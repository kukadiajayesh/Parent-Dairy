import '../core/config/grade_scale.dart';
import '../core/theme/subject_hue.dart';

enum RecordType {
  worksheet('worksheet'),
  classwork('classwork'),
  exam('exam');

  const RecordType(this.wire);

  /// Stable value written to Firestore. Never derive this from [name] — the
  /// enum could be reordered or renamed and old documents would stop parsing.
  final String wire;

  static RecordType fromWire(String? value) => switch (value) {
    'classwork' => RecordType.classwork,
    'exam' => RecordType.exam,
    _ => RecordType.worksheet,
  };
}

/// Chapter chip options offered when tagging a worksheet/classwork/shared
/// record. Bounded to 1–10 — the single source of truth for every chapter
/// picker in the app.
const List<String> kChapterOptions = [
  'Chapter 1',
  'Chapter 2',
  'Chapter 3',
  'Chapter 4',
  'Chapter 5',
  'Chapter 6',
  'Chapter 7',
  'Chapter 8',
  'Chapter 9',
  'Chapter 10',
];

/// How a record came to exist. Persisted so the timeline can badge
/// AI-generated material and so an old document (no field) still reads as
/// manual.
enum RecordOrigin {
  manual('manual'),
  share('share'),
  ai('ai'),
  notification('notification');

  const RecordOrigin(this.wire);
  final String wire;

  static RecordOrigin fromWire(String? value) => switch (value) {
    'share' => RecordOrigin.share,
    'ai' => RecordOrigin.ai,
    'notification' => RecordOrigin.notification,
    _ => RecordOrigin.manual,
  };
}

enum WorksheetStatus {
  pending('Pending', 'pending'),
  completed('Completed', 'completed');

  const WorksheetStatus(this.label, this.wire);
  final String label;
  final String wire;

  static WorksheetStatus fromWire(String? value) => switch (value) {
    'completed' => WorksheetStatus.completed,
    _ => WorksheetStatus.pending,
  };
}

/// Where a record or attachment stands relative to the server.
///
/// Firestore's own cache makes document writes optimistic for free, so this
/// tracks the part it cannot: whether the *file bytes* behind an attachment
/// have reached Storage yet.
enum SyncState {
  synced('synced'),
  pending('pending'),
  uploading('uploading'),
  failed('failed');

  const SyncState(this.wire);
  final String wire;

  bool get isSettled => this == SyncState.synced;

  static SyncState fromWire(String? value) => switch (value) {
    'pending' => SyncState.pending,
    'uploading' => SyncState.uploading,
    'failed' => SyncState.failed,
    _ => SyncState.synced,
  };
}

class Subject {
  const Subject({
    required this.name,
    required this.abbr,
    required this.hue,
    required this.order,
    this.id = '',
    this.active = true,
  });

  final String id;
  final String name;
  final String abbr;
  final SubjectHue hue;
  final int order;
  final bool active;

  Subject copyWith({
    String? id,
    String? name,
    String? abbr,
    SubjectHue? hue,
    int? order,
    bool? active,
  }) => Subject(
    id: id ?? this.id,
    name: name ?? this.name,
    abbr: abbr ?? this.abbr,
    hue: hue ?? this.hue,
    order: order ?? this.order,
    active: active ?? this.active,
  );
}

class Child {
  const Child({
    required this.name,
    required this.initials,
    required this.school,
    required this.grade,
    required this.section,
    required this.year,
    this.id = '',
    this.photoUrl,
    this.grNumber,
    this.rollNumber,
    this.dateOfBirth,
    this.notes = '',
    this.gradeScaleId = GradeScale.defaultId,
  });

  final String id;
  final String name;
  final String initials;
  final String school;
  final String grade;
  final String section;

  /// The child's *current* academic year label. Records carry their own year,
  /// so changing this does not move history.
  final String year;

  final String? photoUrl;

  /// School-assigned General Register number, distinct from the class roll
  /// number.
  final String? grNumber;
  final String? rollNumber;
  final DateTime? dateOfBirth;
  final String notes;

  /// Which [GradeScale] turns this child's report-card grades into percents.
  /// Per child, because siblings can attend schools on different boards.
  final String gradeScaleId;

  String get meta => '$grade $section · $school';
  String get shortMeta => '$grade · $year';

  GradeScale get gradeScale => GradeScale.byId(gradeScaleId);

  Child copyWith({
    String? id,
    String? name,
    String? initials,
    String? school,
    String? grade,
    String? section,
    String? year,
    String? photoUrl,
    String? grNumber,
    String? rollNumber,
    DateTime? dateOfBirth,
    String? notes,
    String? gradeScaleId,
  }) => Child(
    id: id ?? this.id,
    name: name ?? this.name,
    initials: initials ?? this.initials,
    school: school ?? this.school,
    grade: grade ?? this.grade,
    section: section ?? this.section,
    year: year ?? this.year,
    photoUrl: photoUrl ?? this.photoUrl,
    grNumber: grNumber ?? this.grNumber,
    rollNumber: rollNumber ?? this.rollNumber,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    notes: notes ?? this.notes,
    gradeScaleId: gradeScaleId ?? this.gradeScaleId,
  );

  /// "Aarav Patel" -> "AP", "Diya" -> "DI".
  static String initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final single = parts.first;
      return (single.length >= 2 ? single.substring(0, 2) : single)
          .toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class AcademicYear {
  const AcademicYear({
    required this.label,
    required this.span,
    required this.records,
    this.id = '',
    this.active = false,
  });

  final String id;
  final String label;
  final String span;

  /// Record count for the year. Maintained by the repository rather than
  /// counted client-side, so old years stay cheap to display.
  final int records;
  final bool active;

  String get meta => '$span · $records records';

  /// The year's span, derived from the label rather than the display string:
  /// `2026–27` runs 1 Apr 2026 – 31 Mar 2027, the Indian school calendar.
  /// Null when the label carries no four-digit year.
  ({DateTime start, DateTime end})? get dateSpan => spanForLabel(label);

  /// True when [date] falls inside this year's April–March span.
  bool contains(DateTime date) {
    final span = dateSpan;
    if (span == null) return false;
    return !date.isBefore(span.start) && date.isBefore(span.end);
  }

  static ({DateTime start, DateTime end})? spanForLabel(String label) {
    final start = int.tryParse(
      RegExp(r'\d{4}').firstMatch(label)?.group(0) ?? '',
    );
    if (start == null) return null;
    return (start: DateTime(start, 4, 1), end: DateTime(start + 1, 4, 1));
  }

  AcademicYear copyWith({
    String? id,
    String? label,
    String? span,
    int? records,
    bool? active,
  }) => AcademicYear(
    id: id ?? this.id,
    label: label ?? this.label,
    span: span ?? this.span,
    records: records ?? this.records,
    active: active ?? this.active,
  );
}

class Attachment {
  const Attachment({
    required this.name,
    required this.meta,
    this.id = '',
    bool isPdf = false,
    this.storagePath,
    this.downloadUrl,
    this.localPath,
    this.fileSize = 0,
    this.mimeType,
    this.sync = SyncState.synced,
  }) : _isPdf = isPdf;

  final String id;

  /// File name as shown to the parent, e.g. `fractions-page-1.jpg`.
  final String name;

  /// Caption under the thumbnail, e.g. `Page 1` or `1 page · 240 KB`.
  final String meta;

  final bool _isPdf;
  bool get isPdf =>
      _isPdf ||
      name.toLowerCase().endsWith('.pdf') ||
      (mimeType ?? '').toLowerCase().contains('pdf');

  /// Location in Firebase Storage. Null until the upload completes.
  final String? storagePath;
  final String? downloadUrl;

  /// On-device copy. Kept after upload so the viewer can render instantly and
  /// so a failed upload can be retried without asking for the file again.
  final String? localPath;

  final int fileSize;
  final String? mimeType;
  final SyncState sync;

  bool get isUploaded => downloadUrl != null && downloadUrl!.isNotEmpty;
  bool get isImage => !isPdf;

  Attachment copyWith({
    String? id,
    String? name,
    String? meta,
    bool? isPdf,
    String? storagePath,
    String? downloadUrl,
    String? localPath,
    int? fileSize,
    String? mimeType,
    SyncState? sync,
  }) => Attachment(
    id: id ?? this.id,
    name: name ?? this.name,
    meta: meta ?? this.meta,
    isPdf: isPdf ?? this.isPdf,
    storagePath: storagePath ?? this.storagePath,
    downloadUrl: downloadUrl ?? this.downloadUrl,
    localPath: localPath ?? this.localPath,
    fileSize: fileSize ?? this.fileSize,
    mimeType: mimeType ?? this.mimeType,
    sync: sync ?? this.sync,
  );
}

/// A single entry on the academic timeline. Worksheets carry a due date, an
/// answer key and a status; classwork carries photos only.
class DiaryRecord {
  const DiaryRecord({
    required this.id,
    required this.type,
    required this.subject,
    required this.title,
    required this.date,
    this.childId = '',
    this.academicYearId = '',
    this.dueDate,
    this.completedDate,
    this.chapters = const [],
    this.notes = '',
    this.status = WorksheetStatus.pending,
    this.attachments = const [],
    this.answerKey,
    this.hardWords,
    this.examType = '',
    this.examTimetable,
    this.origin = RecordOrigin.manual,
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  final String id;

  /// Owning child. Every query is scoped by it, so switching child never
  /// leaks another child's history.
  final String childId;

  /// The year *label*, e.g. `2026–27` — not the year document's id.
  ///
  /// The label is the stable natural key for an academic year and is what the
  /// switcher already holds, so scoping by it keeps the timeline a single
  /// query with no join.
  final String academicYearId;

  final RecordType type;

  /// Subject *name*. Denormalised on purpose: the timeline renders thousands of
  /// rows and must not join to the subject collection to draw each one.
  final String subject;

  final String title;
  final DateTime date;
  final DateTime? dueDate;
  final DateTime? completedDate;

  /// Chapters or units the record covers, e.g. `['Chapter 4']`. Bounded to
  /// [kChapterOptions] by the picker UI.
  final List<String> chapters;
  final String notes;
  final WorksheetStatus status;
  final List<Attachment> attachments;
  final Attachment? answerKey;

  /// Hard-words file for the record's (first) chapter. Chapter-scoped in
  /// practice — see [AppState.hardWordsForChapter], which offers the most
  /// recent one attached to any record sharing that chapter.
  final Attachment? hardWords;

  /// Free-text exam type, e.g. `Unit Test 1`, `Mid-term` — exam records only.
  final String examType;

  /// Exam timetable image — required for [RecordType.exam]. Previous exam
  /// papers reuse the generic [attachments] list (image-only, enforced by
  /// the add-exam UI).
  final Attachment? examTimetable;

  /// Where the record came from. `ai` records carry an "AI" badge wherever
  /// they are listed, and their attachments are model output the parent has
  /// been told to check.
  final RecordOrigin origin;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Soft delete. Deleted records stay in Firestore and drop out of every UI
  /// query, so a mis-tap never destroys a year of history.
  final bool isDeleted;
  final DateTime? deletedAt;

  bool get isWorksheet => type == RecordType.worksheet;
  bool get isExam => type == RecordType.exam;
  bool get isAiGenerated => origin == RecordOrigin.ai;

  bool get hasAnswerKey => answerKey != null;
  bool get hasHardWords => hardWords != null;
  bool get hasExamTimetable => examTimetable != null;

  /// First chapter plus a "+N more" suffix when more than one is tagged, e.g.
  /// `Chapter 2 +1`. Empty string when no chapter is tagged.
  String get chapterLabel {
    if (chapters.isEmpty) return '';
    if (chapters.length == 1) return chapters.first;
    return '${chapters.first} +${chapters.length - 1}';
  }

  /// Pages/photos attached to the record. The answer key is counted separately
  /// — the design lists "2 files" for a worksheet that also carries a key.
  int get fileCount => attachments.length;

  /// Every file on the record, answer key/hard words/exam timetable included
  /// — what the uploader and the delete path both need to walk.
  List<Attachment> get allFiles => [
    ...attachments,
    ?answerKey,
    ?hardWords,
    ?examTimetable,
  ];

  /// Worst state across the record's files: one failed upload makes the whole
  /// record show as failed.
  SyncState get sync {
    final files = allFiles;
    if (files.isEmpty) return SyncState.synced;
    if (files.any((f) => f.sync == SyncState.failed)) return SyncState.failed;
    if (files.any((f) => f.sync == SyncState.uploading)) {
      return SyncState.uploading;
    }
    if (files.any((f) => f.sync == SyncState.pending)) return SyncState.pending;
    return SyncState.synced;
  }

  bool get isOverdue =>
      isWorksheet &&
      status == WorksheetStatus.pending &&
      dueDate != null &&
      dueDate!.isBefore(DateTime.now());

  DiaryRecord copyWith({
    String? id,
    String? childId,
    String? academicYearId,
    RecordType? type,
    String? subject,
    String? title,
    DateTime? date,
    DateTime? dueDate,
    DateTime? completedDate,
    List<String>? chapters,
    String? notes,
    WorksheetStatus? status,
    List<Attachment>? attachments,
    Attachment? answerKey,
    Attachment? hardWords,
    String? examType,
    Attachment? examTimetable,
    RecordOrigin? origin,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDueDate = false,
    bool clearCompletedDate = false,
    bool clearAnswerKey = false,
    bool clearHardWords = false,
    bool clearExamTimetable = false,
  }) => DiaryRecord(
    id: id ?? this.id,
    childId: childId ?? this.childId,
    academicYearId: academicYearId ?? this.academicYearId,
    type: type ?? this.type,
    subject: subject ?? this.subject,
    title: title ?? this.title,
    date: date ?? this.date,
    dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    completedDate: clearCompletedDate
        ? null
        : (completedDate ?? this.completedDate),
    chapters: chapters ?? this.chapters,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    attachments: attachments ?? this.attachments,
    answerKey: clearAnswerKey ? null : (answerKey ?? this.answerKey),
    hardWords: clearHardWords ? null : (hardWords ?? this.hardWords),
    examType: examType ?? this.examType,
    examTimetable: clearExamTimetable
        ? null
        : (examTimetable ?? this.examTimetable),
    origin: origin ?? this.origin,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

// ── Exam results ──────────────────────────────────────────────────────────

/// How a result reached the diary. Manual entry is the only source this
/// build writes; `scanned` and `imported` are reserved for the report-card
/// OCR prompt so those documents already parse when it lands.
enum ResultSource {
  manual('manual'),
  scanned('scanned'),
  imported('imported');

  const ResultSource(this.wire);
  final String wire;

  static ResultSource fromWire(String? value) => switch (value) {
    'scanned' => ResultSource.scanned,
    'imported' => ResultSource.imported,
    _ => ResultSource.manual,
  };

  String get label => switch (this) {
    ResultSource.manual => 'Entered by you',
    ResultSource.scanned => 'Scanned',
    ResultSource.imported => 'Imported',
  };
}

/// One subject row on one report card.
class SubjectScore {
  const SubjectScore({
    required this.subject,
    this.marks,
    this.maxMarks,
    this.grade,
    this.classRank,
    this.remarks = '',
    this.absent = false,
    this.gradeScaleId = GradeScale.defaultId,
  });

  /// Subject *name* — normally one of the child's subjects, but free text is
  /// allowed so a report card can be copied faithfully even when the school
  /// lists a subject the diary does not know yet.
  final String subject;

  /// Null when the school reports grades only.
  final double? marks;
  final double? maxMarks;

  /// 'A1', 'B+', 'Distinction', … — kept verbatim.
  final String? grade;
  final int? classRank;
  final String remarks;

  /// An absent row is excluded from every average, never scored as zero.
  final bool absent;

  /// The scale that resolves [grade] when there are no marks. Carried on the
  /// row so [percent] can stay a plain getter; the mapper writes it once per
  /// result and stamps it back onto every row on read.
  final String gradeScaleId;

  bool get hasMarks => marks != null && maxMarks != null && maxMarks! > 0;
  bool get hasGrade => grade != null && grade!.trim().isNotEmpty;

  /// 0–100, or null when neither marks nor a mappable grade is present.
  /// Absent rows never have a percent.
  double? get percent {
    if (absent) return null;
    if (hasMarks) return (marks! / maxMarks!) * 100;
    return GradeScale.byId(gradeScaleId).percentFor(grade);
  }

  /// True when [percent] came from a grade band's midpoint rather than from
  /// marks — the UI says "approximate" instead of pretending an A1 is 95.5%.
  bool get isDerivedPercent => !absent && !hasMarks && percent != null;

  SubjectScore copyWith({
    String? subject,
    double? marks,
    double? maxMarks,
    String? grade,
    int? classRank,
    String? remarks,
    bool? absent,
    String? gradeScaleId,
    bool clearMarks = false,
    bool clearMaxMarks = false,
    bool clearGrade = false,
    bool clearClassRank = false,
  }) => SubjectScore(
    subject: subject ?? this.subject,
    marks: clearMarks ? null : (marks ?? this.marks),
    maxMarks: clearMaxMarks ? null : (maxMarks ?? this.maxMarks),
    grade: clearGrade ? null : (grade ?? this.grade),
    classRank: clearClassRank ? null : (classRank ?? this.classRank),
    remarks: remarks ?? this.remarks,
    absent: absent ?? this.absent,
    gradeScaleId: gradeScaleId ?? this.gradeScaleId,
  );
}

/// A whole exam result — one report card, one unit test, one term.
class ExamResult {
  const ExamResult({
    required this.id,
    required this.childId,
    required this.academicYearId,
    required this.examLabel,
    required this.date,
    this.examRecordId,
    this.scores = const [],
    this.attendancePercent,
    this.teacherRemarks = '',
    this.source = ResultSource.manual,
    this.extractionConfidence = 1,
    this.needsReview = false,
    this.gradeScaleId = GradeScale.defaultId,
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  final String id;
  final String childId;

  /// The year *label* (`2026–27`), the same convention as [DiaryRecord].
  final String academicYearId;

  /// 'Unit Test 1', 'Term 1', 'Half Yearly', …
  final String examLabel;
  final DateTime date;

  /// The [DiaryRecord] of type exam this result belongs to, if the parent
  /// linked one.
  final String? examRecordId;
  final List<SubjectScore> scores;
  final double? attendancePercent;
  final String teacherRemarks;
  final ResultSource source;

  /// 1.0 for manual entry; a scan reports what the model was sure of.
  final double extractionConfidence;

  /// True until a parent confirms a scanned card.
  final bool needsReview;

  /// The [GradeScale] in force when the result was saved. Snapshotted here
  /// rather than read live from the child, so changing the scale later does
  /// not silently rewrite last year's averages.
  final String gradeScaleId;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  /// Rows that actually carry a number — absent rows and blank rows excluded.
  Iterable<SubjectScore> get scoredRows =>
      scores.where((s) => !s.absent && s.percent != null);

  int get gradedSubjectCount => scoredRows.length;

  /// Marks-weighted overall percent, ignoring absent rows.
  ///
  /// Each row contributes `percent × weight`, where the weight is its own
  /// max marks (a 100-mark paper counts more than a 20-mark quiz) and a
  /// grade-only row counts as a 100-mark paper. Raw marks are never summed
  /// across different maxima, so 72/80 and 90/100 never become "162".
  double? get overallPercent {
    var weighted = 0.0;
    var weights = 0.0;
    for (final row in scoredRows) {
      final weight = row.hasMarks ? row.maxMarks! : 100.0;
      weighted += row.percent! * weight;
      weights += weight;
    }
    if (weights == 0) return null;
    return weighted / weights;
  }

  SubjectScore? scoreFor(String subject) =>
      scores.where((s) => s.subject == subject).firstOrNull;

  /// Re-stamps [gradeScaleId] onto every row as well, so a result and its
  /// scores never disagree about which scale resolves a grade.
  ExamResult copyWith({
    String? id,
    String? childId,
    String? academicYearId,
    String? examLabel,
    DateTime? date,
    String? examRecordId,
    List<SubjectScore>? scores,
    double? attendancePercent,
    String? teacherRemarks,
    ResultSource? source,
    double? extractionConfidence,
    bool? needsReview,
    String? gradeScaleId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearExamRecordId = false,
    bool clearAttendance = false,
  }) {
    final scale = gradeScaleId ?? this.gradeScaleId;
    final rows = scores ?? this.scores;
    return ExamResult(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      academicYearId: academicYearId ?? this.academicYearId,
      examLabel: examLabel ?? this.examLabel,
      date: date ?? this.date,
      examRecordId: clearExamRecordId
          ? null
          : (examRecordId ?? this.examRecordId),
      scores: [
        for (final row in rows)
          row.gradeScaleId == scale ? row : row.copyWith(gradeScaleId: scale),
      ],
      attendancePercent: clearAttendance
          ? null
          : (attendancePercent ?? this.attendancePercent),
      teacherRemarks: teacherRemarks ?? this.teacherRemarks,
      source: source ?? this.source,
      extractionConfidence: extractionConfidence ?? this.extractionConfidence,
      needsReview: needsReview ?? this.needsReview,
      gradeScaleId: scale,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

// ── Captured school notices (prompt 03) ───────────────────────────────────

/// What a school notification is about, as the extractor read it.
enum NoticeKind {
  exam('exam', 'Exam'),
  assignment('assignment', 'Assignment'),
  activity('activity', 'Activity'),
  holiday('holiday', 'Holiday'),
  fee('fee', 'Fee'),
  meeting('meeting', 'Meeting'),
  announcement('announcement', 'Announcement'),
  unknown('unknown', 'Unsorted');

  const NoticeKind(this.wire, this.label);
  final String wire;
  final String label;

  static NoticeKind fromWire(String? value) => switch (value) {
    'exam' => NoticeKind.exam,
    'assignment' => NoticeKind.assignment,
    'activity' => NoticeKind.activity,
    'holiday' => NoticeKind.holiday,
    'fee' => NoticeKind.fee,
    'meeting' => NoticeKind.meeting,
    'announcement' => NoticeKind.announcement,
    _ => NoticeKind.unknown,
  };

  /// Kinds that may arm a reminder without the parent's tap (§D). A fee
  /// or holiday reminder is armed only after a confirm.
  bool get autoArms =>
      this == NoticeKind.exam ||
      this == NoticeKind.assignment ||
      this == NoticeKind.activity ||
      this == NoticeKind.meeting;

  /// Assignments and fees are "due", everything else "happens".
  bool get isDue => this == NoticeKind.assignment || this == NoticeKind.fee;
}

/// Where a captured notice stands with the parent.
enum NoticeStatus {
  needsReview('needsReview', 'Needs review'),
  confirmed('confirmed', 'Confirmed'),
  ignored('ignored', 'Ignored'),
  converted('converted', 'Saved as record');

  const NoticeStatus(this.wire, this.label);
  final String wire;
  final String label;

  static NoticeStatus fromWire(String? value) => switch (value) {
    'confirmed' => NoticeStatus.confirmed,
    'ignored' => NoticeStatus.ignored,
    'converted' => NoticeStatus.converted,
    _ => NoticeStatus.needsReview,
  };
}

/// What the extractor pulled out of a notice's text — either the rules
/// (`source: 'rules'`) or the model (`source: 'gemini'`).
class NoticeExtraction {
  const NoticeExtraction({
    required this.kind,
    required this.title,
    this.subject,
    this.eventAt,
    this.endAt,
    this.allDay = true,
    this.dueAt,
    this.confidence = 0,
    this.source = 'rules',
    this.matchedPhrases = const [],
    this.alternateDates = const [],
  });

  final NoticeKind kind;

  /// Cleaned, e.g. `Science Unit Test 2`.
  final String title;

  /// One of the child's subject names, or null when nothing matched.
  final String? subject;

  /// When the event happens. For a range, [endAt] carries the last day.
  final DateTime? eventAt;
  final DateTime? endAt;
  final bool allDay;

  /// When something is due — assignments and fees.
  final DateTime? dueAt;

  /// 0–1. The auto-arm policy (§D) reads this, so it is never rounded up.
  final double confidence;

  /// `rules` | `gemini`.
  final String source;

  /// The words that drove the decision, for highlighting in the UI.
  final List<String> matchedPhrases;

  /// Other dates found in the same text. A notice with more than one
  /// candidate date always goes to the inbox rather than arming itself.
  final List<DateTime> alternateDates;

  /// The date reminders are anchored on: the due date for things that are
  /// due, the event date for things that happen.
  DateTime? get date => kind.isDue ? (dueAt ?? eventAt) : (eventAt ?? dueAt);

  bool get hasDate => date != null;
  bool get isAmbiguous => alternateDates.isNotEmpty;
  bool get fromModel => source == 'gemini';

  NoticeExtraction copyWith({
    NoticeKind? kind,
    String? title,
    String? subject,
    DateTime? eventAt,
    DateTime? endAt,
    bool? allDay,
    DateTime? dueAt,
    double? confidence,
    String? source,
    List<String>? matchedPhrases,
    List<DateTime>? alternateDates,
    bool clearSubject = false,
    bool clearDates = false,
  }) => NoticeExtraction(
    kind: kind ?? this.kind,
    title: title ?? this.title,
    subject: clearSubject ? null : (subject ?? this.subject),
    eventAt: clearDates ? null : (eventAt ?? this.eventAt),
    endAt: clearDates ? null : (endAt ?? this.endAt),
    allDay: allDay ?? this.allDay,
    dueAt: clearDates ? null : (dueAt ?? this.dueAt),
    confidence: confidence ?? this.confidence,
    source: source ?? this.source,
    matchedPhrases: matchedPhrases ?? this.matchedPhrases,
    alternateDates: clearDates ? const [] : (alternateDates ?? this.alternateDates),
  );

  /// Moves the anchor date to [value], keeping the time of day when the
  /// notice carried one — what the detail screen's date picker calls.
  NoticeExtraction withDate(DateTime value) {
    final current = date;
    final stamped = allDay || current == null
        ? DateTime(value.year, value.month, value.day)
        : DateTime(value.year, value.month, value.day, current.hour, current.minute);
    return kind.isDue
        ? copyWith(dueAt: stamped, eventAt: stamped, endAt: null, alternateDates: const [])
        : copyWith(eventAt: stamped, dueAt: stamped, endAt: null, alternateDates: const []);
  }

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'title': title,
    'subject': subject,
    'eventAt': eventAt?.toIso8601String(),
    'endAt': endAt?.toIso8601String(),
    'allDay': allDay,
    'dueAt': dueAt?.toIso8601String(),
    'confidence': confidence,
    'source': source,
    'matchedPhrases': matchedPhrases,
    'alternateDates': [for (final d in alternateDates) d.toIso8601String()],
  };
}

/// One notification captured from a school app.
///
/// Parent-level, not child-level: a notification arrives before anyone knows
/// which child it is about, and the parent assigns one on confirm.
class CapturedNotice {
  const CapturedNotice({
    required this.id,
    required this.packageName,
    required this.appLabel,
    required this.title,
    required this.body,
    required this.postedAt,
    required this.sourceHash,
    this.childId,
    this.status = NoticeStatus.needsReview,
    this.extraction,
    this.linkedRecordId,
    this.reminderIds = const [],
    this.truncated = false,
    this.autoArmedAt,
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  final String id;
  final String packageName;
  final String appLabel;
  final String title;

  /// First 4000 characters of the notification text; [truncated] says
  /// whether anything was cut.
  final String body;
  final DateTime postedAt;

  /// `sha1(packageName|title|body|yyyy-MM-dd)` — the document id is derived
  /// from it, so the same notice on two phones is one document.
  final String sourceHash;

  /// Assigned by the parent or inferred from the app → child mapping.
  final String? childId;
  final NoticeStatus status;
  final NoticeExtraction? extraction;

  /// The [DiaryRecord] this notice became, when converted.
  final String? linkedRecordId;

  /// Local notification ids scheduled from this notice — what cancel walks.
  final List<int> reminderIds;
  final bool truncated;

  /// Set when the auto-arm policy scheduled reminders without a tap. The
  /// detail screen offers Undo for 24 hours from this moment.
  final DateTime? autoArmedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  NoticeKind get kind => extraction?.kind ?? NoticeKind.unknown;
  double get confidence => extraction?.confidence ?? 0;
  DateTime? get date => extraction?.date;
  String get displayTitle {
    final t = extraction?.title.trim() ?? '';
    if (t.isNotEmpty) return t;
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body.trim().split('\n').first.trim();
    return firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine;
  }

  bool get needsReview => status == NoticeStatus.needsReview;
  bool get isConfirmed => status == NoticeStatus.confirmed;
  bool get isArmed => reminderIds.isNotEmpty;

  /// Inbox membership (§E): still needing review and worth a tap — kind or
  /// date known, confidence at least 0.5.
  bool get inInbox => needsReview && confidence >= 0.5;

  /// Confirmed with an event on or after [now]'s date.
  bool isUpcoming(DateTime now) {
    final d = date;
    if (!isConfirmed || d == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    return !d.isBefore(today);
  }

  bool canUndoAutoArm(DateTime now) {
    final at = autoArmedAt;
    return at != null &&
        status == NoticeStatus.confirmed &&
        now.difference(at) < const Duration(hours: 24);
  }

  CapturedNotice copyWith({
    String? id,
    String? packageName,
    String? appLabel,
    String? title,
    String? body,
    DateTime? postedAt,
    String? sourceHash,
    String? childId,
    NoticeStatus? status,
    NoticeExtraction? extraction,
    String? linkedRecordId,
    List<int>? reminderIds,
    bool? truncated,
    DateTime? autoArmedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearChildId = false,
    bool clearAutoArmedAt = false,
  }) => CapturedNotice(
    id: id ?? this.id,
    packageName: packageName ?? this.packageName,
    appLabel: appLabel ?? this.appLabel,
    title: title ?? this.title,
    body: body ?? this.body,
    postedAt: postedAt ?? this.postedAt,
    sourceHash: sourceHash ?? this.sourceHash,
    childId: clearChildId ? null : (childId ?? this.childId),
    status: status ?? this.status,
    extraction: extraction ?? this.extraction,
    linkedRecordId: linkedRecordId ?? this.linkedRecordId,
    reminderIds: reminderIds ?? this.reminderIds,
    truncated: truncated ?? this.truncated,
    autoArmedAt: clearAutoArmedAt ? null : (autoArmedAt ?? this.autoArmedAt),
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

/// Per-app capture rule (§E), kept in preferences rather than Firestore
/// because it is a device setting.
enum NoticeAppRule {
  all('all', 'Capture everything'),
  keywords('keywords', 'Only when it looks like a notice'),
  off('off', 'Off');

  const NoticeAppRule(this.wire, this.label);
  final String wire;
  final String label;

  static NoticeAppRule fromWire(String? value) => switch (value) {
    'keywords' => NoticeAppRule.keywords,
    'off' => NoticeAppRule.off,
    _ => NoticeAppRule.all,
  };
}
