/// Normalises a subject name the model read off a report card against the
/// child's own subject list — in Dart, never by asking the model
/// (prompt 02 §E). "Maths" → "Mathematics", "EVS" → "Environmental Studies".
abstract final class SubjectMatcher {
  /// Common Indian report-card shorthands. Keys are lower-case.
  static const aliases = <String, List<String>>{
    'mathematics': ['maths', 'math', 'ganit'],
    'english': ['eng', 'english language', 'english lang'],
    'hindi': ['hin', 'hindi language'],
    'gujarati': ['guj'],
    'science': ['sci', 'general science', 'gen science'],
    'social science': ['sst', 's.st', 'social studies', 'social', 'sst.'],
    'environmental studies': ['evs', 'e.v.s', 'environment'],
    'computer': ['computers', 'computer science', 'it', 'ict'],
    'physical education': ['pe', 'p.e', 'pt', 'sports'],
    'art': ['drawing', 'arts', 'art & craft'],
    'sanskrit': ['sans', 'sanskrit language'],
    'general knowledge': ['gk', 'g.k'],
    'moral science': ['value education', 'values'],
  };

  /// The child's subject that [read] most likely means, or null when
  /// nothing is close enough to suggest. A suggestion is only ever a
  /// suggestion — the review screen shows "Maths → Mathematics?" and the
  /// parent confirms.
  static String? match(String read, List<String> known) {
    final needle = _norm(read);
    if (needle.isEmpty) return null;

    for (final k in known) {
      if (_norm(k) == needle) return k;
    }
    for (final k in known) {
      final canonical = _norm(k);
      final synonyms = aliases[canonical] ?? const [];
      if (synonyms.any((s) => _norm(s) == needle)) return k;
      // The reverse: the child's subject is itself an alias of what was read.
      for (final entry in aliases.entries) {
        if (entry.value.map(_norm).contains(canonical) && _norm(entry.key) == needle) {
          return k;
        }
      }
    }
    for (final k in known) {
      final canonical = _norm(k);
      if (canonical.startsWith(needle) || needle.startsWith(canonical)) {
        if (needle.length >= 3) return k;
      }
    }
    String? best;
    var bestDistance = 3;
    for (final k in known) {
      final d = _levenshtein(_norm(k), needle);
      if (d < bestDistance) {
        bestDistance = d;
        best = k;
      }
    }
    return best;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9& ]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}
