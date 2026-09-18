/// Every `responseSchema` in one place (prompt 02 §H), in the OpenAPI
/// subset Gemini accepts. A schema change here is a diff, not a hunt.
abstract final class GeminiSchemas {
  static Map<String, Object?> _obj(
    Map<String, Object?> properties, {
    List<String>? required,
    bool nullable = false,
  }) => {
    'type': 'OBJECT',
    'properties': properties,
    'required': ?required,
    if (nullable) 'nullable': true,
    'propertyOrdering': properties.keys.toList(),
  };

  static Map<String, Object?> _arr(Map<String, Object?> items) => {
    'type': 'ARRAY',
    'items': items,
  };

  static const Map<String, Object?> _str = {'type': 'STRING'};
  static const Map<String, Object?> _strN = {'type': 'STRING', 'nullable': true};
  static const Map<String, Object?> _int = {'type': 'INTEGER'};
  static const Map<String, Object?> _intN = {'type': 'INTEGER', 'nullable': true};
  static const Map<String, Object?> _num = {'type': 'NUMBER'};
  static const Map<String, Object?> _numN = {'type': 'NUMBER', 'nullable': true};
  static const Map<String, Object?> _bool = {'type': 'BOOLEAN'};
  static final Map<String, Object?> _strings = _arr(_str);

  static Map<String, Object?> _enum(List<String> values) => {
    'type': 'STRING',
    'enum': values,
  };

  // ── §C practice paper ───────────────────────────────────────────────────

  static final Map<String, Object?> paperQuestion = _obj({
    'number': _int,
    'type': _enum(['mcq', 'short', 'long', 'fill_in', 'match', 'true_false']),
    'text': _str,
    'options': _strings,
    'answer': _str,
    'explanation': _str,
    'marks': _int,
    'chapter': _str,
    'difficulty': _enum(['easy', 'medium', 'hard']),
    'sourceRef': _str,
  }, required: ['number', 'type', 'text', 'answer', 'marks']);

  static final Map<String, Object?> paper = _obj({
    'title': _str,
    'subject': _str,
    'grade': _str,
    'durationMinutes': _int,
    'totalMarks': _int,
    'instructions': _strings,
    'sections': _arr(
      _obj({
        'name': _str,
        'instructions': _str,
        'questions': _arr(paperQuestion),
      }, required: ['name', 'questions']),
    ),
  }, required: ['title', 'subject', 'sections']);

  /// A single replacement question — the per-question regenerate call.
  static final Map<String, Object?> singleQuestion = _obj({
    'question': paperQuestion,
  }, required: ['question']);

  // ── §D scanned paper ────────────────────────────────────────────────────

  static final Map<String, Object?> scannedPaper = _obj({
    'detected': _obj({
      'subject': _str,
      'examType': _str,
      'date': _strN,
      'grade': _str,
      'totalMarks': _numN,
      'durationMinutes': _intN,
      'confidence': _num,
    }),
    'sections': _arr(
      _obj({
        'name': _str,
        'instructions': _str,
        'questions': _arr(
          _obj({
            'number': _str,
            'text': _str,
            'type': _enum(['mcq', 'short', 'long', 'fill_in', 'match', 'true_false', 'other']),
            'marks': _numN,
            'options': _strings,
            'pageIndex': _int,
            'confidence': _num,
            'needsReview': _bool,
            'studentAnswer': _strN,
          }, required: ['number', 'text', 'pageIndex', 'confidence']),
        ),
      }, required: ['name', 'questions']),
    ),
    'unreadableRegions': _arr(
      _obj({'pageIndex': _int, 'note': _str}, required: ['pageIndex', 'note']),
    ),
  }, required: ['detected', 'sections']);

  static final Map<String, Object?> answerKey = _obj({
    'answers': _arr(
      _obj({
        'number': _str,
        'answer': _str,
        'workedSolution': _strings,
        'markingScheme': _arr(
          _obj({'points': _num, 'for': _str}, required: ['points', 'for']),
        ),
        'commonMistakes': _strings,
        'confidence': _num,
      }, required: ['number', 'answer']),
    ),
  }, required: ['answers']);

  static final Map<String, Object?> gradedPaper = _obj({
    'questions': _arr(
      _obj({
        'number': _str,
        'awarded': _num,
        'outOf': _num,
        'verdict': _enum(['correct', 'partial', 'incorrect', 'blank']),
        'reason': _str,
        'topic': _str,
      }, required: ['number', 'awarded', 'outOf', 'verdict']),
    ),
  }, required: ['questions']);

  // ── §E report card ──────────────────────────────────────────────────────

  static final Map<String, Object?> reportCard = _obj({
    'examLabel': _str,
    'date': _strN,
    'confidence': _num,
    'attendancePercent': _numN,
    'teacherRemarks': _str,
    'scores': _arr(
      _obj({
        'subject': _str,
        'marks': _numN,
        'maxMarks': _numN,
        'grade': _strN,
        'classRank': _intN,
        'remarks': _str,
        'absent': _bool,
        'confidence': _num,
      }, required: ['subject', 'confidence']),
    ),
  }, required: ['examLabel', 'scores']);

  // ── exam timetable (date sheet) ─────────────────────────────────────────

  static final Map<String, Object?> timetable = _obj({
    'examLabel': _str,
    'confidence': _num,
    'entries': _arr(
      _obj({
        'subject': _str,
        'date': _strN,
        'startTime': _strN,
        'endTime': _strN,
        'notes': _str,
        'confidence': _num,
      }, required: ['subject', 'confidence']),
    ),
    'unreadable': _str,
  }, required: ['examLabel', 'entries', 'confidence']);

  // ── prompt 03 §C stage 2: notice classification ─────────────────────────

  /// One reply covers a batch of up to ten notices, matched back by `id`.
  /// Dates are ISO strings the Dart side validates before trusting.
  static final Map<String, Object?> noticeExtraction = _obj({
    'notices': _arr(
      _obj({
        'id': _str,
        'kind': _enum(['exam', 'assignment', 'activity', 'holiday', 'fee', 'meeting', 'announcement', 'unknown']),
        'title': _str,
        'subject': _strN,
        'eventDate': _strN,
        'eventTime': _strN,
        'endDate': _strN,
        'dueDate': _strN,
        'confidence': _num,
        'reasoning': _str,
      }, required: ['id', 'kind', 'title', 'confidence', 'reasoning']),
    ),
  }, required: ['notices']);

  // ── §F focus plan ───────────────────────────────────────────────────────

  static final Map<String, Object?> focusPlan = _obj({
    'summary': _str,
    'subjects': _arr(
      _obj({
        'subject': _str,
        'why': _str,
        'focusChapters': _strings,
        'plan': _arr(
          _obj({'week': _int, 'actions': _strings}, required: ['week', 'actions']),
        ),
        'practiceSuggestion': _obj({
          'type': _enum(['practice_paper', 'quiz', 'worksheet', 'flashcards', 'revision_notes']),
          'chapters': _strings,
          'questionCount': _int,
        }, nullable: true),
      }, required: ['subject', 'why', 'plan']),
    ),
  }, required: ['summary', 'subjects']);
}
