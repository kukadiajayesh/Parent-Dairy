import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../firestore_paths.dart';
import '../mappers.dart';
import '../models.dart';

/// Exam results — report cards, unit tests, term marks — kept in their own
/// collection so one document holds every subject of one exam.
///
/// Same contract as [RecordRepository]: every read filters `isDeleted`,
/// every write validates before it touches Firestore, and nothing but an
/// [AppFailure] ever escapes.
class ResultRepository {
  const ResultRepository();

  /// A year rarely holds more than a dozen results; 200 is a safety bound,
  /// not a page size.
  static const int pageSize = 200;

  /// Slack allowed on a result's date. A card handed out on Monday is often
  /// entered late Sunday night, so "today" is not a strict enough ceiling.
  static const Duration futureTolerance = Duration(days: 1);

  Stream<List<ExamResult>> watch({
    required String uid,
    required String childId,
    required String yearLabel,
  }) => Paths.results(uid, childId)
      .where('isDeleted', isEqualTo: false)
      .where('academicYearId', isEqualTo: yearLabel)
      .orderBy('date', descending: true)
      .limit(pageSize)
      .snapshots()
      .map((snap) => snap.docs.map(Map$.resultFrom).toList())
      .handleError((Object error) => throw AppFailure.from(error));

  /// Every year's results, newest first — what the all-years trend reads.
  Future<List<ExamResult>> allYears({
    required String uid,
    required String childId,
  }) async {
    try {
      final snap = await Paths.results(uid, childId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('date', descending: true)
          .limit(pageSize)
          .get();
      return snap.docs.map(Map$.resultFrom).toList();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<ExamResult> save({
    required String uid,
    required String childId,
    required ExamResult result,
  }) async {
    _validate(result);
    try {
      final collection = Paths.results(uid, childId);
      final isNew = result.id.isEmpty;
      final ref = isNew ? collection.doc() : collection.doc(result.id);
      final stored = result.copyWith(id: ref.id, childId: childId);

      await ref.set({
        ...Map$.resultToMap(stored),
        if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: !isNew));

      return stored;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> softDelete({
    required String uid,
    required String childId,
    required String resultId,
  }) async {
    try {
      await Paths.results(uid, childId).doc(resultId).update({
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
    required String resultId,
  }) async {
    try {
      await Paths.results(uid, childId).doc(resultId).update({
        'isDeleted': false,
        'deletedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Global search over exam label and subject names, mirroring
  /// [RecordRepository.search] so the search screen can show a Marks group.
  Future<List<ExamResult>> search({
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
      var q = Paths.results(uid, childId)
          .where('isDeleted', isEqualTo: false)
          .where('searchTerms', arrayContains: terms.first);
      if (yearLabel != null) {
        q = q.where('academicYearId', isEqualTo: yearLabel);
      }
      final snap =
          await q.orderBy('date', descending: true).limit(pageSize).get();
      final found = snap.docs.map(Map$.resultFrom).toList();
      if (terms.length == 1) return found;
      return found.where((r) {
        final haystack =
            '${r.examLabel} ${r.scores.map((s) => s.subject).join(' ')}'
                .toLowerCase();
        return terms.skip(1).every(haystack.contains);
      }).toList();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Enforced here rather than only in the form, so a result can never reach
  /// Firestore in a state the Performance tab cannot read.
  static void _validate(ExamResult result) {
    if (result.examLabel.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'Name the exam before saving — "Unit Test 1", "Term 1", …',
        canRetry: false,
      );
    }
    if (result.childId.isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'Choose a child before saving.',
        canRetry: false,
      );
    }
    if (result.academicYearId.isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'Choose an academic year before saving.',
        canRetry: false,
      );
    }
    if (result.date.isAfter(DateTime.now().add(futureTolerance))) {
      throw const AppFailure(
        FailureKind.invalidFile,
        "A result can't be dated in the future.",
        canRetry: false,
      );
    }
    if (result.scores.isEmpty) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'Add at least one subject before saving.',
        canRetry: false,
      );
    }
    for (final score in result.scores) {
      if (score.subject.trim().isEmpty) {
        throw const AppFailure(
          FailureKind.invalidFile,
          'Every row needs a subject name.',
          canRetry: false,
        );
      }
      final marks = score.marks;
      final max = score.maxMarks;
      if (marks != null && marks < 0) {
        throw AppFailure(
          FailureKind.invalidFile,
          "${score.subject}: marks can't be negative.",
          canRetry: false,
        );
      }
      if (max != null && max <= 0) {
        throw AppFailure(
          FailureKind.invalidFile,
          '${score.subject}: max marks must be more than zero.',
          canRetry: false,
        );
      }
      if (marks != null && max != null && marks > max) {
        throw AppFailure(
          FailureKind.invalidFile,
          "${score.subject}: marks can't be more than the maximum "
          '(${_trim(marks)} of ${_trim(max)}).',
          canRetry: false,
        );
      }
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
