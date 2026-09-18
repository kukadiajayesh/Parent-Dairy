import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/config/feature_flags.dart';
import '../core/errors/app_failure.dart';
import '../core/services/ai/ai_activity_log.dart';
import '../core/services/ai/ai_service.dart';
import '../core/services/ai/gemini_client.dart';
import '../core/services/ai/gemini_key_store.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/ai/ai_redaction.dart';
import '../core/services/ai/subject_matcher.dart';
import '../core/services/image_service.dart';
import '../core/services/notice_capture_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/prefs_service.dart';
import '../core/services/telemetry_service.dart';
import '../core/config/grade_scale.dart';
import '../core/theme/subject_hue.dart';
import 'analytics/notice_extractor.dart';
import 'analytics/notice_reminders.dart';
import 'analytics/subject_insights.dart';
import 'models.dart';
import 'models_ai.dart';
import 'repositories/attachment_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/child_repository.dart';
import 'repositories/generated_repository.dart';
import 'repositories/notice_repository.dart';
import 'repositories/record_repository.dart';
import 'repositories/result_repository.dart';
import 'repositories/subject_repository.dart';
import 'repositories/upload_queue.dart';
import 'repositories/year_repository.dart';

/// Timeline filter axes, mirroring the design's `timelineFilter` rows.
class TimelineFilter {
  const TimelineFilter({
    this.subject = 'All',
    this.type = 'All',
    this.date = 'This week',
    this.sortBy = 'Chapter',
  });

  final String subject;
  final String type;
  final String date;
  final String sortBy;

  String get summary => '$subject · $type · $date · sorted by $sortBy';

  bool get isDefault =>
      subject == 'All' && type == 'All' && date == 'This week' && sortBy == 'Chapter';

  TimelineFilter copyWith({String? subject, String? type, String? date, String? sortBy}) =>
      TimelineFilter(
        subject: subject ?? this.subject,
        type: type ?? this.type,
        date: date ?? this.date,
        sortBy: sortBy ?? this.sortBy,
      );
}

/// Where the parent should be sent at launch.
enum AuthStatus { unknown, signedOut, needsChild, ready }

/// Single source of truth for everything the screens read and mutate.
///
/// Still one [ChangeNotifier] behind an [AppScope], exactly as the design build
/// had it — but the lists are now fed by Firestore streams instead of a sample
/// file. The **read** surface is deliberately unchanged (`records`, `subjects`,
/// `activeChild`, `groupBySubject`, …) so every screen that only displays data
/// kept working untouched; only the write paths became async.
class AppState extends ChangeNotifier {
  AppState({
    AuthRepository? auth,
    ChildRepository children = const ChildRepository(),
    SubjectRepository subjects = const SubjectRepository(),
    YearRepository years = const YearRepository(),
    RecordRepository records = const RecordRepository(),
    ResultRepository results = const ResultRepository(),
    GeneratedRepository generated = const GeneratedRepository(),
    NoticeRepository notices = const NoticeRepository(),
    AttachmentRepository? attachments,
    ConnectivityService? connectivity,
    GeminiKeyStore? aiKeys,
    AiService? ai,
    NoticeCaptureService? noticeCapture,
    NoticeReminderScheduler? noticeScheduler,
    DateTime Function()? now,
  }) : _auth = auth ?? AuthRepository(),
       _childRepo = children,
       _subjectRepo = subjects,
       _yearRepo = years,
       _recordRepo = records,
       _resultRepo = results,
       _generatedRepo = generated,
       _noticeRepo = notices,
       _attachmentRepo = attachments ?? AttachmentRepository(),
       _connectivity = connectivity ?? ConnectivityService(),
       _aiKeysOverride = aiKeys,
       _aiOverride = ai,
       _noticeCaptureOverride = noticeCapture,
       _noticeSchedulerOverride = noticeScheduler,
       _now = now ?? DateTime.now {
    uploads = UploadQueue(
      attachments: _attachmentRepo,
      records: _recordRepo,
      offline: _connectivity.offline,
    );
    uploads.addListener(notifyListeners);
    _connectivity.offline.addListener(_onConnectivityChanged);
  }

  final AuthRepository _auth;
  final ChildRepository _childRepo;
  final SubjectRepository _subjectRepo;
  final YearRepository _yearRepo;
  final RecordRepository _recordRepo;
  final ResultRepository _resultRepo;
  final GeneratedRepository _generatedRepo;
  final NoticeRepository _noticeRepo;
  final AttachmentRepository _attachmentRepo;
  final ConnectivityService _connectivity;
  final GeminiKeyStore? _aiKeysOverride;
  final AiService? _aiOverride;
  final NoticeCaptureService? _noticeCaptureOverride;
  final NoticeReminderScheduler? _noticeSchedulerOverride;
  final DateTime Function() _now;

  late final UploadQueue uploads;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<Child>>? _childrenSub;
  StreamSubscription<List<AcademicYear>>? _yearsSub;
  StreamSubscription<List<Subject>>? _subjectsSub;
  StreamSubscription<List<DiaryRecord>>? _recordsSub;
  StreamSubscription<List<ExamResult>>? _resultsSub;
  StreamSubscription<List<GeneratedDoc>>? _generatedSub;
  StreamSubscription<List<CapturedNotice>>? _noticesSub;

  // ── AI (prompt 02) ───────────────────────────────────────────────────────
  //
  // Built lazily: the key store touches the platform keystore and the log
  // needs preferences, neither of which a unit test constructing AppState
  // wants on the first line. Everything AI is reached through these three.

  late final GeminiKeyStore aiKeys = _aiKeysOverride ?? GeminiKeyStore();

  late final AiActivityLog aiLog = AiActivityLog(PrefsService.instance.raw);

  late final AiService ai =
      _aiOverride ??
      AiService(
        client: GeminiClient(
          keys: aiKeys,
          offline: _connectivity.offline,
          fileCache: GeminiFileCache(PrefsService.instance.raw),
        ),
        log: aiLog,
        modelFor: PrefsService.instance.aiModelFor,
      );

  /// The parent's runtime opt-in (More → AI → Use Gemini AI).
  bool get aiEnabled => kAiEnabled && PrefsService.instance.aiEnabled;

  Future<void> setAiEnabled(bool value) async {
    await PrefsService.instance.setAiEnabled(value);
    if (value && !aiKeys.isLoaded) unawaited(aiKeys.load());
    notifyListeners();
  }

  bool get aiConsented => PrefsService.instance.aiConsented;
  DateTime? get aiConsentedAt => PrefsService.instance.aiConsentedAt;

  Future<void> setAiConsented(bool value) async {
    await PrefsService.instance.setAiConsented(value);
    notifyListeners();
  }

  /// Whether an AI entry point should be shown: the build has the layer,
  /// the parent switched it on. Consent is asked at the first action, not
  /// here, so a parent can find the feature before agreeing to it.
  bool get aiAvailable => aiEnabled;

  /// Ready to actually call: switched on, consented, and at least one key.
  bool get aiReady => aiAvailable && aiConsented && aiKeys.keys.isNotEmpty;

  /// "Revoke" in AI settings: keys, cached file URIs, the activity log,
  /// consent and the switch — all of it, in one go.
  Future<void> revokeAi() async {
    await aiKeys.clear();
    await aiLog.clear();
    await PrefsService.instance.clearAiScoped();
    notifyListeners();
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Wires connectivity and the auth listener. Called once from `main`, after
  /// `Firebase.initializeApp`.
  Future<void> bootstrap() async {
    await _connectivity.start();
    if (aiEnabled) {
      // Keys are only needed once the parent has opted in; loading them
      // eagerly on a phone that never uses AI is a keystore prompt for
      // nothing.
      unawaited(aiKeys.load());
    }
    aiKeys.addListener(notifyListeners);
    _authSub = _auth.authStateChanges().listen(_onUserChanged);
    // authStateChanges fires immediately with the restored session, but a cold
    // start with no cached user emits null and would leave status unknown.
    if (!_auth.isSignedIn) _status = AuthStatus.signedOut;
    notifyListeners();
  }

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get authStatus => _status;

  User? get user => _auth.currentUser;
  String? get uid => _auth.uid;
  bool get isSignedIn => _auth.isSignedIn;

  String get parentName {
    final name = user?.displayName?.trim();
    if (name == null || name.isEmpty) return 'Parent';
    return name.split(RegExp(r'\s+')).first;
  }

  String get parentFullName => user?.displayName?.trim().isNotEmpty == true
      ? user!.displayName!.trim()
      : 'Parent';

  String get parentEmail => user?.email ?? '';

  String get parentInitials => Child.initialsFor(parentFullName);

  String? get parentPhotoUrl => user?.photoURL;

  Future<void> signInWithGoogle() async {
    await _auth.signInWithGoogle();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await PrefsService.instance.clearAccountScoped();
  }

  void _onUserChanged(User? user) {
    _cancelDataSubscriptions();
    _children = const [];
    _subjects = const [];
    _records = const [];
    _results = const [];
    _generated = const [];
    _notices = const [];
    _allYearResults = null;
    _years = const [];
    _childId = null;
    _loadingRecords = false;
    _loadingResults = false;
    _loadingNotices = false;
    _noticesPurged = false;

    if (user == null) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    _status = AuthStatus.unknown;
    unawaited(Telemetry.setUser(user.uid));
    _childrenSub = _childRepo
        .watch(user.uid)
        .listen(_onChildren, onError: _onStreamError);
    _yearsSub = _yearRepo
        .watch(user.uid)
        .listen(_onYears, onError: _onStreamError);
    // Notices hang off the parent, not the child, so they subscribe here.
    // Only when capture is on: with it off there is nothing to read and a
    // stream would still cost a listener.
    if (noticeCaptureEnabled) _subscribeNotices(user.uid);
    notifyListeners();
  }

  void _onChildren(List<Child> value) {
    _children = value;

    if (value.isEmpty) {
      _childId = null;
      _status = AuthStatus.needsChild;
      _subjects = const [];
      _records = const [];
      _results = const [];
      notifyListeners();
      return;
    }

    final remembered = PrefsService.instance.childId;
    final stillExists = value.any((c) => c.id == _childId);
    if (!stillExists) {
      _childId =
          value.firstWhere(
            (c) => c.id == remembered,
            orElse: () => value.first,
          ).id;
      _resubscribeChildScoped();
    }

    _status = AuthStatus.ready;
    notifyListeners();
  }

  void _onYears(List<AcademicYear> value) {
    _years = value;
    if (value.isEmpty) return;

    final remembered = PrefsService.instance.year;
    final known = value.map((y) => y.label).toSet();
    if (_activeYear == null || !known.contains(_activeYear)) {
      // Falls back when the remembered year is gone — and persists whatever it
      // lands on, so the very first launch remembers its year too.
      _setActiveYear(
        known.contains(remembered)
            ? remembered!
            : value.firstWhere((y) => y.active, orElse: () => value.first).label,
      );
      _resubscribeChildYearScoped();
    }
    notifyListeners();
  }

  void _onStreamError(Object error, StackTrace stack) {
    _loadingRecords = false;
    _loadingResults = false;
    _lastError = AppFailure.from(error);
    unawaited(Telemetry.recordError(error, stack, context: 'appStateStream'));
    notifyListeners();
  }

  void _resubscribeChildScoped() {
    final uid = _auth.uid;
    final childId = _childId;
    _subjectsSub?.cancel();
    // Drop the previous child's subjects immediately. Holding them until the
    // new stream arrives would briefly offer Class 5's subjects on a Class 2
    // form.
    _subjects = const [];
    if (uid == null || childId == null) return;

    _subjectsSub = _subjectRepo
        .watch(uid, childId)
        .listen((value) {
          _subjects = value;
          notifyListeners();
        }, onError: _onStreamError);

    _generatedSub?.cancel();
    _generated = const [];
    if (kAiEnabled) {
      _generatedSub = _generatedRepo
          .watch(uid: uid, childId: childId)
          .listen((value) {
            _generated = value;
            notifyListeners();
          }, onError: _onStreamError);
    }

    _resubscribeChildYearScoped();
    unawaited(uploads.resume(uid: uid, childId: childId));
  }

  /// Re-runs every query scoped by *both* child and year — records and exam
  /// results. Called whenever either selection changes.
  void _resubscribeChildYearScoped() {
    final uid = _auth.uid;
    final childId = _childId;
    final year = _activeYear;
    _recordsSub?.cancel();
    _resultsSub?.cancel();
    // Same for records: switching child or year must not leave the old list on
    // screen while the new query runs.
    _records = const [];
    _results = const [];
    // The all-years cache belongs to one child; a switch invalidates it.
    _allYearResults = null;
    if (uid == null || childId == null || year == null) {
      _loadingRecords = false;
      _loadingResults = false;
      return;
    }

    _loadingRecords = true;
    _recordsSub = _recordRepo
        .watch(uid: uid, childId: childId, yearLabel: year)
        .listen((value) {
          _records = value;
          _loadingRecords = false;
          notifyListeners();
        }, onError: _onStreamError);

    _loadingResults = true;
    _resultsSub = _resultRepo
        .watch(uid: uid, childId: childId, yearLabel: year)
        .listen((value) {
          _results = value;
          _loadingResults = false;
          notifyListeners();
        }, onError: _onStreamError);
    if (_insightsAllYears) unawaited(_loadAllYearResults());
  }

  /// Retries the child/year streams after an error — what the Performance
  /// tab's error state calls.
  void retryStreams() {
    clearError();
    _resubscribeChildYearScoped();
    notifyListeners();
  }

  void _cancelDataSubscriptions() {
    _childrenSub?.cancel();
    _yearsSub?.cancel();
    _subjectsSub?.cancel();
    _recordsSub?.cancel();
    _resultsSub?.cancel();
    _generatedSub?.cancel();
    _noticesSub?.cancel();
    _childrenSub = null;
    _yearsSub = null;
    _subjectsSub = null;
    _recordsSub = null;
    _resultsSub = null;
    _generatedSub = null;
    _noticesSub = null;
  }

  bool _loadingRecords = false;
  bool get isLoadingRecords => _loadingRecords;

  bool _loadingResults = false;
  bool get isLoadingResults => _loadingResults;

  AppFailure? _lastError;
  AppFailure? get lastError => _lastError;
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  // ── Theme ────────────────────────────────────────────────────────────────
  /// Always follows the device's own setting — there is no in-app override.
  ThemeMode get themeMode => ThemeMode.system;

  // ── Child / year selection ───────────────────────────────────────────────
  List<Child> _children = const [];
  List<Child> get children => List.unmodifiable(_children);
  bool get hasChildren => _children.isNotEmpty;

  String? _childId;

  /// Shown before the first child stream arrives. Never persisted — it exists
  /// so the shell can build one frame without a null check in 20 widgets.
  static const _placeholderChild = Child(
    name: '—',
    initials: '—',
    school: '',
    grade: '',
    section: '',
    year: '',
  );

  Child get activeChild {
    if (_children.isEmpty) return _placeholderChild;
    return _children.firstWhere(
      (c) => c.id == _childId,
      orElse: () => _children.first,
    );
  }

  int get activeChildIndex {
    final index = _children.indexWhere((c) => c.id == _childId);
    return index == -1 ? 0 : index;
  }

  void selectChild(int index) {
    if (index < 0 || index >= _children.length) return;
    final child = _children[index];
    if (child.id == _childId) return;
    _childId = child.id;
    unawaited(PrefsService.instance.setChildId(child.id));
    _resubscribeChildScoped();
    notifyListeners();
  }

  List<AcademicYear> _years = const [];
  List<AcademicYear> get years => List.unmodifiable(_years);

  String? _activeYear;
  String get activeYear => _activeYear ?? activeChild.year;

  void selectYear(String label) {
    if (label == _activeYear) return;
    final uid = _auth.uid;
    if (uid == null) return;
    _setActiveYear(label);
    unawaited(_yearRepo.setActive(uid, label));
    _resubscribeChildYearScoped();
    notifyListeners();
  }

  /// The year a dated document belongs to (§G): whichever known year's
  /// April–March span contains [date], else the active year. A report card
  /// dated last March files under last year even if this year is selected.
  String yearLabelFor(DateTime date) {
    for (final year in _years) {
      if (year.contains(date)) return year.label;
    }
    return activeYear;
  }

  /// One place that assigns the active year, so it is never changed without
  /// also being remembered for the next launch (§37).
  void _setActiveYear(String label) {
    _activeYear = label;
    unawaited(PrefsService.instance.setYear(label));
  }

  Future<void> addYear(AcademicYear year, {required bool makeActive}) async {
    final uid = _auth.uid;
    if (uid == null) return;
    await _yearRepo.create(uid, year.copyWith(active: makeActive));
    if (makeActive) {
      _setActiveYear(year.label);
      _resubscribeChildYearScoped();
    }
    unawaited(Telemetry.yearCreated());
    notifyListeners();
  }

  // ── Children management ──────────────────────────────────────────────────
  Future<Child> saveChild(Child child, {PickedAttachment? photo}) async {
    final uid = _auth.uid;
    if (uid == null) throw AppFailure.cancelled;

    if (child.id.isEmpty) {
      final created = await _childRepo.create(uid, child);
      await _subjectRepo.seedDefaults(uid, created.id);
      await _yearRepo.seedIfEmpty(uid, created.year);
      await _attachPhoto(uid, created, photo);
      _childId = created.id;
      await PrefsService.instance.setChildId(created.id);
      if (_activeYear == null) _setActiveYear(created.year);
      _resubscribeChildScoped();
      unawaited(Telemetry.childCreated(_children.length + 1));
      return created;
    }

    await _childRepo.update(uid, child);
    await _attachPhoto(uid, child, photo);
    return child;
  }

  /// Uploaded after the profile exists, so the file lands under the child's own
  /// folder. A failed photo never fails the save — the profile is the point.
  Future<void> _attachPhoto(
    String uid,
    Child child,
    PickedAttachment? photo,
  ) async {
    if (photo == null) return;
    try {
      final url = await _attachmentRepo.uploadChildPhoto(
        uid: uid,
        childId: child.id,
        file: photo.file,
      );
      await _childRepo.update(uid, child.copyWith(photoUrl: url));
    } catch (error, stack) {
      unawaited(
        Telemetry.recordError(error, stack, context: 'uploadChildPhoto'),
      );
    }
  }

  Future<void> deleteChild(String childId) async {
    final uid = _auth.uid;
    if (uid == null) return;
    await _childRepo.delete(uid, childId);
  }

  /// The active child's grade scale — what resolves a report-card grade to a
  /// percent for every new result.
  GradeScale get gradeScale => activeChild.gradeScale;

  Future<void> setGradeScale(String scaleId) async {
    final uid = _auth.uid;
    final child = activeChild;
    if (uid == null || child.id.isEmpty) return;
    if (child.gradeScaleId == scaleId) return;
    await _childRepo.update(uid, child.copyWith(gradeScaleId: scaleId));
  }

  // ── Subjects ─────────────────────────────────────────────────────────────
  List<Subject> _subjects = const [];
  List<Subject> get subjects => List.unmodifiable(_subjects);
  List<String> get subjectNames => _subjects.map((s) => s.name).toList();

  Subject subjectByName(String name) => _subjects.firstWhere(
    (s) => s.name == name,
    orElse: () => Subject(
      name: name,
      abbr: name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase(),
      hue: SubjectHue.stone,
      order: _subjects.length + 1,
    ),
  );

  /// §11/§37: the subject a form should pre-select.
  String get suggestedSubject {
    final last = PrefsService.instance.lastSubject;
    if (last != null && _subjects.any((s) => s.name == last)) return last;
    return _subjects.isEmpty ? '' : _subjects.first.name;
  }

  Future<void> addSubject(Subject subject) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return;
    await _subjectRepo.create(
      uid,
      childId,
      subject.copyWith(order: _subjects.length + 1),
    );
    unawaited(Telemetry.subjectCreated());
  }

  Future<void> removeSubject(String name) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return;
    final match = _subjects.where((s) => s.name == name).firstOrNull;
    if (match == null) return;
    await _subjectRepo.deactivate(uid, childId, match.id);
  }

  Future<void> reorderSubjects(List<Subject> ordered) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return;
    _subjects = ordered;
    notifyListeners();
    await _subjectRepo.reorder(uid, childId, ordered);
  }

  // ── Records ──────────────────────────────────────────────────────────────
  List<DiaryRecord> _records = const [];
  List<DiaryRecord> get records => List.unmodifiable(_records);

  /// The derived slices below are memoised against the identity of
  /// [_records], which only changes when a Firestore snapshot lands. Every
  /// screen reads two or three of them from `build()`, and each of the
  /// connectivity, upload-queue and key-store ticks used to re-filter and
  /// re-sort the whole year for nothing (prompt 04 §1.4). Returning the same
  /// list instance also lets [groupBySubject] key its own cache on identity.
  final _RecordsMemo _memo = _RecordsMemo();

  List<DiaryRecord> get worksheets => _memo.worksheets(
    _records,
    () => _records.where((r) => r.type == RecordType.worksheet).toList(),
  );

  List<DiaryRecord> get classwork => _memo.classwork(
    _records,
    () => _records.where((r) => r.type == RecordType.classwork).toList(),
  );

  /// Newest first — the order the timeline and "Recent activity" use.
  List<DiaryRecord> get recordsByDateDesc => _memo.byDateDesc(
    _records,
    () => _records.toList()..sort((a, b) => b.date.compareTo(a.date)),
  );

  /// The clock the app runs on: injectable for tests, wall clock otherwise.
  /// Screens that compare against "today" read this, never a pinned date.
  DateTime get now => _now();

  List<DiaryRecord> get pendingWorksheets =>
      worksheets.where((w) => w.status == WorksheetStatus.pending).toList()
        ..sort((a, b) => (a.dueDate ?? a.date).compareTo(b.dueDate ?? b.date));

  DiaryRecord? recordById(String id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The most recently updated hard-words file already attached to a worksheet
  /// covering [chapter], so a second worksheet on the same chapter can reuse it
  /// instead of asking the parent to attach it again.
  Attachment? hardWordsForChapter(String chapter, {String? excludeRecordId}) {
    final matches =
        worksheets.where(
          (r) =>
              r.id != excludeRecordId &&
              r.hardWords != null &&
              r.chapters.contains(chapter),
        ).toList()..sort(
          (a, b) => (b.updatedAt ?? b.date).compareTo(a.updatedAt ?? a.date),
        );
    return matches.firstOrNull?.hardWords;
  }

  /// Saves a worksheet or classwork entry and queues its files.
  ///
  /// Returns as soon as Firestore has accepted the document — which it does
  /// from cache when offline — so the parent is never left waiting on a
  /// network. Uploads continue in [uploads].
  Future<DiaryRecord> saveRecord(
    DiaryRecord record, {
    List<PickedAttachment> newFiles = const [],
    PickedAttachment? newAnswerKey,
    PickedAttachment? newHardWords,
    PickedAttachment? newExamTimetable,
    bool fromShare = false,
  }) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) {
      throw const AppFailure(
        FailureKind.sessionExpired,
        'Please sign in again to save this record.',
      );
    }

    final staged = <Attachment>[
      ...record.attachments,
      for (var i = 0; i < newFiles.length; i++)
        AttachmentRepository.stage(
          newFiles[i],
          caption: record.isWorksheet
              ? 'Page ${record.attachments.length + i + 1}'
              : 'Photo ${record.attachments.length + i + 1}',
        ),
    ];

    final answerKey = newAnswerKey == null
        ? record.answerKey
        : AttachmentRepository.stage(
            newAnswerKey,
            caption: ImageService.humanSize(newAnswerKey.bytes),
          );

    final hardWords = newHardWords == null
        ? record.hardWords
        : AttachmentRepository.stage(
            newHardWords,
            caption: ImageService.humanSize(newHardWords.bytes),
          );

    final examTimetable = newExamTimetable == null
        ? record.examTimetable
        : AttachmentRepository.stage(
            newExamTimetable,
            caption: ImageService.humanSize(newExamTimetable.bytes),
          );

    final prepared = record.copyWith(
      childId: childId,
      academicYearId: record.academicYearId.isEmpty
          ? activeYear
          : record.academicYearId,
      attachments: staged,
      answerKey: answerKey,
      hardWords: hardWords,
      examTimetable: examTimetable,
    );

    final saved = await _recordRepo.save(
      uid: uid,
      childId: childId,
      record: prepared,
    );

    unawaited(PrefsService.instance.setLastSubject(saved.subject));
    if (record.id.isEmpty) {
      unawaited(_yearRepo.bumpRecordCount(uid, saved.academicYearId, 1));
      unawaited(
        Telemetry.recordCreated(
          type: saved.type.wire,
          attachmentCount: saved.allFiles.length,
          fromShare: fromShare,
        ),
      );
    }

    uploads.enqueue(uid: uid, childId: childId, record: saved);

    // §24: a worksheet with a due date arms its own reminder. Rescheduling on
    // every save keeps an edited due date in step and replaces the old alarm.
    unawaited(
      NotificationService.instance.scheduleWorksheetReminder(saved),
    );
    // An exam reminds at the exam offsets on the school-notices channel,
    // whether it was typed in, converted from a notice or read off a
    // timetable.
    if (saved.isExam) {
      unawaited(
        NotificationService.instance.scheduleExamReminders(saved, offsets: noticeOffsets),
      );
    }
    return saved;
  }

  /// One exam record per timetable row (the Add Exam form's "read with AI"
  /// path): every record carries the same timetable image and the whole
  /// date sheet in its notes, so any one of them shows the full schedule.
  Future<List<DiaryRecord>> saveTimetableExams({
    required List<({String subject, DateTime date})> entries,
    required String examType,
    required Attachment timetable,
    List<Attachment> previousPapers = const [],
    String scheduleNotes = '',
    String model = '',
  }) async {
    final saved = <DiaryRecord>[];
    for (final e in entries) {
      final record = await saveRecord(
        DiaryRecord(
          id: '',
          type: RecordType.exam,
          subject: e.subject,
          title: examType,
          examType: examType,
          date: e.date,
          // A fresh id per record: the file is uploaded under each record's
          // own folder, so one shared attachment id would collide.
          examTimetable: timetable.copyWith(id: '${timetable.id}-${saved.length}'),
          attachments: saved.isEmpty ? previousPapers : const [],
          notes: [
            if (model.isNotEmpty) 'Timetable read by $model — check the dates.',
            if (scheduleNotes.isNotEmpty) scheduleNotes,
          ].join('\n'),
          origin: model.isEmpty ? RecordOrigin.manual : RecordOrigin.ai,
        ),
      );
      saved.add(record);
    }
    return saved;
  }

  /// Soft delete (§30) — the record leaves every list but stays recoverable.
  Future<void> deleteRecord(String id) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return;

    final record = recordById(id);
    await _recordRepo.softDelete(uid: uid, childId: childId, recordId: id);
    unawaited(NotificationService.instance.cancelWorksheetReminder(id));
    unawaited(NotificationService.instance.cancelExamReminders(id));
    if (record != null) {
      unawaited(_yearRepo.bumpRecordCount(uid, record.academicYearId, -1));
      unawaited(Telemetry.recordDeleted(record.type.wire));
    }
  }

  Future<void> restoreRecord(String id) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return;
    await _recordRepo.restore(uid: uid, childId: childId, recordId: id);
  }

  Future<void> markCompleted(String id, {bool completed = true}) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return;
    await _recordRepo.markCompleted(
      uid: uid,
      childId: childId,
      recordId: id,
      completed: completed,
    );
    if (completed) {
      // A finished worksheet must not nag on its due date.
      unawaited(NotificationService.instance.cancelWorksheetReminder(id));
      unawaited(Telemetry.worksheetCompleted());
    } else {
      final record = recordById(id);
      if (record != null) {
        unawaited(
          NotificationService.instance.scheduleWorksheetReminder(
            record.copyWith(status: WorksheetStatus.pending),
          ),
        );
      }
    }
  }

  /// §15. Scoped to the active year unless [allYears] is set.
  Future<List<DiaryRecord>> search(
    String query, {
    bool allYears = false,
  }) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return const [];
    unawaited(Telemetry.searchPerformed(allYears: allYears));
    return _recordRepo.search(
      uid: uid,
      childId: childId,
      query: query,
      yearLabel: allYears ? null : activeYear,
    );
  }

  // ── Exam results ─────────────────────────────────────────────────────────
  List<ExamResult> _results = const [];

  /// The active year's results, as the stream delivered them (newest first).
  List<ExamResult> get results => List.unmodifiable(_results);

  List<ExamResult> get resultsByDateDesc =>
      _results.toList()..sort((a, b) => b.date.compareTo(a.date));

  ExamResult? get latestResult => resultsByDateDesc.firstOrNull;

  /// Looks in the active year first, then the all-years cache, so a detail
  /// screen opened from the all-years view still resolves.
  ExamResult? resultById(String id) {
    for (final r in _results) {
      if (r.id == id) return r;
    }
    for (final r in _allYearResults ?? const <ExamResult>[]) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Results that could be the same report card entered twice (§G): same
  /// label, same day, and not the one being edited.
  List<ExamResult> duplicatesOf(ExamResult draft) => _results
      .where(
        (r) =>
            r.id != draft.id &&
            r.examLabel.trim().toLowerCase() ==
                draft.examLabel.trim().toLowerCase() &&
            r.date.year == draft.date.year &&
            r.date.month == draft.date.month &&
            r.date.day == draft.date.day,
      )
      .toList();

  /// Saves a result, stamping the child, the year its date falls in (§G) and
  /// the child's grade scale. Like [saveRecord], returns as soon as Firestore
  /// accepts the write — which it does from cache when offline.
  Future<ExamResult> saveResult(ExamResult result) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) {
      throw const AppFailure(
        FailureKind.sessionExpired,
        'Please sign in again to save these marks.',
      );
    }

    final prepared = result.copyWith(
      childId: childId,
      academicYearId: yearLabelFor(result.date),
      // A scanned result keeps the scale it was reviewed under; a manual one
      // always takes the child's current setting.
      gradeScaleId: result.id.isEmpty ? gradeScale.id : result.gradeScaleId,
    );

    final saved = await _resultRepo.save(
      uid: uid,
      childId: childId,
      result: prepared,
    );
    if (result.id.isEmpty) {
      unawaited(
        Telemetry.resultCreated(
          subjectCount: saved.scores.length,
          source: saved.source.wire,
        ),
      );
    }
    // A result outside the active year never arrives on the stream, so the
    // all-years cache is the only place it would show; drop it to refetch.
    _allYearResults = null;
    if (_insightsAllYears) unawaited(_loadAllYearResults());
    return saved;
  }

  /// Soft delete — the result leaves the tab but stays recoverable.
  Future<void> deleteResult(String id) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return;
    await _resultRepo.softDelete(uid: uid, childId: childId, resultId: id);
    _allYearResults = null;
    unawaited(Telemetry.resultDeleted());
  }

  Future<void> restoreResult(String id) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return;
    await _resultRepo.restore(uid: uid, childId: childId, resultId: id);
    _allYearResults = null;
  }

  Future<List<ExamResult>> searchResults(
    String query, {
    bool allYears = false,
  }) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return const [];
    return _resultRepo.search(
      uid: uid,
      childId: childId,
      query: query,
      yearLabel: allYears ? null : activeYear,
    );
  }

  /// Marks a scanned result as checked. Editing and saving does the same
  /// through [saveResult]; this is the one-tap version on the detail screen.
  Future<void> confirmResult(String id) async {
    final result = resultById(id);
    if (result == null || !result.needsReview) return;
    await saveResult(result.copyWith(needsReview: false));
  }

  // ── AI artefacts (prompt 02) ─────────────────────────────────────────────
  List<GeneratedDoc> _generated = const [];

  /// Every structured AI artefact for the active child, newest first.
  List<GeneratedDoc> get generated => List.unmodifiable(_generated);

  GeneratedDoc? generatedById(String id) =>
      _generated.where((g) => g.id == id).firstOrNull;

  /// The artefacts filed under a record: a scanned paper, its answer key,
  /// its grading.
  List<GeneratedDoc> generatedForRecord(String recordId) => _generated
      .where((g) => g.recordId == recordId || g.examRecordId == recordId)
      .toList();

  GeneratedDoc? scannedPaperFor(String recordId) => generatedForRecord(recordId)
      .where((g) => g.kind == GeneratedKind.scannedPaper)
      .firstOrNull;

  /// Chapters seen on this year's records, per subject — the generator's
  /// fallback when a subject has no focus chapters.
  Map<String, List<String>> get chaptersBySubject {
    final out = <String, Set<String>>{};
    for (final r in _records) {
      out.putIfAbsent(r.subject, () => {}).addAll(r.chapters);
    }
    return {
      for (final e in out.entries) e.key: (e.value.toList()..sort()),
    };
  }

  /// The last [limit] worksheet/classwork records for a subject, preferring
  /// those tagged with any of [chapters] — the generator's default sources.
  List<DiaryRecord> sourceRecordsFor(
    String subject, {
    List<String> chapters = const [],
    int limit = 8,
  }) {
    final candidates = _records
        .where(
          (r) =>
              r.subject == subject &&
              !r.isExam &&
              r.attachments.isNotEmpty,
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (chapters.isEmpty) return candidates.take(limit).toList();
    final tagged = candidates
        .where((r) => r.chapters.any(chapters.contains))
        .toList();
    final rest = candidates.where((r) => !tagged.contains(r)).toList();
    return [...tagged, ...rest].take(limit).toList();
  }

  Future<GeneratedDoc> _saveGenerated(GeneratedDoc doc) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) {
      throw const AppFailure(
        FailureKind.sessionExpired,
        'Please sign in again to save this.',
      );
    }
    return _generatedRepo.save(uid: uid, childId: childId, doc: doc);
  }

  /// Files a generated paper as a real worksheet record with its PDF, and
  /// keeps the structured JSON beside it. Returns the record.
  Future<DiaryRecord> saveGeneratedPaper({
    required GeneratedPaper paper,
    required PaperConfig config,
    required List<int> pdfBytes,
  }) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) {
      throw const AppFailure(
        FailureKind.sessionExpired,
        'Please sign in again to save this paper.',
      );
    }
    final safeTitle = paper.title
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    final pdf = await ImageService.stageBytes(
      pdfBytes,
      '${safeTitle.isEmpty ? 'practice' : safeTitle}.pdf',
    );
    final doc = await _saveGenerated(
      GeneratedDoc(
        id: '',
        childId: childId,
        kind: GeneratedKind.paper,
        title: paper.title,
        subject: config.subject,
        payload: {...paper.toJson(), 'config': config.toJson()},
        model: paper.model,
      ),
    );
    final record = await saveRecord(
      DiaryRecord(
        id: '',
        type: RecordType.worksheet,
        subject: config.subject,
        title: paper.title,
        date: DateTime.now(),
        chapters: config.chapters,
        notes: 'AI-generated ${config.output.label.toLowerCase()} '
            '(${paper.model}). Check the questions before use.',
        origin: RecordOrigin.ai,
      ),
      newFiles: [pdf],
    );
    unawaited(
      _generatedRepo.link(
        uid: uid,
        childId: childId,
        generatedId: doc.id,
        recordId: record.id,
      ),
    );
    return record;
  }

  /// Files a scanned exam paper: an exam record carrying the page images,
  /// plus the structured questions beside it.
  Future<({DiaryRecord record, GeneratedDoc doc})> saveScannedPaper({
    required ScannedPaper paper,
    required List<PickedAttachment> pages,
    required String subject,
    required String examType,
    required DateTime date,
  }) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) {
      throw const AppFailure(
        FailureKind.sessionExpired,
        'Please sign in again to save this paper.',
      );
    }
    final record = await saveRecord(
      DiaryRecord(
        id: '',
        type: RecordType.exam,
        subject: subject,
        title: '$examType · $subject',
        date: date,
        examType: examType,
        notes: 'Scanned exam paper · ${paper.questions.length} questions read by '
            '${paper.model}.',
        origin: RecordOrigin.ai,
      ),
      newFiles: pages,
    );
    final doc = await _saveGenerated(
      GeneratedDoc(
        id: '',
        childId: childId,
        kind: GeneratedKind.scannedPaper,
        title: '$examType · $subject',
        subject: subject,
        payload: paper.toJson(),
        recordId: record.id,
        examRecordId: record.id,
        model: paper.model,
      ),
    );
    return (record: record, doc: doc);
  }

  /// Attaches an AI answer key PDF to an exam record and keeps its JSON.
  Future<void> saveAnswerKey({
    required DiaryRecord record,
    required ScannedPaper paper,
    required AnswerKey key,
    required List<int> pdfBytes,
  }) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) {
      throw const AppFailure(
        FailureKind.sessionExpired,
        'Please sign in again to save this answer key.',
      );
    }
    final pdf = await ImageService.stageBytes(pdfBytes, 'answer-key-ai.pdf');
    await saveRecord(record, newAnswerKey: pdf);
    await _saveGenerated(
      GeneratedDoc(
        id: '',
        childId: childId,
        kind: GeneratedKind.answerKey,
        title: 'Answer key · ${record.title}',
        subject: record.subject,
        payload: key.toJson(),
        recordId: record.id,
        examRecordId: record.id,
        model: key.model,
      ),
    );
  }

  /// Saves a grading as an [ExamResult] (`scanned`, `needsReview`) linked to
  /// the exam record, and keeps the per-question breakdown beside it.
  Future<ExamResult> saveGradedPaper({
    required DiaryRecord record,
    required GradedPaper graded,
    required String examLabel,
  }) async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) {
      throw const AppFailure(
        FailureKind.sessionExpired,
        'Please sign in again to save this result.',
      );
    }
    final result = await saveResult(
      ExamResult(
        id: '',
        childId: childId,
        academicYearId: '',
        examLabel: examLabel,
        date: record.date,
        examRecordId: record.id,
        scores: [
          SubjectScore(
            subject: record.subject,
            marks: graded.awarded,
            maxMarks: graded.outOf,
            remarks: 'Graded by AI from a scanned paper · check before relying on it',
          ),
        ],
        source: ResultSource.scanned,
        extractionConfidence: 0.7,
        needsReview: true,
        gradeScaleId: gradeScale.id,
      ),
    );
    await _saveGenerated(
      GeneratedDoc(
        id: '',
        childId: childId,
        kind: GeneratedKind.gradedPaper,
        title: 'Grading · ${record.title}',
        subject: record.subject,
        payload: graded.toJson(),
        recordId: record.id,
        examRecordId: record.id,
        resultId: result.id,
        model: graded.model,
      ),
    );
    return result;
  }


  // ── Notification capture (prompt 03) ─────────────────────────────────────
  //
  // Android-only. The native listener buffers captures while Flutter is not
  // running; [drainNotices] pulls them in on start and on every resume,
  // runs the extractor, applies the auto-arm policy and writes to
  // `users/{uid}/notices`. Everything here degrades to a no-op on iOS.

  late final NoticeCaptureService noticeCapture =
      _noticeCaptureOverride ?? NoticeCaptureService();

  late final NoticeReminderScheduler _noticeScheduler =
      _noticeSchedulerOverride ?? NotificationService.instance;

  List<CapturedNotice> _notices = const [];
  bool _loadingNotices = false;
  bool _noticesPurged = false;
  bool _draining = false;

  /// Every non-deleted notice, newest posted first.
  List<CapturedNotice> get notices => List.unmodifiable(_notices);
  bool get isLoadingNotices => _loadingNotices;

  bool get noticeCaptureSupported => noticeCapture.isSupported;

  /// The master switch (Settings → Notification capture).
  bool get noticeCaptureEnabled =>
      noticeCaptureSupported && PrefsService.instance.noticesEnabled;

  /// Switched on *and* granted in system settings.
  bool get noticeCaptureActive => noticeCaptureEnabled && noticeCapture.isGranted;

  /// Needs a tap: kind or date read, but not confidently enough to arm.
  List<CapturedNotice> get noticeInbox => _notices.where((n) => n.inInbox).toList();
  int get noticeInboxCount => noticeInbox.length;

  /// Confirmed, with an event today or later, soonest first.
  List<CapturedNotice> get upcomingNotices {
    final now = _now();
    return _notices.where((n) => n.isUpcoming(now)).toList()
      ..sort((a, b) => a.date!.compareTo(b.date!));
  }

  /// The home strip: confirmed notices in the next fourteen days.
  List<CapturedNotice> get upcomingFromSchool {
    final limit = _now().add(const Duration(days: 14));
    return upcomingNotices.where((n) => !n.date!.isAfter(limit)).toList();
  }

  CapturedNotice? noticeById(String id) =>
      _notices.where((n) => n.id == id).firstOrNull;

  void _subscribeNotices(String uid) {
    _noticesSub?.cancel();
    _loadingNotices = true;
    _noticesSub = _noticeRepo.watch(uid).listen((value) {
      _notices = value;
      _loadingNotices = false;
      notifyListeners();
    }, onError: (Object error, StackTrace stack) {
      _loadingNotices = false;
      _onStreamError(error, stack);
    });
  }

  /// Retries the notices stream after an error.
  void retryNotices() {
    final uid = _auth.uid;
    if (uid == null) return;
    clearError();
    _subscribeNotices(uid);
    notifyListeners();
  }

  Future<void> setNoticeCaptureEnabled(bool value) async {
    final uid = _auth.uid;
    await PrefsService.instance.setNoticesEnabled(value);
    if (value) {
      await _syncWatchedPackages();
      if (uid != null) _subscribeNotices(uid);
      await refreshNoticeCapture();
    } else {
      // The listener stays bound (that is the OS's permission, not ours)
      // but with an empty opt-in set it captures nothing.
      await noticeCapture.setWatchedPackages(const []);
      _noticesSub?.cancel();
      _noticesSub = null;
      _notices = const [];
      _loadingNotices = false;
    }
    notifyListeners();
  }

  bool get noticeDisclosureAccepted =>
      PrefsService.instance.noticeDisclosureAt != null;

  Future<void> acceptNoticeDisclosure() async {
    await PrefsService.instance.setNoticeDisclosureAccepted();
    notifyListeners();
  }

  // ── watched apps and rules ──

  List<String> get watchedPackages => PrefsService.instance.noticePackages;

  NoticeAppRule noticeRuleFor(String packageName) =>
      PrefsService.instance.noticeRules[packageName] ?? NoticeAppRule.all;

  Future<void> setWatchedPackages(List<String> packages) async {
    await PrefsService.instance.setNoticePackages(packages);
    await _syncWatchedPackages();
    notifyListeners();
  }

  Future<void> setNoticeRule(String packageName, NoticeAppRule rule) async {
    await PrefsService.instance.setNoticeRule(packageName, rule);
    await _syncWatchedPackages();
    notifyListeners();
  }

  /// Writes the opt-in set the native listener reads: every ticked app
  /// whose rule is not "off".
  Future<void> _syncWatchedPackages() async {
    if (!noticeCaptureEnabled) return;
    final rules = PrefsService.instance.noticeRules;
    await noticeCapture.setWatchedPackages([
      for (final p in watchedPackages)
        if ((rules[p] ?? NoticeAppRule.all) != NoticeAppRule.off) p,
    ]);
  }

  /// Packages that have actually posted a captured notice, most recent
  /// first — the picker floats these to the top.
  List<String> get packagesWithCaptures {
    final seen = <String>{};
    return [for (final n in _notices) if (seen.add(n.packageName)) n.packageName];
  }

  // ── app → child ──

  /// The child an app's notices default to: the remembered mapping, else
  /// the only child, else nothing (the parent is asked on confirm).
  String? childIdForPackage(String packageName) {
    final mapped = PrefsService.instance.noticeChildMap[packageName];
    if (mapped != null && _children.any((c) => c.id == mapped)) return mapped;
    if (_children.length == 1) return _children.first.id;
    return null;
  }

  Future<void> rememberNoticeChild(String packageName, String childId) =>
      PrefsService.instance.setNoticeChild(packageName, childId);

  // ── reminder offsets ──

  Map<NoticeKind, List<int>> get noticeOffsets => {
    ...NoticeReminders.defaultOffsets,
    ...?PrefsService.instance.noticeOffsets,
  };

  Future<void> setNoticeOffsets(NoticeKind kind, List<int> days) async {
    await PrefsService.instance.setNoticeOffsets(kind, days);
    notifyListeners();
  }

  int get noticeRetentionDays => PrefsService.instance.noticeRetentionDays;

  Future<void> setNoticeRetentionDays(int days) async {
    await PrefsService.instance.setNoticeRetentionDays(days);
    notifyListeners();
    unawaited(purgeOldNotices(force: true));
  }

  /// §F: granted, apps ticked, and nothing captured in fourteen days — the
  /// OEM's battery manager has probably killed the listener.
  bool get noticeBatteryHintDue {
    if (!noticeCaptureActive || watchedPackages.isEmpty) return false;
    if (PrefsService.instance.noticeBatteryHintShown) return false;
    final since = noticeCapture.lastCaptureAt ?? PrefsService.instance.noticesEnabledAt;
    if (since == null) return false;
    return _now().difference(since) > const Duration(days: 14);
  }

  Future<void> dismissNoticeBatteryHint() async {
    await PrefsService.instance.setNoticeBatteryHintShown();
    notifyListeners();
  }

  // ── drain ──

  /// Re-checks the permission and drains the buffer. Called on start and
  /// on every resume.
  Future<void> refreshNoticeCapture() async {
    if (!noticeCaptureEnabled) return;
    await noticeCapture.refresh();
    await drainNotices();
    notifyListeners();
  }

  /// Pulls buffered captures in, extracts, applies the auto-arm policy and
  /// writes. Idempotent: every hash is checked against stored notices
  /// first, so a re-post after the buffer was cleared is not a second
  /// document. Returns how many new notices were stored.
  Future<int> drainNotices() async {
    final uid = _auth.uid;
    if (uid == null || !noticeCaptureEnabled || _draining) return 0;
    _draining = true;
    try {
      final raw = await noticeCapture.drain();
      if (raw.isEmpty) return 0;

      // The stream may not have delivered yet on a cold start; ask the
      // repository too rather than trusting an empty list.
      final known = <String>{for (final n in _notices) n.sourceHash};
      if (_notices.isEmpty) known.addAll(await _noticeRepo.knownHashes(uid));

      final now = _now();
      final rules = PrefsService.instance.noticeRules;
      var added = 0;
      final lowConfidence = <CapturedNotice>[];
      for (final r in raw) {
        if (known.contains(r.hash)) continue;
        final rule = rules[r.packageName] ?? NoticeAppRule.all;
        if (rule == NoticeAppRule.off) continue;
        if (rule == NoticeAppRule.keywords &&
            !NoticeExtractor.looksLikeNotice('${r.title}\n${r.body}')) {
          continue;
        }
        final childId = childIdForPackage(r.packageName);
        final extraction = NoticeExtractor.extract(
          title: r.title,
          body: r.body,
          postedAt: r.postedAt,
          subjects: _subjectsFor(childId),
        );
        final notice = CapturedNotice(
          id: '',
          packageName: r.packageName,
          appLabel: r.appLabel,
          title: r.title,
          body: r.body,
          postedAt: r.postedAt,
          sourceHash: r.hash,
          childId: childId,
          extraction: extraction,
          truncated: r.truncated,
        );
        try {
          final saved = await _saveWithPolicy(uid, notice, now);
          known.add(r.hash);
          added++;
          if (extraction.confidence < 0.7) lowConfidence.add(saved);
        } catch (error, stack) {
          unawaited(Telemetry.recordError(error, stack, context: 'noticeDrain'));
        }
      }
      unawaited(PrefsService.instance.setNoticeLastDrainAt(now));
      if (lowConfidence.isNotEmpty) unawaited(_classifyNotices(lowConfidence));
      return added;
    } catch (error, stack) {
      _lastError = AppFailure.from(error);
      unawaited(Telemetry.recordError(error, stack, context: 'noticeDrain'));
      return 0;
    } finally {
      _draining = false;
      notifyListeners();
    }
  }

  /// Subject names for matching: the active child's when the notice is
  /// theirs or unassigned. Another child's subjects are not loaded, so a
  /// notice for them matches on the built-in list only.
  List<String> _subjectsFor(String? childId) =>
      childId == null || childId == _childId ? subjectNames : const [];

  /// §D. Auto-arms when the policy allows and the scheduler actually
  /// scheduled something; otherwise the notice lands as needs-review.
  Future<CapturedNotice> _saveWithPolicy(
    String uid,
    CapturedNotice notice,
    DateTime now,
  ) async {
    final extraction = notice.extraction!;
    final decision = NoticeReminders.decide(
      extraction,
      now: now,
      autoArmedThisWeek: PrefsService.instance.noticeAutoArmed(now).length,
    );
    var toSave = notice.id.isEmpty ? notice.copyWith(id: notice.sourceHash) : notice;
    if (decision == NoticeArmDecision.auto) {
      final times = NoticeReminders.timesFor(extraction, now: now, offsets: noticeOffsets);
      final ids = await _noticeScheduler.scheduleNoticeReminders(toSave, times);
      if (ids.isNotEmpty) {
        toSave = toSave.copyWith(
          status: NoticeStatus.confirmed,
          reminderIds: ids,
          autoArmedAt: now,
        );
        await PrefsService.instance.recordNoticeAutoArmed(now);
        unawaited(_noticeScheduler.showNoticeArmed(toSave));
      }
    }
    return _noticeRepo.save(uid: uid, notice: toSave);
  }

  /// Stage 2 (§C): the cheap classification model, only for notices the
  /// rules read below 0.7, only with AI on and a key, at most fifty calls a
  /// day, ten notices per call. Any failure is silent — falling back to the
  /// inbox is normal, not an error.
  Future<void> _classifyNotices(List<CapturedNotice> pending) async {
    final uid = _auth.uid;
    if (uid == null || !aiReady || isOffline) return;
    final child = activeChild;
    if (child.id.isEmpty) return;
    final now = _now();
    var budget = 50 - PrefsService.instance.noticeAiCallsToday(now);
    for (var i = 0; i < pending.length && budget > 0; i += 10, budget--) {
      final batch = pending.skip(i).take(10).toList();
      await PrefsService.instance.recordNoticeAiCall(now);
      final Map<String, NoticeModelReading> readings;
      try {
        readings = await ai.classifyNotices(
          notices: [
            for (final n in batch)
              (
                id: n.id,
                title: _scrubForFamily(n.title),
                body: _scrubForFamily(n.body),
                postedAt: n.postedAt,
              ),
          ],
          child: child,
          subjects: subjectNames,
        );
      } catch (_) {
        return;
      }
      for (final n in batch) {
        final reading = readings[n.id];
        final current = noticeById(n.id) ?? n;
        // The parent may have acted in the meantime; never overwrite that.
        if (reading == null || !current.needsReview) continue;
        final merged = _mergeReading(current, reading);
        if (merged == null) continue;
        try {
          await _saveWithPolicy(uid, current.copyWith(extraction: merged), now);
        } catch (error, stack) {
          unawaited(Telemetry.recordError(error, stack, context: 'noticeClassify'));
        }
      }
    }
    notifyListeners();
  }

  /// Every child's identifiers, not just the active one's — a sibling's
  /// name in a notice is just as private.
  String _scrubForFamily(String text) {
    var out = text;
    for (final c in _children) {
      out = AiRedaction.scrub(out, c);
    }
    return out;
  }

  /// Applies the same validation as stage 1 to a model reading: a date in
  /// the past or more than a year out is discarded, not trusted, and a
  /// reading no surer than the rules is ignored.
  NoticeExtraction? _mergeReading(CapturedNotice notice, NoticeModelReading r) {
    final old = notice.extraction;
    if (old != null && r.confidence <= old.confidence) return null;
    if (r.kind == NoticeKind.unknown && r.eventDate == null && r.dueDate == null) return null;

    DateTime? stamp(DateTime? d) {
      if (!NoticeReminders.acceptableDate(d, postedAt: notice.postedAt)) return null;
      final t = r.eventTime;
      return t == null ? d : DateTime(d!.year, d.month, d.day, t.$1, t.$2);
    }

    final eventAt = stamp(r.eventDate);
    final dueAt = stamp(r.dueDate);
    final endAt = NoticeReminders.acceptableDate(r.endDate, postedAt: notice.postedAt) ? r.endDate : null;
    final anyDate = eventAt != null || dueAt != null;
    // A date the validator threw out takes the confidence down with it.
    final confidence = ((r.eventDate != null || r.dueDate != null) && !anyDate)
        ? r.confidence.clamp(0, 0.5).toDouble()
        : r.confidence;
    return NoticeExtraction(
      kind: r.kind,
      title: r.title.trim().isEmpty ? (old?.title ?? notice.displayTitle) : r.title.trim(),
      subject: r.subject == null ? old?.subject : SubjectMatcher.match(r.subject!, _subjectsFor(notice.childId)),
      eventAt: eventAt,
      endAt: endAt,
      allDay: r.eventTime == null,
      dueAt: dueAt,
      confidence: confidence,
      source: 'gemini',
      matchedPhrases: [if (r.reasoning.isNotEmpty) r.reasoning],
    );
  }

  // ── actions ──

  /// The parent's confirm (§E). The extraction handed in is the truth from
  /// here on; reminders are (re)armed from it.
  Future<void> confirmNotice(
    String id, {
    NoticeExtraction? extraction,
    String? childId,
    List<DateTime>? reminderTimes,
  }) async {
    final uid = _auth.uid;
    final notice = noticeById(id);
    if (uid == null || notice == null) return;
    final e = extraction ?? notice.extraction;
    if (e == null) return;
    final now = _now();
    await _noticeScheduler.cancelNoticeReminders(notice.reminderIds);
    var updated = notice.copyWith(
      extraction: e,
      childId: childId ?? notice.childId,
      status: NoticeStatus.confirmed,
      reminderIds: const [],
      clearAutoArmedAt: true,
    );
    final times = reminderTimes ?? NoticeReminders.timesFor(e, now: now, offsets: noticeOffsets);
    final ids = await _noticeScheduler.scheduleNoticeReminders(updated, times);
    updated = updated.copyWith(reminderIds: ids);
    await _noticeRepo.save(uid: uid, notice: updated);
    if (childId != null) unawaited(rememberNoticeChild(notice.packageName, childId));
    unawaited(Telemetry.noticeConfirmed(e.kind.wire, e.source));
    notifyListeners();
  }

  /// Saves an edit without confirming — kind, date, subject or child.
  Future<void> updateNotice(String id, {NoticeExtraction? extraction, String? childId}) async {
    final uid = _auth.uid;
    final notice = noticeById(id);
    if (uid == null || notice == null) return;
    await _noticeRepo.save(
      uid: uid,
      notice: notice.copyWith(extraction: extraction, childId: childId),
    );
  }

  Future<void> ignoreNotice(String id) async {
    final uid = _auth.uid;
    final notice = noticeById(id);
    if (uid == null || notice == null) return;
    await _noticeScheduler.cancelNoticeReminders(notice.reminderIds);
    await _noticeRepo.save(
      uid: uid,
      notice: notice.copyWith(
        status: NoticeStatus.ignored,
        reminderIds: const [],
        clearAutoArmedAt: true,
      ),
    );
    unawaited(Telemetry.noticeIgnored(notice.kind.wire));
  }

  /// An ignored notice back to needs-review — the "Undo" on a swipe.
  Future<void> restoreNotice(String id) async {
    final uid = _auth.uid;
    final notice = noticeById(id);
    if (uid == null || notice == null) return;
    await _noticeRepo.save(
      uid: uid,
      notice: notice.copyWith(status: NoticeStatus.needsReview),
    );
  }

  /// Undo for an auto-armed notice (§D): back to the inbox, alarms off.
  Future<void> undoNoticeAutoArm(String id) async {
    final uid = _auth.uid;
    final notice = noticeById(id);
    if (uid == null || notice == null) return;
    await _noticeScheduler.cancelNoticeReminders(notice.reminderIds);
    await _noticeRepo.save(
      uid: uid,
      notice: notice.copyWith(
        status: NoticeStatus.needsReview,
        reminderIds: const [],
        clearAutoArmedAt: true,
      ),
    );
  }

  Future<void> deleteNotice(String id) async {
    final uid = _auth.uid;
    final notice = noticeById(id);
    if (uid == null || notice == null) return;
    await _noticeScheduler.cancelNoticeReminders(notice.reminderIds);
    await _noticeRepo.softDelete(uid: uid, noticeId: id);
  }

  /// Settings → Delete all captured notices. Really deletes — this is other
  /// people's text — and clears every alarm armed from it.
  Future<void> deleteAllNotices() async {
    final uid = _auth.uid;
    if (uid == null) return;
    for (final n in _notices) {
      await _noticeScheduler.cancelNoticeReminders(n.reminderIds);
    }
    await _noticeRepo.deleteAll(uid);
    _notices = const [];
    notifyListeners();
  }

  /// Retention (§B): once per session after sign-in, drop notices older
  /// than the retention window.
  Future<void> purgeOldNotices({bool force = false}) async {
    final uid = _auth.uid;
    if (uid == null || !noticeCaptureEnabled) return;
    if (_noticesPurged && !force) return;
    _noticesPurged = true;
    try {
      await _noticeRepo.purgeOlderThan(
        uid: uid,
        before: _now().subtract(Duration(days: noticeRetentionDays)),
      );
    } catch (error, stack) {
      unawaited(Telemetry.recordError(error, stack, context: 'noticePurge'));
    }
  }

  /// Convert to record (§D). An assignment becomes a worksheet with the due
  /// date filled and the notice text as notes, saved straight away. An exam
  /// needs its timetable image, so the caller gets a *draft* to open in the
  /// Add Exam form and links it with [linkNoticeToRecord] afterwards.
  DiaryRecord draftRecordFor(CapturedNotice notice) {
    final e = notice.extraction;
    final subject = e?.subject ?? suggestedSubject;
    final title = notice.displayTitle;
    final notes = 'From ${notice.appLabel}:\n${notice.body.trim()}';
    final date = DateTime(notice.postedAt.year, notice.postedAt.month, notice.postedAt.day);
    if (e?.kind == NoticeKind.exam) {
      final examDate = e?.date ?? date;
      return DiaryRecord(
        id: '',
        type: RecordType.exam,
        subject: subject.isEmpty ? 'General' : subject,
        title: title,
        examType: title,
        date: DateTime(examDate.year, examDate.month, examDate.day),
        notes: notes,
        origin: RecordOrigin.notification,
      );
    }
    return DiaryRecord(
      id: '',
      type: RecordType.worksheet,
      subject: subject.isEmpty ? 'General' : subject,
      title: title,
      date: date,
      dueDate: e?.date == null ? null : DateTime(e!.date!.year, e.date!.month, e.date!.day),
      notes: notes,
      origin: RecordOrigin.notification,
    );
  }

  /// One tap for an assignment notice: saves the worksheet and links it.
  Future<DiaryRecord> convertNoticeToWorksheet(String id) async {
    final notice = noticeById(id);
    if (notice == null) throw AppFailure.cancelled;
    final draft = draftRecordFor(notice);
    final record = await saveRecord(
      draft.copyWith(
        type: RecordType.worksheet,
        // A due date before the notice date fails validation; a notice
        // about last week's homework is still worth filing.
        dueDate: draft.dueDate != null && draft.dueDate!.isBefore(draft.date) ? null : draft.dueDate,
      ),
    );
    await linkNoticeToRecord(id, record, cancelReminders: true);
    return record;
  }

  Future<void> linkNoticeToRecord(
    String id,
    DiaryRecord record, {
    bool cancelReminders = false,
  }) async {
    final uid = _auth.uid;
    final notice = noticeById(id);
    if (uid == null || notice == null) return;
    if (cancelReminders) {
      // The worksheet carries its own due-date reminder; two alarms on the
      // same morning would be a nag.
      await _noticeScheduler.cancelNoticeReminders(notice.reminderIds);
    }
    await _noticeRepo.save(
      uid: uid,
      notice: notice.copyWith(
        status: NoticeStatus.converted,
        linkedRecordId: record.id,
        reminderIds: cancelReminders ? const [] : notice.reminderIds,
        clearAutoArmedAt: true,
      ),
    );
    unawaited(Telemetry.noticeConverted(record.type.wire));
  }

  // ── Weak-subject analytics ───────────────────────────────────────────────

  /// Every year's results, fetched once per child when the parent asks for
  /// the all-years view. Null until then.
  List<ExamResult>? _allYearResults;
  bool _loadingAllYears = false;
  bool get isLoadingAllYearResults => _loadingAllYears;

  bool _insightsAllYears = false;

  /// Whether the Performance tab reads across every year or just the active
  /// one. Default: the active year — the question a parent usually asks.
  bool get insightsAllYears => _insightsAllYears;

  Future<void> setInsightsAllYears(bool value) async {
    if (_insightsAllYears == value) return;
    _insightsAllYears = value;
    notifyListeners();
    if (value && _allYearResults == null) await _loadAllYearResults();
  }

  Future<void> _loadAllYearResults() async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null || _loadingAllYears) return;
    _loadingAllYears = true;
    notifyListeners();
    try {
      _allYearResults = await _resultRepo.allYears(
        uid: uid,
        childId: childId,
      );
    } catch (error, stack) {
      _lastError = AppFailure.from(error);
      unawaited(Telemetry.recordError(error, stack, context: 'allYearResults'));
    } finally {
      _loadingAllYears = false;
      notifyListeners();
    }
  }

  /// The result set the insights are computed over.
  List<ExamResult> get insightResults =>
      _insightsAllYears ? (_allYearResults ?? _results) : _results;

  // Memo key: list *identities*, not contents. The streams hand over a fresh
  // list on every change, so identity is a cheap, exact "did anything move".
  List<ExamResult>? _memoResults;
  List<DiaryRecord>? _memoRecords;
  List<Subject>? _memoSubjects;
  String? _memoChildName;
  List<SubjectInsight> _memoInsights = const [];

  /// One insight per subject (§E). Read from `build()` on the home and
  /// performance screens, so it is memoised against the inputs and only
  /// recomputed when a result, record or subject list actually changes.
  List<SubjectInsight> get subjectInsights {
    final inputs = insightResults;
    final childName = activeChild.name;
    if (identical(inputs, _memoResults) &&
        identical(_records, _memoRecords) &&
        identical(_subjects, _memoSubjects) &&
        childName == _memoChildName) {
      return _memoInsights;
    }
    _memoResults = inputs;
    _memoRecords = _records;
    _memoSubjects = _subjects;
    _memoChildName = childName;
    _memoInsights = computeSubjectInsights(
      // A scanned card the parent has not confirmed is shown, dotted, but
      // never counted: a wrong mark is worse than no mark.
      results: inputs.where((r) => !r.needsReview).toList(),
      records: _records,
      subjects: subjectNames,
      childName: childName.isEmpty || childName == '—' ? 'your child' : childName,
    );
    return _memoInsights;
  }

  /// Weak-band subjects, worst first.
  List<SubjectInsight> get weakSubjects => weakSubjectsFrom(subjectInsights);

  SubjectInsight? insightFor(String subject) =>
      subjectInsights.where((i) => i.subject == subject).firstOrNull;

  /// Re-runs any stranded uploads — what "Retry" and the More screen's sync row
  /// call.
  Future<void> retrySync() async {
    final uid = _auth.uid;
    final childId = _childId;
    if (uid == null || childId == null) return;
    await uploads.resume(uid: uid, childId: childId);
  }

  // ── Timeline / list filters ──────────────────────────────────────────────
  TimelineFilter _filter = const TimelineFilter();
  TimelineFilter get filter => _filter;
  void setFilter(TimelineFilter value) {
    _filter = value;
    notifyListeners();
  }

  void clearFilter() => setFilter(const TimelineFilter());

  String _worksheetStatusFilter = 'All';
  String get worksheetStatusFilter => _worksheetStatusFilter;
  void setWorksheetStatusFilter(String value) {
    _worksheetStatusFilter = value;
    notifyListeners();
  }

  String _listSubject = 'All';
  String get listSubject => _listSubject;
  void setListSubject(String value) {
    _listSubject = value;
    notifyListeners();
  }

  // ── Connectivity banner ──────────────────────────────────────────────────

  /// Set only by the design-states gallery, which previews the offline banner
  /// on a device that is actually online. Null means "use the real network".
  bool? _offlineOverride;

  bool get isOffline => _offlineOverride ?? _connectivity.offline.value;

  bool _bannerDismissed = false;

  /// The timeline's banner. Dismissing hides it for this stretch of being
  /// offline; it returns if the connection drops again, because by then the
  /// parent has new work that is not syncing.
  bool get showOfflineBanner => isOffline && !_bannerDismissed;

  void dismissOfflineBanner() {
    if (_bannerDismissed) return;
    _bannerDismissed = true;
    notifyListeners();
  }

  /// True while attachment bytes are still in flight (§25).
  bool get isSyncing => uploads.status == QueueStatus.uploading;
  bool get hasFailedUploads => uploads.status == QueueStatus.failed;

  String get syncLabel {
    if (isOffline) return 'Offline';
    return switch (uploads.status) {
      QueueStatus.uploading => 'Syncing',
      QueueStatus.waiting => 'Waiting for internet',
      QueueStatus.failed => 'Sync failed',
      QueueStatus.idle => 'Synced',
    };
  }

  void toggleOffline() {
    _offlineOverride = !isOffline;
    notifyListeners();
  }

  void setOffline(bool value) {
    if (isOffline == value) return;
    _offlineOverride = value;
    notifyListeners();
  }

  void _onConnectivityChanged() {
    // A real network change wins over a preview override.
    _offlineOverride = null;
    _bannerDismissed = false;
    notifyListeners();
  }

  /// Groups records by subject in the configured subject order, dropping empty
  /// groups — the `groupBy` helper from the prototype.
  ///
  /// Memoised on `(source, subjects, listSubject, unit)`. [source] is
  /// compared element-wise by identity rather than by list identity, because
  /// the worksheets list hands in a freshly filtered copy on every build.
  List<SubjectGroup> groupBySubject(List<DiaryRecord> source, String unit) {
    final cached = _memo.groups(source, _subjects, _listSubject, unit);
    if (cached != null) return cached;
    final groups = _groupBySubject(source, unit);
    _memo.rememberGroups(source, _subjects, _listSubject, unit, groups);
    return groups;
  }

  List<SubjectGroup> _groupBySubject(List<DiaryRecord> source, String unit) {
    final names = _listSubject == 'All' ? subjectNames : <String>[_listSubject];
    final groups = <SubjectGroup>[];
    for (final name in names) {
      final items = source.where((r) => r.subject == name).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (items.isEmpty) continue;
      groups.add(
        SubjectGroup(
          subject: subjectByName(name),
          items: items,
          count: '${items.length} $unit${items.length == 1 ? '' : 's'}',
        ),
      );
    }
    return groups;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cancelDataSubscriptions();
    aiKeys.removeListener(notifyListeners);
    if (_noticeCaptureOverride == null) noticeCapture.dispose();
    _connectivity.offline.removeListener(_onConnectivityChanged);
    uploads.removeListener(notifyListeners);
    uploads.dispose();
    unawaited(_connectivity.dispose());
    super.dispose();
  }
}

/// Per-[AppState] cache for the derived record lists. Each entry remembers
/// the source list it was computed from and is recomputed only when that
/// identity changes; there is no TTL because the inputs are immutable lists
/// that are replaced, never mutated.
class _RecordsMemo {
  List<DiaryRecord>? _worksheetsSource;
  List<DiaryRecord> _worksheets = const [];
  List<DiaryRecord>? _classworkSource;
  List<DiaryRecord> _classwork = const [];
  List<DiaryRecord>? _byDateSource;
  List<DiaryRecord> _byDate = const [];

  List<DiaryRecord>? _groupSource;
  List<Subject>? _groupSubjects;
  String? _groupListSubject;
  String? _groupUnit;
  List<SubjectGroup> _groups = const [];

  List<DiaryRecord> worksheets(
    List<DiaryRecord> source,
    List<DiaryRecord> Function() compute,
  ) {
    if (!identical(source, _worksheetsSource)) {
      _worksheetsSource = source;
      _worksheets = List.unmodifiable(compute());
    }
    return _worksheets;
  }

  List<DiaryRecord> classwork(
    List<DiaryRecord> source,
    List<DiaryRecord> Function() compute,
  ) {
    if (!identical(source, _classworkSource)) {
      _classworkSource = source;
      _classwork = List.unmodifiable(compute());
    }
    return _classwork;
  }

  List<DiaryRecord> byDateDesc(
    List<DiaryRecord> source,
    List<DiaryRecord> Function() compute,
  ) {
    if (!identical(source, _byDateSource)) {
      _byDateSource = source;
      _byDate = List.unmodifiable(compute());
    }
    return _byDate;
  }

  List<SubjectGroup>? groups(
    List<DiaryRecord> source,
    List<Subject> subjects,
    String listSubject,
    String unit,
  ) {
    if (!identical(subjects, _groupSubjects) ||
        listSubject != _groupListSubject ||
        unit != _groupUnit ||
        !_sameElements(source, _groupSource)) {
      return null;
    }
    return _groups;
  }

  void rememberGroups(
    List<DiaryRecord> source,
    List<Subject> subjects,
    String listSubject,
    String unit,
    List<SubjectGroup> groups,
  ) {
    _groupSource = source;
    _groupSubjects = subjects;
    _groupListSubject = listSubject;
    _groupUnit = unit;
    _groups = groups;
  }

  static bool _sameElements(List<DiaryRecord> a, List<DiaryRecord>? b) {
    if (b == null || a.length != b.length) return false;
    if (identical(a, b)) return true;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

class SubjectGroup {
  const SubjectGroup({
    required this.subject,
    required this.items,
    required this.count,
  });

  final Subject subject;
  final List<DiaryRecord> items;
  final String count;
}

/// Makes [AppState] available to the widget tree and rebuilds dependents when
/// it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }

  /// Reads the state without subscribing — for callbacks that only mutate.
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }
}
