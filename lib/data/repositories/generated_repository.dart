import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../firestore_paths.dart';
import '../mappers.dart';
import '../models_ai.dart';

/// Structured AI artefacts — generated papers, scanned questions, answer
/// keys, gradings — one document each, beside the record they produced.
///
/// Same contract as the other repositories: reads filter `isDeleted`, writes
/// validate first, nothing but an [AppFailure] escapes.
class GeneratedRepository {
  const GeneratedRepository();

  /// A child accumulates a few dozen of these a year; 200 is a safety bound.
  static const int pageSize = 200;

  Stream<List<GeneratedDoc>> watch({
    required String uid,
    required String childId,
  }) => Paths.generated(uid, childId)
      .where('isDeleted', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .limit(pageSize)
      .snapshots()
      .map((snap) => snap.docs.map(Map$.generatedFrom).toList())
      .handleError((Object error) => throw AppFailure.from(error));

  Future<GeneratedDoc> save({
    required String uid,
    required String childId,
    required GeneratedDoc doc,
  }) async {
    _validate(doc);
    try {
      final collection = Paths.generated(uid, childId);
      final isNew = doc.id.isEmpty;
      final ref = isNew ? collection.doc() : collection.doc(doc.id);
      final stored = doc.copyWith(id: ref.id, childId: childId);
      await ref.set({
        ...Map$.generatedToMap(stored),
        if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: !isNew));
      return stored;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Points an artefact at the record or result it was filed as, once that
  /// exists. Scoped to the link fields so it never clobbers the payload.
  Future<void> link({
    required String uid,
    required String childId,
    required String generatedId,
    String? recordId,
    String? examRecordId,
    String? resultId,
  }) async {
    try {
      await Paths.generated(uid, childId).doc(generatedId).update({
        'recordId': ?recordId,
        'examRecordId': ?examRecordId,
        'resultId': ?resultId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> softDelete({
    required String uid,
    required String childId,
    required String generatedId,
  }) async {
    try {
      await Paths.generated(uid, childId).doc(generatedId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  static void _validate(GeneratedDoc doc) {
    if (doc.title.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'The generated document has no title.',
        canRetry: false,
      );
    }
    if (doc.payload.isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'There is nothing to save yet.',
        canRetry: false,
      );
    }
  }
}
