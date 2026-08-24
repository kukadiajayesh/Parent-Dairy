import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../firestore_paths.dart';
import '../mappers.dart';
import '../models.dart';

/// Child profiles (§5). A parent may keep several; every academic record hangs
/// off exactly one.
class ChildRepository {
  const ChildRepository();

  /// Ordered oldest-first so the child switcher keeps a stable order rather
  /// than reshuffling whenever a profile is edited.
  Stream<List<Child>> watch(String uid) => Paths.children(uid)
      .where('isDeleted', isEqualTo: false)
      .orderBy('createdAt')
      .snapshots()
      .map((snap) => snap.docs.map(Map$.childFrom).toList())
      .handleError((Object error) => throw AppFailure.from(error));

  Future<Child> create(String uid, Child child) async {
    try {
      final ref = Paths.children(uid).doc();
      await ref.set({
        ...Map$.childToMap(child),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return child.copyWith(id: ref.id);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> update(String uid, Child child) async {
    if (child.id.isEmpty) {
      throw const AppFailure(
        FailureKind.notFound,
        'That child profile could not be found.',
        canRetry: false,
      );
    }
    try {
      await Paths.child(uid, child.id).update(Map$.childToMap(child));
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Soft delete (§30): the child drops out of every list but their years of
  /// worksheets stay recoverable.
  Future<void> delete(String uid, String childId) async {
    try {
      await Paths.child(uid, childId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
