import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../firestore_paths.dart';
import '../mappers.dart';
import '../models.dart';

/// Academic years (§6).
///
/// Years live on the parent, not the child: "2026–27" is the same span for
/// every sibling, and the design's year switcher is global. Starting a new year
/// never touches old records — history is preserved by scoping queries, not by
/// clearing anything.
class YearRepository {
  const YearRepository();

  /// Newest first, matching the switcher's ordering.
  Stream<List<AcademicYear>> watch(String uid) => Paths.years(uid)
      .orderBy('label', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(Map$.yearFrom).toList())
      .handleError((Object error) => throw AppFailure.from(error));

  Future<AcademicYear> create(String uid, AcademicYear year) async {
    try {
      final ref = Paths.years(uid).doc();
      await ref.set({
        ...Map$.yearToMap(year),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (year.active) await setActive(uid, year.label);
      return year.copyWith(id: ref.id);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Exactly one year carries `active`. Done as a batch so the switcher never
  /// sees two active years mid-write.
  Future<void> setActive(String uid, String label) async {
    try {
      final all = await Paths.years(uid).get();
      final batch = Paths.batch();
      for (final doc in all.docs) {
        final shouldBeActive = Map$.str(doc.data()['label']) == label;
        if (Map$.flag(doc.data()['active']) == shouldBeActive) continue;
        batch.update(doc.reference, {'active': shouldBeActive});
      }
      await batch.commit();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Keeps the "· 118 records" caption honest without counting documents.
  /// Fire-and-forget: a dropped counter must never fail a record save.
  Future<void> bumpRecordCount(String uid, String label, int delta) async {
    try {
      final match = await Paths.years(
        uid,
      ).where('label', isEqualTo: label).limit(1).get();
      if (match.docs.isEmpty) return;
      await match.docs.first.reference.update({
        'records': FieldValue.increment(delta),
      });
    } catch (_) {
      // Intentionally silent — see above.
    }
  }

  /// Creates the parent's first year from a label the child-setup screen
  /// collected, e.g. "2026–27" → "Apr 2026 – Mar 2027".
  Future<void> seedIfEmpty(String uid, String label) async {
    try {
      final existing = await Paths.years(uid).limit(1).get();
      if (existing.docs.isNotEmpty) return;
      await create(
        uid,
        AcademicYear(
          label: label,
          span: spanFor(label),
          records: 0,
          active: true,
        ),
      );
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// The Indian school year runs April–March, which is what the design's
  /// sample spans show.
  static String spanFor(String label) {
    final start = int.tryParse(RegExp(r'\d{4}').firstMatch(label)?.group(0) ?? '');
    if (start == null) return label;
    return 'Apr $start – Mar ${start + 1}';
  }
}
