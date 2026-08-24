import '../core/theme/subject_hue.dart';

enum RecordType { worksheet, classwork }

enum WorksheetStatus {
  pending('Pending'),
  completed('Completed');

  const WorksheetStatus(this.label);
  final String label;
}

class Subject {
  const Subject({
    required this.name,
    required this.abbr,
    required this.hue,
    required this.order,
    this.active = true,
  });

  final String name;
  final String abbr;
  final SubjectHue hue;
  final int order;
  final bool active;

  Subject copyWith({String? name, String? abbr, SubjectHue? hue, int? order, bool? active}) =>
      Subject(
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
  });

  final String name;
  final String initials;
  final String school;
  final String grade;
  final String section;
  final String year;

  String get meta => '$grade $section · $school';
  String get shortMeta => '$grade · $year';
}

class AcademicYear {
  const AcademicYear({
    required this.label,
    required this.span,
    required this.records,
    this.active = false,
  });

  final String label;
  final String span;
  final int records;
  final bool active;

  String get meta => '$span · $records records';
}

class Attachment {
  const Attachment({required this.name, required this.meta, this.isPdf = false});

  final String name;
  final String meta;
  final bool isPdf;
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
    this.dueDate,
    this.completedDate,
    this.notes = '',
    this.status = WorksheetStatus.pending,
    this.attachments = const [],
    this.answerKey,
  });

  final String id;
  final RecordType type;
  final String subject;
  final String title;
  final DateTime date;
  final DateTime? dueDate;
  final DateTime? completedDate;
  final String notes;
  final WorksheetStatus status;
  final List<Attachment> attachments;
  final Attachment? answerKey;

  bool get isWorksheet => type == RecordType.worksheet;

  bool get hasAnswerKey => answerKey != null;

  /// Pages/photos attached to the record. The answer key is counted separately
  /// — the design lists "2 files" for a worksheet that also carries a key.
  int get fileCount => attachments.length;
}
