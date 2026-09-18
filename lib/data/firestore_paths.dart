import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Every collection path in one place, shaped after the structure in the spec
/// (§27) and mirrored by `firestore.rules`.
///
/// ```
/// users/{uid}
/// users/{uid}/academicYears/{yearId}
/// users/{uid}/children/{childId}
/// users/{uid}/children/{childId}/subjects/{subjectId}
/// users/{uid}/children/{childId}/records/{recordId}
/// users/{uid}/children/{childId}/results/{resultId}
/// ```
///
/// Two deliberate choices against the spec's sketch:
///
/// * **Years hang off the user, not the child.** "2026–27" is a calendar fact
///   shared by every child in the family, and the design's year switcher is
///   global — duplicating years per child would let them drift apart.
/// * **One `records` collection carrying a `type` field**, which §27 offers as
///   the alternative. The timeline is the app's primary screen and it reads
///   worksheets and classwork interleaved; a single collection makes that one
///   query instead of a merge.
abstract final class Paths {
  static FirebaseFirestore? _override;

  /// Swapped for a fake in tests. Left null in the app, where the lazily
  /// resolved `FirebaseFirestore.instance` is correct.
  @visibleForTesting
  static set db(FirebaseFirestore? value) => _override = value;

  static FirebaseFirestore get _db => _override ?? FirebaseFirestore.instance;

  /// Batches must come from the same instance as the references they touch,
  /// so they go through here rather than reaching for the global singleton.
  static WriteBatch batch() => _db.batch();

  static DocumentReference<Map<String, dynamic>> user(String uid) =>
      _db.collection('users').doc(uid);

  static CollectionReference<Map<String, dynamic>> years(String uid) =>
      user(uid).collection('academicYears');

  static CollectionReference<Map<String, dynamic>> children(String uid) =>
      user(uid).collection('children');

  static DocumentReference<Map<String, dynamic>> child(
    String uid,
    String childId,
  ) => children(uid).doc(childId);

  static CollectionReference<Map<String, dynamic>> subjects(
    String uid,
    String childId,
  ) => child(uid, childId).collection('subjects');

  static CollectionReference<Map<String, dynamic>> records(
    String uid,
    String childId,
  ) => child(uid, childId).collection('records');

  /// Exam results — one document per report card, deliberately *not* a
  /// record variant: a report card spans every subject at once, while a
  /// record is single-subject, and the Performance tab needs the
  /// "this exam, across subjects" view intact.
  static CollectionReference<Map<String, dynamic>> results(
    String uid,
    String childId,
  ) => child(uid, childId).collection('results');

  /// Storage layout from §33. Files are namespaced by record so deleting a
  /// record can drop its whole folder, and never land in a shared bucket root.
  static String storageFolder({
    required String uid,
    required String childId,
    required String recordId,
    required String typeFolder,
  }) => 'users/$uid/children/$childId/$typeFolder/$recordId';
}
