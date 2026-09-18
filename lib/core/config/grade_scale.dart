/// Grade-to-percent scales for report cards that carry letters, not marks.
///
/// Indian schools report CBSE-style grades at least as often as raw marks,
/// and a grade has to become a number before it can be averaged or charted.
/// Each grade maps to the **midpoint** of its band — an A1 (91–100) becomes
/// 95.5 — and the caller flags the result as approximate rather than
/// pretending the school reported 95.5%.
///
/// Pure Dart: no Firebase, no Flutter, so the analytics and the models can
/// import it freely.
class GradeScale {
  const GradeScale({
    required this.id,
    required this.label,
    required this.bands,
  });

  /// Stable identifier persisted on the child (`Child.gradeScaleId`).
  final String id;
  final String label;

  /// Grade → inclusive percent band. Keys are upper-case; lookups normalise.
  final Map<String, ({double min, double max})> bands;

  /// Midpoint of the grade's band, or null when the grade is not on this
  /// scale (or the scale has no bands at all).
  double? percentFor(String? grade) {
    if (grade == null) return null;
    final band = bands[grade.trim().toUpperCase()];
    if (band == null) return null;
    return (band.min + band.max) / 2;
  }

  bool get hasBands => bands.isNotEmpty;

  static const String defaultId = 'cbse9';

  static const cbse9 = GradeScale(
    id: 'cbse9',
    label: 'CBSE 9-point',
    bands: {
      'A1': (min: 91, max: 100),
      'A2': (min: 81, max: 90),
      'B1': (min: 71, max: 80),
      'B2': (min: 61, max: 70),
      'C1': (min: 51, max: 60),
      'C2': (min: 41, max: 50),
      'D': (min: 33, max: 40),
      'E1': (min: 21, max: 32),
      'E2': (min: 0, max: 20),
    },
  );

  static const fiveLetter = GradeScale(
    id: 'five',
    label: 'Five-letter (A–E)',
    bands: {
      'A': (min: 81, max: 100),
      'B': (min: 61, max: 80),
      'C': (min: 41, max: 60),
      'D': (min: 21, max: 40),
      'E': (min: 0, max: 20),
    },
  );

  /// For schools whose grades do not map to marks at all: a grade is kept as
  /// text and never charted.
  static const none = GradeScale(id: 'none', label: 'None', bands: {});

  static const List<GradeScale> all = [cbse9, fiveLetter, none];

  /// Unknown or missing ids fall back to the default rather than throwing —
  /// a child document written before this field existed must keep working.
  static GradeScale byId(String? id) =>
      all.firstWhere((s) => s.id == id, orElse: () => cbse9);
}
