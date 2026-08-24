import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../firestore_paths.dart';
import '../mappers.dart';
import '../models.dart';

/// Worksheets and classwork — one collection with a `type` field, which is the
/// alternative §27 offers and the one the timeline wants (§13).
///
/// Every read filters `isDeleted == false`, so a soft-deleted record (§30)
/// vanishes from the UI while staying recoverable in Firestore.
class RecordRepository {
  const RecordRepository();

  /// How many records the timeline holds in memory. A parent with six years of
  /// history should not stream 5,000 documents to draw one screen; older
  /// records are reached through search and the year switcher.
  static const int pageSize = 400;

  Stream<List<DiaryRecord>> watch({
    required String uid,
    required String childId,
    required String yearLabel,
  }) => Paths.records(uid, childId)
      .where('isDeleted', isEqualTo: false)
      .where('academicYearId', isEqualTo: yearLabel)
      .orderBy('date', descending: true)
      .limit(pageSize)
      .snapshots()
      .map((snap) => snap.docs.map(Map$.recordFrom).toList())
      .handleError((Object error) => throw AppFailure.from(error));

  Future<DiaryRecord> save({
    required String uid,
    required String childId,
    required DiaryRecord record,
  }) async {
    _validate(record);
    try {
      final collection = Paths.records(uid, childId);
      final isNew = record.id.isEmpty;
      final ref = isNew ? collection.doc() : collection.doc(record.id);
      final stored = record.copyWith(id: ref.id, childId: childId);

      await ref.set({
        ...Map$.recordToMap(stored),
        if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: !isNew));

      return stored;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Replaces the attachment lists after an upload settles. Scoped to those
  /// fields so it cannot clobber an edit the parent made in the meantime.
  Future<void> updateFiles({
    required String uid,
    required String childId,
    required String recordId,
    required List<Attachment> attachments,
    Attachment? answerKey,
  }) async {
    try {
      final pending = [
        ...attachments,
        ?answerKey,
      ].any((a) => a.sync != SyncState.synced);

      await Paths.records(uid, childId).doc(recordId).update({
        'attachments': [for (final a in attachments) Map$.attachmentToMap(a)],
        'answerKey': answerKey == null
            ? null
            : Map$.attachmentToMap(answerKey),
        'hasPendingUpload': pending,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> markCompleted({
    required String uid,
    required String childId,
    required String recordId,
    required bool completed,
  }) async {
    try {
      await Paths.records(uid, childId).doc(recordId).update({
        'status': (completed ? WorksheetStatus.completed : WorksheetStatus.pending)
            .wire,
        'completedDate': completed ? Timestamp.now() : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Soft delete (§30). The document and its Storage files both survive.
  Future<void> softDelete({
    required String uid,
    required String childId,
    required String recordId,
  }) async {
    try {
      await Paths.records(uid, childId).doc(recordId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> restore({
    required String uid,
    required String childId,
    required String recordId,
  }) async {
    try {
      await Paths.records(uid, childId).doc(recordId).update({
        'isDeleted': false,
        'deletedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Global search (§15) over title, notes and subject.
  ///
  /// Matches on the `searchTerms` array the mapper builds, so a one-word query
  /// is a single indexed lookup. Multi-word queries filter the first term's
  /// results in memory — cheap, because the first term already narrows hard.
  Future<List<DiaryRecord>> search({
    required String uid,
    required String childId,
    required String query,
    String? yearLabel,
  }) async {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return const [];

    try {
      var q = Paths.records(uid, childId)
          .where('isDeleted', isEqualTo: false)
          .where('searchTerms', arrayContains: terms.first);
      if (yearLabel != null) {
        q = q.where('academicYearId', isEqualTo: yearLabel);
      }

      final snap = await q.orderBy('date', descending: true).limit(pageSize).get();
      final results = snap.docs.map(Map$.recordFrom).toList();
      if (terms.length == 1) return results;

      // Firestore allows only one arrayContains per query, so the remaining
      // terms are applied client-side against the narrowed set.
      return results.where((r) {
        final haystack = '${r.title} ${r.notes} ${r.subject}'.toLowerCase();
        return terms.skip(1).every(haystack.contains);
      }).toList();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Records whose files never made it to Storage — the upload queue's inbox.
  Future<List<DiaryRecord>> pendingUploads({
    required String uid,
    required String childId,
  }) async {
    try {
      final snap = await Paths.records(uid, childId)
          .where('isDeleted', isEqualTo: false)
          .where('hasPendingUpload', isEqualTo: true)
          .limit(50)
          .get();
      return snap.docs.map(Map$.recordFrom).toList();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// §31. Enforced here rather than only in the form so a record can never
  /// reach Firestore in a state the timeline cannot render.
  static void _validate(DiaryRecord record) {
    if (record.title.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'Add a title before saving.',
        canRetry: false,
      );
    }
    if (record.subject.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'Choose a subject before saving.',
        canRetry: false,
      );
    }
    if (record.childId.isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'Choose a child before saving.',
        canRetry: false,
      );
    }
    if (record.academicYearId.isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'Choose an academic year before saving.',
        canRetry: false,
      );
    }
    if (record.dueDate != null && record.dueDate!.isBefore(record.date)) {
      throw const AppFailure(
        FailureKind.invalidFile,
        "A worksheet's due date cannot be before its date.",
        canRetry: false,
      );
    }
  }
}
