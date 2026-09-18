import '../../core/services/ai/subject_matcher.dart';
import '../models.dart';

/// Stage 1 of notice extraction (prompt 03 §C): deterministic, pure Dart, no
/// network. Reads a school notification's title and body and pulls out what
/// kind of event it is, when, and which subject — with a confidence the
/// auto-arm policy can trust.
///
/// Every relative date is anchored on the notice's `postedAt` in the device
/// timezone. Dates are read **day-first** (`24/11` is 24 November), the
/// Indian convention. When the year is missing the next occurrence within
/// eleven months is chosen; a date that would fall further out than that is
/// kept in the current year even though it has passed, because "15 Sep"
/// posted on 20 September is far more likely last week's exam than next
/// year's.
abstract final class NoticeExtractor {
  // ── kind keywords (§C) ──────────────────────────────────────────────────
  //
  // Multi-word phrases score 2, ordinary words 1, and a handful of words
  // that appear in every kind of notice ("due", "term", "submit") score
  // half — so "fee due 10 Oct" is a fee and "holiday homework" is homework.

  static const Map<NoticeKind, List<String>> _keywords = {
    NoticeKind.exam: [
      'exam', 'exams', 'examination', 'test', 'tests', 'unit test', 'ut',
      'periodic', 'periodic test', 'pt', 'assessment', 'viva', 'practical',
      'practicals', 'half yearly', 'half-yearly', 'pre-board', 'pre board',
      'preboard', 'board', 'boards', 'olympiad', 'term', 'revision test',
      'class test', 'dictation',
    ],
    NoticeKind.assignment: [
      'homework', 'hw', 'h.w', 'assignment', 'assignments', 'project',
      'projects', 'submission', 'submit', 'due', 'worksheet', 'worksheets',
      'holiday homework', 'last date', 'deadline',
    ],
    NoticeKind.activity: [
      'sports day', 'annual day', 'annual function', 'competition',
      'elocution', 'drawing', 'quiz', 'field trip', 'excursion', 'picnic',
      'rehearsal', 'fancy dress', 'celebration', 'cultural', 'assembly',
      'recitation', 'debate', 'exhibition', 'science fair', 'fete',
    ],
    NoticeKind.holiday: [
      'holiday', 'holidays', 'no school', 'closed', 'vacation', 'leave',
      'off day', 'school off', 'remain closed', 'will be closed',
    ],
    NoticeKind.fee: [
      'fee', 'fees', 'payment', 'installment', 'instalment', 'due amount',
      'tuition', 'pay online', 'paid by', 'late fee',
    ],
    NoticeKind.meeting: [
      'ptm', 'p.t.m', 'parent teacher', 'parent-teacher', 'parents teacher',
      'orientation', 'open house', 'meeting', 'counselling', 'counseling',
    ],
    NoticeKind.announcement: [
      'circular', 'notice', 'announcement', 'kindly note', 'dear parents',
      'dear parent', 'reminder', 'timetable', 'time table', 'result',
      'results', 'report card', 'uniform', 'bus',
    ],
  };

  /// Words that belong to several kinds at once; they only tip the balance.
  static const Set<String> _weak = {
    'due', 'term', 'submit', 'board', 'leave', 'test', 'closed', 'result',
    'results', 'reminder', 'notice', 'meeting', 'drawing', 'pt', 'ut',
  };

  /// Tie-break order when two kinds score the same.
  static const List<NoticeKind> _priority = [
    NoticeKind.exam,
    NoticeKind.assignment,
    NoticeKind.meeting,
    NoticeKind.fee,
    NoticeKind.activity,
    NoticeKind.holiday,
    NoticeKind.announcement,
  ];

  // ── subjects ────────────────────────────────────────────────────────────

  /// Shorthands seen in Indian school notices, on top of
  /// [SubjectMatcher.aliases]. Two-letter aliases like `it` and `pe` are
  /// deliberately left out — they match ordinary words.
  static const Map<String, List<String>> _subjectAliases = {
    'mathematics': ['maths', 'math', 'mathematics', 'ganit'],
    'science': ['sci', 'science', 'general science'],
    'english': ['eng', 'english'],
    'hindi': ['hin', 'hindi'],
    'gujarati': ['guj', 'gujarati'],
    'social science': ['sst', 's.st', 's.s.t', 'social science', 'social studies', 'social'],
    'environmental studies': ['evs', 'e.v.s', 'environmental studies'],
    'computer': ['comp', 'computer', 'computers', 'computer science', 'ict'],
    'sanskrit': ['sanskrit', 'sans'],
    'general knowledge': ['gk', 'g.k', 'general knowledge'],
    'physical education': ['physical education', 'p.e', 'sports'],
    'art': ['art', 'craft', 'art & craft', 'art and craft'],
    'moral science': ['moral science', 'value education'],
    'physics': ['physics', 'phy'],
    'chemistry': ['chemistry', 'chem'],
    'biology': ['biology', 'bio'],
    'history': ['history'],
    'geography': ['geography', 'geo'],
    'civics': ['civics'],
    'economics': ['economics', 'eco'],
    'marathi': ['marathi'],
  };

  // ── dates ───────────────────────────────────────────────────────────────

  static const List<String> _months = [
    'january', 'february', 'march', 'april', 'may', 'june', 'july',
    'august', 'september', 'october', 'november', 'december',
  ];

  static const _monthPattern =
      r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

  static const _weekdays = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];
  static const _weekdayPattern =
      r'(mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)';

  static final _timeRe = RegExp(
    r'\b(\d{1,2})(?:[:.](\d{2}))?\s*(a\.?m\.?|p\.?m\.?)(?![a-z])',
    caseSensitive: false,
  );
  static final _time24Re = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b(?!\s*(?:a|p)\.?m)', caseSensitive: false);

  /// `24–26 November`, `24-26 Nov 2026`.
  static final _dayRangeRe = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|–|—|to|till|until)\s*(\d{1,2})(?:st|nd|rd|th)?\s+' +
        _monthPattern +
        r"\.?,?(?:\s+(\d{4}|'?\d{2}(?!\d)))?",
    caseSensitive: false,
  );

  /// `24 Nov`, `24th November 2026`, `24 of Nov`, `24-Nov-26`.
  static final _dayMonthRe = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?[\s\-/.]*(?:of\s+)?' +
        _monthPattern +
        r"\.?,?(?:[\s\-/.]*(\d{4}|'\d{2}|\d{2}(?![\d:])))?",
    caseSensitive: false,
  );

  /// `November 24`, `Nov 24, 2026`.
  static final _monthDayRe = RegExp(
    _monthPattern + r'\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?!\s*[:.]\d)(?:,?\s+(\d{4}))?\b',
    caseSensitive: false,
  );

  /// `24/11/2026`, `24-11-26`, `24.11`.
  static final _numericRe = RegExp(
    r'(?<![\d/.\-])(\d{1,2})([/.\-])(\d{1,2})(?:[/.\-](\d{4}|\d{2}))?(?!\d|[/.\-]\d|\s*(?:a|p)\.?m)',
    caseSensitive: false,
  );

  static final _relativeRe = RegExp(
    '\\b(day after tomorrow|tomorrow|today|tonight|in\\s+(\\d{1,2})\\s+days?|'
    '(?:next|this|coming|on|by|from|till|until)\\s+$_weekdayPattern)\\b',
    caseSensitive: false,
  );

  static final _rangeJoinRe = RegExp(r'^\s*(?:-|–|—|to|till|until|through|upto|up to)\s*$', caseSensitive: false);
  static final _dueCueRe = RegExp(
    r'\b(due|submit|submitted|submission|by|before|last date|deadline|latest by|on or before|pay|paid)\b',
    caseSensitive: false,
  );

  static final _latinRe = RegExp(r'[A-Za-z]');

  // ── entry point ─────────────────────────────────────────────────────────

  static NoticeExtraction extract({
    required String title,
    required String body,
    required DateTime postedAt,
    List<String> subjects = const [],
  }) {
    final text = '${title.trim()}\n${body.trim()}'.trim();
    final matched = <String>[];

    final kind = _detectKind(text, matched);
    final subject = _detectSubject(text, subjects, matched);
    final time = _detectTime(text, matched);
    final dates = _detectDates(text, postedAt, matched);

    _DateHit? primary;
    _DateHit? end;
    final alternates = <DateTime>[];

    if (dates.isNotEmpty) {
      // A due-cue right before a date wins for things that are due; a range
      // is one event, not two candidates.
      primary = kind.isDue ? (dates.where((d) => d.afterDueCue).firstOrNull ?? dates.first) : dates.first;
      end = primary.rangeEnd;
      for (final d in dates) {
        if (identical(d, primary)) continue;
        if (!_sameDay(d.date, primary.date)) alternates.add(d.date);
      }
    }

    DateTime? eventAt;
    DateTime? dueAt;
    DateTime? endAt;
    var allDay = true;
    if (primary != null) {
      var when = primary.date;
      if (time != null) {
        when = DateTime(when.year, when.month, when.day, time.$1, time.$2);
        allDay = false;
      }
      if (kind.isDue) {
        dueAt = when;
      } else {
        eventAt = when;
      }
      endAt = end?.date;
    }

    final hasKind = kind != NoticeKind.unknown && kind != NoticeKind.announcement;
    double confidence;
    if (hasKind && primary != null && !primary.relative) {
      confidence = 0.9;
    } else if (hasKind && primary != null) {
      confidence = 0.7;
    } else if (hasKind) {
      confidence = 0.5;
    } else if (kind == NoticeKind.announcement && primary != null) {
      confidence = 0.5;
    } else {
      confidence = 0.3;
    }
    // Two candidate dates: the parent picks, so never auto-arm (§D).
    if (alternates.isNotEmpty && confidence > 0.6) confidence = 0.6;
    // Nothing Latin at all — a Gujarati or Hindi notice. Stage 1 can still
    // read a numeric date but cannot vouch for the kind.
    if (!_latinRe.hasMatch(text) && confidence > 0.3) confidence = 0.3;

    return NoticeExtraction(
      kind: kind,
      title: cleanTitle(title: title, body: body, subject: subject, kind: kind),
      subject: subject,
      eventAt: eventAt,
      endAt: endAt,
      allDay: allDay,
      dueAt: dueAt,
      confidence: confidence,
      source: 'rules',
      matchedPhrases: matched.toSet().toList(),
      alternateDates: alternates,
    );
  }

  /// True when the text carries any kind keyword — the "only when it
  /// matches keywords" per-app rule (§E) reads this.
  static bool looksLikeNotice(String text) =>
      _detectKind(text, []) != NoticeKind.unknown;

  // ── kind ────────────────────────────────────────────────────────────────

  static NoticeKind _detectKind(String text, List<String> matched) {
    final lower = text.toLowerCase();
    final scores = <NoticeKind, double>{};
    final hits = <NoticeKind, List<String>>{};
    for (final entry in _keywords.entries) {
      for (final word in entry.value) {
        final re = RegExp(r'(?<![a-z0-9])' + RegExp.escape(word) + r'(?![a-z0-9])');
        final count = re.allMatches(lower).length;
        if (count == 0) continue;
        final weight = word.contains(' ') || word.contains('-')
            ? 2.0
            : (_weak.contains(word) ? 0.5 : 1.0);
        scores[entry.key] = (scores[entry.key] ?? 0) + weight * count;
        hits.putIfAbsent(entry.key, () => []).add(word);
      }
    }
    if (scores.isEmpty) return NoticeKind.unknown;
    NoticeKind? best;
    var bestScore = 0.0;
    for (final kind in _priority) {
      final s = scores[kind] ?? 0;
      if (s > bestScore) {
        bestScore = s;
        best = kind;
      }
    }
    // An announcement word is only decisive when nothing more specific
    // scored at all — "circular: unit test on 24 Nov" is an exam.
    if (best == NoticeKind.announcement) {
      for (final kind in _priority) {
        if (kind != NoticeKind.announcement && (scores[kind] ?? 0) >= 1) {
          best = kind;
          break;
        }
      }
    }
    matched.addAll(hits[best] ?? const []);
    return best ?? NoticeKind.unknown;
  }

  // ── subject ─────────────────────────────────────────────────────────────

  static String? _detectSubject(String text, List<String> subjects, List<String> matched) {
    final lower = text.toLowerCase();
    RegExpMatch? firstMatch(String alias) {
      final re = RegExp(r'(?<![a-z])' + RegExp.escape(alias.toLowerCase()) + r'(?![a-z])');
      return re.firstMatch(lower);
    }

    // The subject mentioned *first* wins ("Science test on 24 Nov and Maths
    // test on 26 Nov" is about Science); at the same position the longer
    // name wins, so "Social Science" beats "Science".
    String? best;
    String? bestAlias;
    var bestStart = 1 << 30;
    for (final name in subjects) {
      final canonical = name.toLowerCase().trim();
      final aliases = <String>{
        canonical,
        ...?_subjectAliases[canonical],
        ...?SubjectMatcher.aliases[canonical],
      }.where((a) => a.length >= 3 || a == 'gk');
      for (final alias in aliases) {
        final m = firstMatch(alias);
        if (m == null) continue;
        final better = m.start < bestStart ||
            (m.start == bestStart && name.length > (best?.length ?? 0));
        if (better) {
          best = name;
          bestAlias = alias;
          bestStart = m.start;
        }
      }
    }
    if (bestAlias != null) matched.add(bestAlias);
    // A subject the diary does not know yet is still worth naming in the
    // title, but it is not "matched" — the extraction leaves subject null.
    return best;
  }

  /// The canonical name of any subject-like word in [text], for the title.
  static String? _anySubjectWord(String text) {
    final lower = text.toLowerCase();
    for (final entry in _subjectAliases.entries) {
      for (final alias in entry.value) {
        if (alias.length < 3) continue;
        final re = RegExp(r'(?<![a-z])' + RegExp.escape(alias) + r'(?![a-z])');
        if (re.hasMatch(lower)) return _titleCase(entry.key);
      }
    }
    return null;
  }

  // ── time ────────────────────────────────────────────────────────────────

  static (int, int)? _detectTime(String text, List<String> matched) {
    final m = _timeRe.firstMatch(text);
    if (m != null) {
      var hour = int.parse(m.group(1)!);
      final minute = int.tryParse(m.group(2) ?? '') ?? 0;
      final pm = m.group(3)!.toLowerCase().startsWith('p');
      if (hour < 1 || hour > 12 || minute > 59) return null;
      if (pm && hour != 12) hour += 12;
      if (!pm && hour == 12) hour = 0;
      matched.add(m.group(0)!.trim());
      return (hour, minute);
    }
    final m24 = _time24Re.firstMatch(text);
    if (m24 != null) {
      matched.add(m24.group(0)!);
      return (int.parse(m24.group(1)!), int.parse(m24.group(2)!));
    }
    return null;
  }

  // ── dates ───────────────────────────────────────────────────────────────

  static List<_DateHit> _detectDates(String text, DateTime postedAt, List<String> matched) {
    final hits = <_DateHit>[];
    final taken = <(int, int)>[];
    bool overlaps(int start, int end) => taken.any((t) => start < t.$2 && end > t.$1);
    void claim(int start, int end) => taken.add((start, end));

    final today = DateTime(postedAt.year, postedAt.month, postedAt.day);

    // Times are masked first so "9.30" is never read as 9 March.
    for (final m in _timeRe.allMatches(text)) {
      claim(m.start, m.end);
    }
    for (final m in _time24Re.allMatches(text)) {
      claim(m.start, m.end);
    }

    // Day ranges within one month.
    for (final m in _dayRangeRe.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      final month = _monthIndex(m.group(3)!);
      final year = _yearOf(m.group(4));
      final start = _resolve(int.parse(m.group(1)!), month, year, today);
      final end = _resolve(int.parse(m.group(2)!), month, year, today);
      if (start == null || end == null) continue;
      claim(m.start, m.end);
      hits.add(_DateHit(start, m.start, m.end, rangeEnd: _DateHit(end, m.start, m.end)));
      matched.add(m.group(0)!.trim());
    }

    for (final m in _dayMonthRe.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      final month = _monthIndex(m.group(2)!);
      final date = _resolve(int.parse(m.group(1)!), month, _yearOf(m.group(3)), today);
      if (date == null) continue;
      claim(m.start, m.end);
      hits.add(_DateHit(date, m.start, m.end));
      matched.add(m.group(0)!.trim());
    }

    for (final m in _monthDayRe.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      final month = _monthIndex(m.group(1)!);
      final date = _resolve(int.parse(m.group(2)!), month, _yearOf(m.group(3)), today);
      if (date == null) continue;
      claim(m.start, m.end);
      hits.add(_DateHit(date, m.start, m.end));
      matched.add(m.group(0)!.trim());
    }

    for (final m in _numericRe.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      final day = int.parse(m.group(1)!);
      final month = int.parse(m.group(3)!);
      if (month < 1 || month > 12) continue;
      // "Chapters 1-4" is not 1 April: a bare day.month or day-month needs a
      // two-digit day; the slash form ("2/10") is unambiguous enough.
      if (m.group(4) == null && m.group(2) != '/' && m.group(1)!.length < 2) continue;
      final date = _resolve(day, month, _yearOf(m.group(4)), today);
      if (date == null) continue;
      claim(m.start, m.end);
      hits.add(_DateHit(date, m.start, m.end));
      matched.add(m.group(0)!.trim());
    }

    for (final m in _relativeRe.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      final phrase = m.group(1)!.toLowerCase();
      DateTime? date;
      if (phrase == 'today' || phrase == 'tonight') {
        date = today;
      } else if (phrase == 'tomorrow') {
        date = today.add(const Duration(days: 1));
      } else if (phrase == 'day after tomorrow') {
        date = today.add(const Duration(days: 2));
      } else if (m.group(2) != null) {
        date = today.add(Duration(days: int.parse(m.group(2)!)));
      } else if (m.group(3) != null) {
        final weekday = _weekdayIndex(m.group(3)!);
        final ahead = (weekday - today.weekday + 7) % 7;
        // "this Friday" includes today; "next Monday" is always ahead.
        final days = phrase.startsWith('next') ? (ahead == 0 ? 7 : ahead) : ahead;
        date = today.add(Duration(days: days));
      }
      if (date == null) continue;
      claim(m.start, m.end);
      hits.add(_DateHit(date, m.start, m.end, relative: true));
      matched.add(m.group(0)!.trim());
    }

    hits.sort((a, b) => a.start.compareTo(b.start));

    // "on Saturday 26 Sep" — the weekday is a label for the date beside it,
    // not a second candidate.
    hits.removeWhere(
      (h) =>
          h.relative &&
          hits.any((o) => !o.relative && o.start >= h.end && o.start - h.end <= 3),
    );

    // Join "24 Nov to 2 Dec" into one range, and flag dates that follow a
    // due-cue so assignments anchor on the right one.
    final joined = <_DateHit>[];
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      if (i + 1 < hits.length && hit.rangeEnd == null) {
        final next = hits[i + 1];
        final between = text.substring(hit.end, next.start);
        if (_rangeJoinRe.hasMatch(between) && !next.date.isBefore(hit.date)) {
          joined.add(_DateHit(hit.date, hit.start, next.end, rangeEnd: next, relative: hit.relative, afterDueCue: _hasDueCue(text, hit.start)));
          i++;
          continue;
        }
      }
      joined.add(_DateHit(hit.date, hit.start, hit.end, rangeEnd: hit.rangeEnd, relative: hit.relative, afterDueCue: _hasDueCue(text, hit.start)));
    }
    return joined;
  }

  static bool _hasDueCue(String text, int before) {
    final window = text.substring((before - 24).clamp(0, text.length), before);
    return _dueCueRe.hasMatch(window);
  }

  static int _monthIndex(String name) {
    final n = name.toLowerCase();
    for (var i = 0; i < _months.length; i++) {
      if (_months[i].startsWith(n.substring(0, 3))) return i + 1;
    }
    return 0;
  }

  static int _weekdayIndex(String name) {
    final n = name.toLowerCase().substring(0, 3);
    for (var i = 0; i < _weekdays.length; i++) {
      if (_weekdays[i].startsWith(n)) return i + 1;
    }
    return 1;
  }

  static int? _yearOf(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final digits = raw.replaceAll("'", '');
    final n = int.tryParse(digits);
    if (n == null) return null;
    return digits.length == 2 ? 2000 + n : n;
  }

  /// Builds a date, filling a missing year per the eleven-month rule, and
  /// rejecting impossible days and years wildly off the notice.
  static DateTime? _resolve(int day, int month, int? year, DateTime today) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year != null) {
      if (year < today.year - 1 || year > today.year + 2) return null;
      final d = DateTime(year, month, day);
      return d.month == month ? d : null;
    }
    final thisYear = DateTime(today.year, month, day);
    if (thisYear.month != month) return null;
    if (!thisYear.isBefore(today)) return thisYear;
    final nextYear = DateTime(today.year + 1, month, day);
    final limit = DateTime(today.year, today.month + 11, today.day);
    return nextYear.isAfter(limit) ? thisYear : nextYear;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── title ───────────────────────────────────────────────────────────────

  static final _genericTitleRe = RegExp(
    r'^(new (notification|message|circular|notice)|notification|circular|notice|message|alert|update|reminder|dear parents?|campus ?care.*|school app)$',
    caseSensitive: false,
  );

  /// `Unit Test 2 — Science — 24 Nov` → `Science Unit Test 2`.
  static String cleanTitle({
    required String title,
    required String body,
    String? subject,
    NoticeKind kind = NoticeKind.unknown,
  }) {
    var base = title.trim();
    if (base.isEmpty || _genericTitleRe.hasMatch(base)) {
      base = body.trim().split(RegExp(r'[\n.!?]')).map((s) => s.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => '');
    }
    base = _stripDates(base);
    base = base
        .replaceAll(RegExp(r'\s*[—–|:•·]+\s*'), ' · ')
        .replaceAll(RegExp(r'\s*-\s+'), ' · ')
        .replaceAll(RegExp(r'(\s*·\s*)+'), ' · ')
        .replaceAll(RegExp(r'^\s*·\s*|\s*·\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (base.isEmpty) base = kind == NoticeKind.unknown ? 'School notice' : kind.label;
    if (base.length > 80) base = '${base.substring(0, 77).trimRight()}…';

    final subjectName = subject ?? _anySubjectWord('$title\n$body');
    if (subjectName != null && !base.toLowerCase().contains(subjectName.toLowerCase())) {
      final parts = base.split(' · ').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      final rest = parts.where((p) => _anySubjectWord(p) == null).join(' · ');
      base = rest.isEmpty ? subjectName : '$subjectName ${rest.split(' · ').first}';
    } else if (base.contains(' · ')) {
      // Put the subject first when the title lists it second.
      final parts = base.split(' · ').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      final subjectIdx = parts.indexWhere((p) => _anySubjectWord(p) != null && p.split(' ').length <= 2);
      if (subjectIdx > 0) {
        final s = parts.removeAt(subjectIdx);
        base = '$s ${parts.first}';
      } else {
        base = parts.first;
      }
    }
    return base.trim();
  }

  static String _stripDates(String text) {
    var out = text;
    for (final re in [_dayRangeRe, _dayMonthRe, _monthDayRe, _numericRe, _timeRe, _time24Re, _relativeRe]) {
      out = out.replaceAll(re, ' ');
    }
    out = out.replaceAll(RegExp(r'\b(on|at|from|dated?)\s*$', caseSensitive: false), '');
    return out;
  }

  static String _titleCase(String s) =>
      s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

class _DateHit {
  const _DateHit(
    this.date,
    this.start,
    this.end, {
    this.rangeEnd,
    this.relative = false,
    this.afterDueCue = false,
  });

  final DateTime date;
  final int start;
  final int end;
  final _DateHit? rangeEnd;
  final bool relative;
  final bool afterDueCue;
}
