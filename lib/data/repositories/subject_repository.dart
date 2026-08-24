import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../../core/theme/subject_hue.dart';
import '../firestore_paths.dart';
import '../mappers.dart';
import '../models.dart';

/// Subjects, kept per child as §7 describes — a Class 2 sibling should not
/// inherit Class 5's Social Science.
class SubjectRepository {
  const SubjectRepository();

  /// The starter list from §7, seeded for a newly created child so the first
  /// worksheet can be filed without a detour through Manage Subjects.
  static const defaults = <Subject>[
    Subject(name: 'Mathematics', abbr: 'MA', hue: SubjectHue.indigo, order: 1),
    Subject(name: 'English', abbr: 'EN', hue: SubjectHue.terracotta, order: 2),
    Subject(name: 'Science', abbr: 'SC', hue: SubjectHue.green, order: 3),
    Subject(name: 'Gujarati', abbr: 'GU', hue: SubjectHue.ochre, order: 4),
    Subject(name: 'Hindi', abbr: 'HI', hue: SubjectHue.violet, order: 5),
  ];

  Stream<List<Subject>> watch(String uid, String childId) =>
      Paths.subjects(uid, childId)
          .where('active', isEqualTo: true)
          .orderBy('order')
          .snapshots()
          .map((snap) => snap.docs.map(Map$.subjectFrom).toList())
          .handleError((Object error) => throw AppFailure.from(error));

  Future<Subject> create(String uid, String childId, Subject subject) async {
    try {
      final ref = Paths.subjects(uid, childId).doc();
      await ref.set({
        ...Map$.subjectToMap(subject),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return subject.copyWith(id: ref.id);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> update(String uid, String childId, Subject subject) async {
    if (subject.id.isEmpty) return;
    try {
      await Paths.subjects(
        uid,
        childId,
      ).doc(subject.id).update(Map$.subjectToMap(subject));
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Deactivates rather than deletes (§7 "delete/deactivate"): records already
  /// filed under the subject keep rendering their chip and colour.
  Future<void> deactivate(String uid, String childId, String subjectId) async {
    if (subjectId.isEmpty) return;
    try {
      await Paths.subjects(uid, childId).doc(subjectId).update({
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Persists a drag-reorder in one batch so the list never renders a
  /// half-applied order.
  Future<void> reorder(String uid, String childId, List<Subject> ordered) async {
    try {
      final batch = Paths.batch();
      for (var i = 0; i < ordered.length; i++) {
        if (ordered[i].id.isEmpty) continue;
        batch.update(Paths.subjects(uid, childId).doc(ordered[i].id), {
          'order': i + 1,
        });
      }
      await batch.commit();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> seedDefaults(String uid, String childId) async {
    try {
      final existing = await Paths.subjects(uid, childId).limit(1).get();
      if (existing.docs.isNotEmpty) return;
      final batch = Paths.batch();
      for (final subject in defaults) {
        batch.set(Paths.subjects(uid, childId).doc(), {
          ...Map$.subjectToMap(subject),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
