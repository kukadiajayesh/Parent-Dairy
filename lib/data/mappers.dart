import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/theme/subject_hue.dart';
import 'models.dart';

/// Firestore ⇄ model conversion, kept out of `models.dart` so the model file
/// stays pure Dart — every widget imports it, and none of them should pull in
/// the Firestore SDK to compile.
///
/// Reads are defensive on purpose: a document written by an older build must
/// never crash the timeline, so every field falls back rather than throwing.
abstract final class Map$ {
  // ── primitives ──────────────────────────────────────────────────────────
  static DateTime? date(Object? value) => switch (value) {
    Timestamp t => t.toDate(),
    DateTime d => d,
    String s => DateTime.tryParse(s),
    int ms => DateTime.fromMillisecondsSinceEpoch(ms),
    _ => null,
  };

  static String str(Object? value, [String fallback = '']) =>
      value is String ? value : fallback;

  static int integer(Object? value, [int fallback = 0]) => switch (value) {
    int i => i,
    double d => d.round(),
    String s => int.tryParse(s) ?? fallback,
    _ => fallback,
  };

  static bool flag(Object? value, [bool fallback = false]) =>
      value is bool ? value : fallback;

  static SubjectHue hue(Object? value) => SubjectHue.values.firstWhere(
    (h) => h.name == value,
    orElse: () => SubjectHue.stone,
  );

  // ── Subject ─────────────────────────────────────────────────────────────
  static Map<String, dynamic> subjectToMap(Subject s) => {
    'name': s.name,
    'abbr': s.abbr,
    'hue': s.hue.name,
    'order': s.order,
    'active': s.active,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static Subject subjectFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Subject(
      id: doc.id,
      name: str(m['name']),
      abbr: str(m['abbr']),
      hue: hue(m['hue']),
      order: integer(m['order']),
      active: flag(m['active'], true),
    );
  }

  // ── Child ───────────────────────────────────────────────────────────────
  static Map<String, dynamic> childToMap(Child c) => {
    'name': c.name,
    'initials': c.initials,
    'school': c.school,
    'grade': c.grade,
    'section': c.section,
    'year': c.year,
    'photoUrl': c.photoUrl,
    'grNumber': c.grNumber,
    'rollNumber': c.rollNumber,
    'dateOfBirth': c.dateOfBirth == null
        ? null
        : Timestamp.fromDate(c.dateOfBirth!),
    'notes': c.notes,
    'isDeleted': false,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static Child childFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    final name = str(m['name']);
    return Child(
      id: doc.id,
      name: name,
      initials: str(m['initials'], Child.initialsFor(name)),
      school: str(m['school']),
      grade: str(m['grade']),
      section: str(m['section']),
      year: str(m['year']),
      photoUrl: m['photoUrl'] as String?,
      grNumber: m['grNumber'] as String?,
      rollNumber: m['rollNumber'] as String?,
      dateOfBirth: date(m['dateOfBirth']),
      notes: str(m['notes']),
    );
  }

  // ── AcademicYear ────────────────────────────────────────────────────────
  static Map<String, dynamic> yearToMap(AcademicYear y) => {
    'label': y.label,
    'span': y.span,
    'records': y.records,
    'active': y.active,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static AcademicYear yearFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return AcademicYear(
      id: doc.id,
      label: str(m['label']),
      span: str(m['span']),
      records: integer(m['records']),
      active: flag(m['active']),
    );
  }

  // ── Attachment ──────────────────────────────────────────────────────────
  static Map<String, dynamic> attachmentToMap(Attachment a) => {
    'id': a.id,
    'name': a.name,
    'meta': a.meta,
    'isPdf': a.isPdf,
    'storagePath': a.storagePath,
    'downloadUrl': a.downloadUrl,
    'localPath': a.localPath,
    'fileSize': a.fileSize,
    'mimeType': a.mimeType,
    'sync': a.sync.wire,
  };

  static Attachment attachmentFrom(Map<String, dynamic> m) {
    final name = str(m['name'], 'attachment');
    final mime = m['mimeType'] as String?;
    final isPdf =
        flag(m['isPdf']) ||
        name.toLowerCase().endsWith('.pdf') ||
        (mime ?? '').toLowerCase().contains('pdf');

    return Attachment(
      id: str(m['id']),
      name: name,
      meta: str(m['meta']),
      isPdf: isPdf,
      storagePath: m['storagePath'] as String?,
      downloadUrl: m['downloadUrl'] as String?,
      localPath: m['localPath'] as String?,
      fileSize: integer(m['fileSize']),
      mimeType: mime,
      sync: SyncState.fromWire(m['sync'] as String?),
    );
  }

  static List<Attachment> attachmentsFrom(Object? value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is Map) attachmentFrom(Map<String, dynamic>.from(entry)),
    ];
  }

  // ── DiaryRecord ─────────────────────────────────────────────────────────
  static Map<String, dynamic> recordToMap(DiaryRecord r) => {
    'childId': r.childId,
    'academicYearId': r.academicYearId,
    'type': r.type.wire,
    'subject': r.subject,
    // Lower-cased haystack so search can prefix-match in Firestore without a
    // third-party index. Rebuilt on every write.
    'searchTerms': searchTermsFor(r),
    'title': r.title,
    'date': Timestamp.fromDate(r.date),
    'dueDate': r.dueDate == null ? null : Timestamp.fromDate(r.dueDate!),
    'completedDate': r.completedDate == null
        ? null
        : Timestamp.fromDate(r.completedDate!),
    'chapter': r.chapter,
    'notes': r.notes,
    'status': r.status.wire,
    'attachments': [for (final a in r.attachments) attachmentToMap(a)],
    'answerKey': r.answerKey == null ? null : attachmentToMap(r.answerKey!),
    // Denormalised so the upload queue can find stranded records with one
    // query — Firestore cannot filter on a field inside an array of maps.
    'hasPendingUpload': r.sync != SyncState.synced,
    'isDeleted': r.isDeleted,
    'deletedAt': r.deletedAt == null
        ? null
        : Timestamp.fromDate(r.deletedAt!),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static DiaryRecord recordFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    final answerKey = m['answerKey'];
    return DiaryRecord(
      id: doc.id,
      childId: str(m['childId']),
      academicYearId: str(m['academicYearId']),
      type: RecordType.fromWire(m['type'] as String?),
      subject: str(m['subject']),
      title: str(m['title']),
      date: date(m['date']) ?? DateTime.now(),
      dueDate: date(m['dueDate']),
      completedDate: date(m['completedDate']),
      chapter: str(m['chapter']),
      notes: str(m['notes']),
      status: WorksheetStatus.fromWire(m['status'] as String?),
      attachments: attachmentsFrom(m['attachments']),
      answerKey: answerKey is Map
          ? attachmentFrom(Map<String, dynamic>.from(answerKey))
          : null,
      createdAt: date(m['createdAt']),
      updatedAt: date(m['updatedAt']),
      isDeleted: flag(m['isDeleted']),
      deletedAt: date(m['deletedAt']),
    );
  }

  /// Distinct lower-cased words from the fields §15 says search covers, so
  /// "math" finds a Mathematics worksheet by title, note or subject.
  static List<String> searchTermsFor(DiaryRecord r) {
    final words = <String>{};
    for (final source in [r.title, r.notes, r.subject]) {
      for (final word in source.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
        if (word.length > 1) words.add(word);
      }
    }
    // Firestore caps array members; 40 words is far more than any title needs.
    return words.take(40).toList();
  }
}
