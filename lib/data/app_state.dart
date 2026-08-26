import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/errors/app_failure.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/image_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/prefs_service.dart';
import '../core/services/telemetry_service.dart';
import '../core/theme/subject_hue.dart';
import 'models.dart';
import 'repositories/attachment_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/child_repository.dart';
import 'repositories/record_repository.dart';
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
    AttachmentRepository? attachments,
    ConnectivityService? connectivity,
  }) : _auth = auth ?? AuthRepository(),
       _childRepo = children,
       _subjectRepo = subjects,
       _yearRepo = years,
       _recordRepo = records,
       _attachmentRepo = attachments ?? AttachmentRepository(),
       _connectivity = connectivity ?? ConnectivityService() {
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
  final AttachmentRepository _attachmentRepo;
  final ConnectivityService _connectivity;

  late final UploadQueue uploads;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<Child>>? _childrenSub;
  StreamSubscription<List<AcademicYear>>? _yearsSub;
  StreamSubscription<List<Subject>>? _subjectsSub;
  StreamSubscription<List<DiaryRecord>>? _recordsSub;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Wires connectivity and the auth listener. Called once from `main`, after
  /// `Firebase.initializeApp`.
  Future<void> bootstrap() async {
    await _connectivity.start();
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
    _years = const [];
    _childId = null;
    _loadingRecords = false;

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
    notifyListeners();
  }

  void _onChildren(List<Child> value) {
    _children = value;

    if (value.isEmpty) {
      _childId = null;
      _status = AuthStatus.needsChild;
      _subjects = const [];
      _records = const [];
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
      _resubscribeRecords();
    }
    notifyListeners();
  }

  void _onStreamError(Object error, StackTrace stack) {
    _loadingRecords = false;
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

    _resubscribeRecords();
    unawaited(uploads.resume(uid: uid, childId: childId));
  }

  void _resubscribeRecords() {
    final uid = _auth.uid;
    final childId = _childId;
    final year = _activeYear;
    _recordsSub?.cancel();
    // Same for records: switching child or year must not leave the old list on
    // screen while the new query runs.
    _records = const [];
    if (uid == null || childId == null || year == null) {
      _loadingRecords = false;
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
  }

  void _cancelDataSubscriptions() {
    _childrenSub?.cancel();
    _yearsSub?.cancel();
    _subjectsSub?.cancel();
    _recordsSub?.cancel();
    _childrenSub = null;
    _yearsSub = null;
    _subjectsSub = null;
    _recordsSub = null;
  }

  bool _loadingRecords = false;
  bool get isLoadingRecords => _loadingRecords;

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
    _resubscribeRecords();
    notifyListeners();
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
      _resubscribeRecords();
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

  List<DiaryRecord> get worksheets =>
      _records.where((r) => r.type == RecordType.worksheet).toList();

  List<DiaryRecord> get classwork =>
      _records.where((r) => r.type == RecordType.classwork).toList();

  /// Newest first — the order the timeline and "Recent activity" use.
  List<DiaryRecord> get recordsByDateDesc =>
      _records.toList()..sort((a, b) => b.date.compareTo(a.date));

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
  List<SubjectGroup> groupBySubject(List<DiaryRecord> source, String unit) {
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
    _connectivity.offline.removeListener(_onConnectivityChanged);
    uploads.removeListener(notifyListeners);
    uploads.dispose();
    unawaited(_connectivity.dispose());
    super.dispose();
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
