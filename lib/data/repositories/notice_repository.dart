import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../firestore_paths.dart';
import '../mappers.dart';
import '../models.dart';

/// Captured school notifications (prompt 03 §B), under
/// `users/{uid}/notices/{noticeId}`.
///
/// Same contract as the other repositories — reads filter `isDeleted`,
/// writes validate first, nothing but an [AppFailure] escapes — with two
/// deliberate differences:
///
/// * **Upserts are `set` on an id derived from the dedupe hash**, so the
///   same notice captured on two phones is one document rather than two.
/// * **Retention really deletes.** Every other collection is soft-delete
///   only, but a notice is someone else's text with no long-term value, and
///   the disclosure promises it is gone after the retention period.
class NoticeRepository {
  const NoticeRepository();

  static const int pageSize = 300;
  static const int titleMax = 300;
  static const int bodyMax = Map$.noticeBodyMax;

  Stream<List<CapturedNotice>> watch(String uid) => Paths.notices(uid)
      .where('isDeleted', isEqualTo: false)
      .orderBy('postedAt', descending: true)
      .limit(pageSize)
      .snapshots()
      .map((snap) => snap.docs.map(Map$.noticeFrom).toList())
      .handleError((Object error) => throw AppFailure.from(error));

  /// Every non-deleted notice's hash — what the drain checks before writing.
  Future<Set<String>> knownHashes(String uid) async {
    try {
      final snap = await Paths.notices(uid)
          .where('isDeleted', isEqualTo: false)
          .limit(2000)
          .get();
      return {for (final d in snap.docs) Map$.str(d.data()['sourceHash'], d.id)};
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Creates or replaces. The id is [CapturedNotice.sourceHash] when the
  /// notice is new, so two phones write the same document.
  Future<CapturedNotice> save({
    required String uid,
    required CapturedNotice notice,
  }) async {
    _validate(notice);
    try {
      final id = notice.id.isEmpty ? notice.sourceHash : notice.id;
      final stored = notice.copyWith(id: id);
      final ref = Paths.notices(uid).doc(id);
      final isNew = notice.id.isEmpty;
      await ref.set({
        ...Map$.noticeToMap(stored),
        if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: !isNew));
      return stored;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> softDelete({required String uid, required String noticeId}) async {
    try {
      await Paths.notices(uid).doc(noticeId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Retention (§B): hard-deletes every notice posted before [before], in
  /// batches. Returns how many went.
  Future<int> purgeOlderThan({required String uid, required DateTime before}) async {
    try {
      var removed = 0;
      while (true) {
        final snap = await Paths.notices(uid)
            .where('postedAt', isLessThan: Timestamp.fromDate(before))
            .limit(200)
            .get();
        if (snap.docs.isEmpty) return removed;
        final batch = Paths.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        removed += snap.docs.length;
        if (snap.docs.length < 200) return removed;
      }
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// "Delete all captured notices" — everything, deleted or not.
  Future<int> deleteAll(String uid) async {
    try {
      var removed = 0;
      while (true) {
        final snap = await Paths.notices(uid).limit(200).get();
        if (snap.docs.isEmpty) return removed;
        final batch = Paths.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        removed += snap.docs.length;
        if (snap.docs.length < 200) return removed;
      }
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  static void _validate(CapturedNotice notice) {
    if (notice.packageName.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'This notice has no source app.',
        canRetry: false,
      );
    }
    if (notice.sourceHash.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'This notice cannot be identified.',
        canRetry: false,
      );
    }
    if (notice.title.trim().isEmpty && notice.body.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'This notice has no text.',
        canRetry: false,
      );
    }
  }
}
