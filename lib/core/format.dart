/// Date formatting helpers matching the strings used across the design.
/// Kept dependency-free so the app runs without `intl`.
abstract final class AppDate {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  /// `23 Aug 2026`
  static String full(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// `23 Aug`
  static String short(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  /// `Fri, 28 Aug`
  static String dueLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

  /// `Sun · 23 Aug` — timeline day heading.
  static String dayHeading(DateTime d) =>
      '${_weekdays[d.weekday - 1]} · ${d.day} ${_months[d.month - 1]}';

  /// `Apr 2027`
  static String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

abstract final class AppFormat {
  static String fileCount(int n) => '$n file${n == 1 ? '' : 's'}';
  static String photoCount(int n) => '$n photo${n == 1 ? '' : 's'}';
  static String attachmentCount(int n) => '$n attachment${n == 1 ? '' : 's'}';

  /// Two-letter monogram from a name — "Aarav Patel" → "AP", "Aarav" → "AA".
  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
    }
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}
