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

  String get meta => '$grade $section · $school';
  String get shortMeta => '$grade · $year';

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

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Soft delete. Deleted records stay in Firestore and drop out of every UI
  /// query, so a mis-tap never destroys a year of history.
  final bool isDeleted;
  final DateTime? deletedAt;

  bool get isWorksheet => type == RecordType.worksheet;
  bool get isExam => type == RecordType.exam;

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
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
