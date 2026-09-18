import '../../../data/models.dart';

/// What must never be sent to the model (prompt 02 §G.2).
///
/// The child's name, school, GR number, roll number and date of birth stay
/// on the phone. Prompts refer to "the student" and the grade. Everything
/// that builds a prompt goes through here, and the test asserts that a
/// prompt built from a fully-populated [Child] contains none of it.
abstract final class AiRedaction {
  static const String studentLabel = 'the student';

  /// `Class 4` — the only thing about the child a prompt carries.
  static String gradeContext(Child child) {
    final grade = child.grade.trim();
    return grade.isEmpty ? 'primary school' : grade;
  }

  /// Every string that identifies the child, for scrubbing free text.
  static List<String> identifiers(Child child) => [
    child.name,
    for (final part in child.name.split(RegExp(r'\s+')))
      if (part.length >= 3) part,
    child.school,
    ?child.grNumber,
    ?child.rollNumber,
    if (child.dateOfBirth != null) ...[
      _iso(child.dateOfBirth!),
      _dmy(child.dateOfBirth!),
    ],
  ].where((s) => s.trim().length >= 2).toList();

  /// Replaces any identifier in [text] — a teacher's remark that names the
  /// child, a worksheet title with the school on it — before it is sent.
  static String scrub(String text, Child child) {
    var out = text;
    for (final id in identifiers(child)) {
      out = out.replaceAll(
        RegExp(RegExp.escape(id), caseSensitive: false),
        studentLabel,
      );
    }
    return out;
  }

  /// True when [prompt] leaks nothing. Cheap enough to assert in debug on
  /// every request.
  static bool isClean(String prompt, Child child) {
    final lower = prompt.toLowerCase();
    for (final id in identifiers(child)) {
      if (lower.contains(id.toLowerCase())) return false;
    }
    return true;
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _dmy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
