/// Everything the model returns, as plain Dart — no Firebase, no Flutter, no
/// HTTP. Each class parses *defensively* from the JSON Gemini produced: a
/// missing field falls back, a malformed question is dropped and counted
/// rather than taking the whole paper down with it.
///
/// Persistence lives in `mappers.dart` (`Map$.generatedToMap` / `generatedFrom`)
/// exactly as it does for the other models.
library;

// ── JSON helpers ──────────────────────────────────────────────────────────

/// Lenient readers shared by every `fromJson` below. Public only so the
/// service layer can reuse them when it inspects a raw reply.
abstract final class J {
  static String str(Object? v, [String fallback = '']) =>
      v is String ? v : (v == null ? fallback : v.toString());

  static String? strOrNull(Object? v) {
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    return s.trim().isEmpty ? null : s;
  }

  static int integer(Object? v, [int fallback = 0]) => switch (v) {
    int i => i,
    double d => d.isFinite ? d.round() : fallback,
    String s => int.tryParse(s.trim()) ?? double.tryParse(s.trim())?.round() ?? fallback,
    _ => fallback,
  };

  static int? intOrNull(Object? v) {
    if (v == null) return null;
    final parsed = integer(v, -1 << 30);
    return parsed == -1 << 30 ? null : parsed;
  }

  static double? number(Object? v) => switch (v) {
    double d => d.isFinite ? d : null,
    int i => i.toDouble(),
    String s => double.tryParse(s.trim()),
    _ => null,
  };

  static bool flag(Object? v, [bool fallback = false]) => switch (v) {
    bool b => b,
    String s => s.toLowerCase() == 'true',
    _ => fallback,
  };

  static List<String> strings(Object? v) {
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e != null && e.toString().trim().isNotEmpty) e.toString(),
    ];
  }

  static List<Map<String, Object?>> maps(Object? v) {
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map) Map<String, Object?>.from(e),
    ];
  }

  static Map<String, Object?> map(Object? v) =>
      v is Map ? Map<String, Object?>.from(v) : const {};

  /// 0–1, clamped; missing reads as fully confident so a schema that omits
  /// confidence does not flag every row for review.
  static double confidence(Object? v, [double fallback = 1]) {
    final n = number(v);
    if (n == null) return fallback;
    return n.clamp(0, 1).toDouble();
  }
}

// ── Shared enums ──────────────────────────────────────────────────────────

/// Which kind of structured artefact a `generated` document holds.
enum GeneratedKind {
  paper('paper', 'Practice paper'),
  scannedPaper('scannedPaper', 'Scanned paper'),
  answerKey('answerKey', 'Answer key'),
  gradedPaper('gradedPaper', 'Graded paper');

  const GeneratedKind(this.wire, this.label);
  final String wire;
  final String label;

  static GeneratedKind fromWire(String? value) => switch (value) {
    'scannedPaper' => GeneratedKind.scannedPaper,
    'answerKey' => GeneratedKind.answerKey,
    'gradedPaper' => GeneratedKind.gradedPaper,
    _ => GeneratedKind.paper,
  };
}

enum QuestionType {
  mcq('mcq', 'MCQ'),
  short('short', 'Short answer'),
  long('long', 'Long answer'),
  fillIn('fill_in', 'Fill in the blank'),
  match('match', 'Match the following'),
  trueFalse('true_false', 'True / false');

  const QuestionType(this.wire, this.label);
  final String wire;
  final String label;

  static QuestionType fromWire(String? value) {
    final v = (value ?? '').toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return switch (v) {
      'short' || 'short_answer' => QuestionType.short,
      'long' || 'long_answer' => QuestionType.long,
      'fill_in' || 'fillin' || 'fill_in_the_blank' || 'fill' => QuestionType.fillIn,
      'match' || 'matching' => QuestionType.match,
      'true_false' || 'truefalse' || 'tf' => QuestionType.trueFalse,
      _ => QuestionType.mcq,
    };
  }
}

enum PaperOutput {
  practicePaper('practice_paper', 'Practice paper'),
  quiz('quiz', 'Quiz (MCQ)'),
  worksheet('worksheet', 'Worksheet'),
  flashcards('flashcards', 'Flashcards'),
  revisionNotes('revision_notes', 'Revision notes');

  const PaperOutput(this.wire, this.label);
  final String wire;
  final String label;

  static PaperOutput fromWire(String? value) => switch (value) {
    'quiz' => PaperOutput.quiz,
    'worksheet' => PaperOutput.worksheet,
    'flashcards' => PaperOutput.flashcards,
    'revision_notes' => PaperOutput.revisionNotes,
    _ => PaperOutput.practicePaper,
  };
}

enum PaperDifficulty {
  sameAsSource('same', 'Same as source'),
  easier('easier', 'Easier'),
  harder('harder', 'Harder'),
  mixed('mixed', 'Mixed');

  const PaperDifficulty(this.wire, this.label);
  final String wire;
  final String label;

  static PaperDifficulty fromWire(String? value) => switch (value) {
    'easier' => PaperDifficulty.easier,
    'harder' => PaperDifficulty.harder,
    'mixed' => PaperDifficulty.mixed,
    _ => PaperDifficulty.sameAsSource,
  };
}

enum PaperLanguage {
  english('English'),
  hindi('Hindi'),
  gujarati('Gujarati');

  const PaperLanguage(this.label);
  final String label;

  static PaperLanguage fromLabel(String? value) => switch (value) {
    'Hindi' => PaperLanguage.hindi,
    'Gujarati' => PaperLanguage.gujarati,
    _ => PaperLanguage.english,
  };
}

// ── C. Generated practice material ────────────────────────────────────────

/// What the parent asked for. Kept so a failed generation can be retried
/// with one tap and so a saved paper remembers how it was made.
class PaperConfig {
  const PaperConfig({
    required this.subject,
    required this.chapters,
    required this.output,
    required this.mix,
    this.difficulty = PaperDifficulty.sameAsSource,
    this.totalMarks,
    this.durationMinutes,
    this.language = PaperLanguage.english,
    this.includeAnswerKey = true,
    this.sourceRecordIds = const [],
  });

  final String subject;
  final List<String> chapters;
  final PaperOutput output;

  /// Question count per type. Zero entries are omitted from the prompt.
  final Map<QuestionType, int> mix;
  final PaperDifficulty difficulty;
  final int? totalMarks;
  final int? durationMinutes;
  final PaperLanguage language;
  final bool includeAnswerKey;
  final List<String> sourceRecordIds;

  int get questionCount => mix.values.fold(0, (a, b) => a + b);

  /// Default marks: 1 per MCQ/true-false/fill-in, 2 per short/match, 5 per
  /// long — the weights an Indian primary-school paper usually uses.
  int get derivedMarks => mix.entries.fold(0, (sum, e) {
    final weight = switch (e.key) {
      QuestionType.mcq || QuestionType.trueFalse || QuestionType.fillIn => 1,
      QuestionType.short || QuestionType.match => 2,
      QuestionType.long => 5,
    };
    return sum + weight * e.value;
  });

  /// Default duration: roughly 1.5 minutes per mark, rounded to 5.
  int get derivedDuration {
    final raw = ((totalMarks ?? derivedMarks) * 1.5).round();
    return raw < 10 ? 10 : (raw / 5).ceil() * 5;
  }

  PaperConfig copyWith({
    String? subject,
    List<String>? chapters,
    PaperOutput? output,
    Map<QuestionType, int>? mix,
    PaperDifficulty? difficulty,
    int? totalMarks,
    int? durationMinutes,
    PaperLanguage? language,
    bool? includeAnswerKey,
    List<String>? sourceRecordIds,
  }) => PaperConfig(
    subject: subject ?? this.subject,
    chapters: chapters ?? this.chapters,
    output: output ?? this.output,
    mix: mix ?? this.mix,
    difficulty: difficulty ?? this.difficulty,
    totalMarks: totalMarks ?? this.totalMarks,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    language: language ?? this.language,
    includeAnswerKey: includeAnswerKey ?? this.includeAnswerKey,
    sourceRecordIds: sourceRecordIds ?? this.sourceRecordIds,
  );

  Map<String, Object?> toJson() => {
    'subject': subject,
    'chapters': chapters,
    'output': output.wire,
    'mix': {for (final e in mix.entries) e.key.wire: e.value},
    'difficulty': difficulty.wire,
    'totalMarks': totalMarks,
    'durationMinutes': durationMinutes,
    'language': language.label,
    'includeAnswerKey': includeAnswerKey,
    'sourceRecordIds': sourceRecordIds,
  };

  factory PaperConfig.fromJson(Map<String, Object?> m) => PaperConfig(
    subject: J.str(m['subject']),
    chapters: J.strings(m['chapters']),
    output: PaperOutput.fromWire(m['output'] as String?),
    mix: {
      for (final e in J.map(m['mix']).entries)
        QuestionType.fromWire(e.key): J.integer(e.value),
    },
    difficulty: PaperDifficulty.fromWire(m['difficulty'] as String?),
    totalMarks: J.intOrNull(m['totalMarks']),
    durationMinutes: J.intOrNull(m['durationMinutes']),
    language: PaperLanguage.fromLabel(m['language'] as String?),
    includeAnswerKey: J.flag(m['includeAnswerKey'], true),
    sourceRecordIds: J.strings(m['sourceRecordIds']),
  );
}

class PaperQuestion {
  const PaperQuestion({
    required this.number,
    required this.type,
    required this.text,
    this.options = const [],
    this.answer = '',
    this.explanation = '',
    this.marks = 1,
    this.chapter = '',
    this.difficulty = 'medium',
    this.sourceRef = 'derived',
    this.flagged = false,
  });

  final int number;
  final QuestionType type;
  final String text;
  final List<String> options;
  final String answer;
  final String explanation;
  final int marks;
  final String chapter;
  final String difficulty;

  /// Attachment id the question was drawn from, or `derived`.
  final String sourceRef;

  /// Parent-side: marked for a second look in the preview. Never sent to
  /// the model and not persisted.
  final bool flagged;

  PaperQuestion copyWith({
    int? number,
    QuestionType? type,
    String? text,
    List<String>? options,
    String? answer,
    String? explanation,
    int? marks,
    String? chapter,
    String? difficulty,
    String? sourceRef,
    bool? flagged,
  }) => PaperQuestion(
    number: number ?? this.number,
    type: type ?? this.type,
    text: text ?? this.text,
    options: options ?? this.options,
    answer: answer ?? this.answer,
    explanation: explanation ?? this.explanation,
    marks: marks ?? this.marks,
    chapter: chapter ?? this.chapter,
    difficulty: difficulty ?? this.difficulty,
    sourceRef: sourceRef ?? this.sourceRef,
    flagged: flagged ?? this.flagged,
  );

  Map<String, Object?> toJson() => {
    'number': number,
    'type': type.wire,
    'text': text,
    'options': options,
    'answer': answer,
    'explanation': explanation,
    'marks': marks,
    'chapter': chapter,
    'difficulty': difficulty,
    'sourceRef': sourceRef,
  };

  /// Null when the question has no text — the one thing that makes it
  /// unusable. Everything else has a sensible default.
  static PaperQuestion? tryParse(Map<String, Object?> m, {int fallbackNumber = 0}) {
    final text = J.str(m['text']).trim();
    if (text.isEmpty) return null;
    final marks = J.integer(m['marks'], 1);
    return PaperQuestion(
      number: J.integer(m['number'], fallbackNumber),
      type: QuestionType.fromWire(m['type'] as String?),
      text: text,
      options: J.strings(m['options']),
      answer: J.str(m['answer']),
      explanation: J.str(m['explanation']),
      marks: marks < 0 ? 0 : marks,
      chapter: J.str(m['chapter']),
      difficulty: J.str(m['difficulty'], 'medium'),
      sourceRef: J.str(m['sourceRef'], 'derived'),
    );
  }
}

class PaperSection {
  const PaperSection({
    required this.name,
    this.instructions = '',
    this.questions = const [],
    this.droppedQuestions = 0,
  });

  final String name;
  final String instructions;
  final List<PaperQuestion> questions;

  /// Questions the model returned that could not be read. Shown as a
  /// "missing" marker in the preview rather than silently vanishing.
  final int droppedQuestions;

  int get marks => questions.fold(0, (sum, q) => sum + q.marks);

  PaperSection copyWith({
    String? name,
    String? instructions,
    List<PaperQuestion>? questions,
    int? droppedQuestions,
  }) => PaperSection(
    name: name ?? this.name,
    instructions: instructions ?? this.instructions,
    questions: questions ?? this.questions,
    droppedQuestions: droppedQuestions ?? this.droppedQuestions,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'instructions': instructions,
    'questions': [for (final q in questions) q.toJson()],
  };

  factory PaperSection.fromJson(Map<String, Object?> m, {int startNumber = 1}) {
    final raw = J.maps(m['questions']);
    final questions = <PaperQuestion>[];
    var dropped = 0;
    for (var i = 0; i < raw.length; i++) {
      final q = PaperQuestion.tryParse(raw[i], fallbackNumber: startNumber + i);
      if (q == null) {
        dropped++;
      } else {
        questions.add(q);
      }
    }
    return PaperSection(
      name: J.str(m['name'], 'Section'),
      instructions: J.str(m['instructions']),
      questions: questions,
      droppedQuestions: dropped,
    );
  }
}

/// A whole generated paper, quiz, worksheet, flashcard set or notes.
class GeneratedPaper {
  const GeneratedPaper({
    required this.title,
    required this.subject,
    required this.grade,
    this.durationMinutes = 0,
    this.totalMarks = 0,
    this.instructions = const [],
    this.sections = const [],
    this.language = PaperLanguage.english,
    this.model = '',
    this.generatedAt,
  });

  final String title;
  final String subject;
  final String grade;
  final int durationMinutes;
  final int totalMarks;
  final List<String> instructions;
  final List<PaperSection> sections;
  final PaperLanguage language;

  /// Which model produced it — shown on the paper so a parent comparing two
  /// generations knows which is which.
  final String model;
  final DateTime? generatedAt;

  List<PaperQuestion> get questions => [
    for (final s in sections) ...s.questions,
  ];
  int get questionCount => questions.length;
  int get droppedQuestions =>
      sections.fold(0, (sum, s) => sum + s.droppedQuestions);
  bool get isPartial => droppedQuestions > 0 || sections.isEmpty;

  /// Sum of the questions' marks — the paper's own `totalMarks` is what the
  /// model claimed and can drift after edits.
  int get computedMarks => sections.fold(0, (sum, s) => sum + s.marks);

  GeneratedPaper copyWith({
    String? title,
    String? subject,
    String? grade,
    int? durationMinutes,
    int? totalMarks,
    List<String>? instructions,
    List<PaperSection>? sections,
    PaperLanguage? language,
    String? model,
    DateTime? generatedAt,
  }) => GeneratedPaper(
    title: title ?? this.title,
    subject: subject ?? this.subject,
    grade: grade ?? this.grade,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    totalMarks: totalMarks ?? this.totalMarks,
    instructions: instructions ?? this.instructions,
    sections: sections ?? this.sections,
    language: language ?? this.language,
    model: model ?? this.model,
    generatedAt: generatedAt ?? this.generatedAt,
  );

  /// Replaces one question in place, matched by section index and number.
  GeneratedPaper replaceQuestion(
    int sectionIndex,
    int questionIndex,
    PaperQuestion? replacement,
  ) {
    final sections = [...this.sections];
    if (sectionIndex < 0 || sectionIndex >= sections.length) return this;
    final questions = [...sections[sectionIndex].questions];
    if (questionIndex < 0 || questionIndex >= questions.length) return this;
    if (replacement == null) {
      questions.removeAt(questionIndex);
    } else {
      questions[questionIndex] = replacement;
    }
    sections[sectionIndex] = sections[sectionIndex].copyWith(
      questions: questions,
    );
    return copyWith(sections: sections);
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'subject': subject,
    'grade': grade,
    'durationMinutes': durationMinutes,
    'totalMarks': totalMarks,
    'instructions': instructions,
    'sections': [for (final s in sections) s.toJson()],
    'language': language.label,
    'model': model,
    'generatedAt': generatedAt?.toIso8601String(),
  };

  factory GeneratedPaper.fromJson(Map<String, Object?> m) {
    final sections = <PaperSection>[];
    var next = 1;
    for (final raw in J.maps(m['sections'])) {
      final s = PaperSection.fromJson(raw, startNumber: next);
      next += s.questions.length + s.droppedQuestions;
      sections.add(s);
    }
    final paper = GeneratedPaper(
      title: J.str(m['title'], 'Practice paper'),
      subject: J.str(m['subject']),
      grade: J.str(m['grade']),
      durationMinutes: J.integer(m['durationMinutes']),
      totalMarks: J.integer(m['totalMarks']),
      instructions: J.strings(m['instructions']),
      sections: sections,
      language: PaperLanguage.fromLabel(m['language'] as String?),
      model: J.str(m['model']),
      generatedAt: DateTime.tryParse(J.str(m['generatedAt'])),
    );
    // A model that forgot totals gets the arithmetic done for it.
    return paper.totalMarks == 0
        ? paper.copyWith(totalMarks: paper.computedMarks)
        : paper;
  }
}

// ── D. Scanned exam paper ─────────────────────────────────────────────────

class DetectedExam {
  const DetectedExam({
    this.subject = '',
    this.examType = '',
    this.date,
    this.grade = '',
    this.totalMarks,
    this.durationMinutes,
    this.confidence = 0,
  });

  final String subject;
  final String examType;
  final DateTime? date;
  final String grade;
  final double? totalMarks;
  final int? durationMinutes;
  final double confidence;

  Map<String, Object?> toJson() => {
    'subject': subject,
    'examType': examType,
    'date': date?.toIso8601String(),
    'grade': grade,
    'totalMarks': totalMarks,
    'durationMinutes': durationMinutes,
    'confidence': confidence,
  };

  factory DetectedExam.fromJson(Map<String, Object?> m) => DetectedExam(
    subject: J.str(m['subject']),
    examType: J.str(m['examType']),
    date: DateTime.tryParse(J.str(m['date'])),
    grade: J.str(m['grade']),
    totalMarks: J.number(m['totalMarks']),
    durationMinutes: J.intOrNull(m['durationMinutes']),
    confidence: J.confidence(m['confidence'], 0),
  );
}

class ScannedQuestion {
  const ScannedQuestion({
    required this.number,
    required this.text,
    this.type = 'short',
    this.marks,
    this.options = const [],
    this.pageIndex = 0,
    this.confidence = 1,
    this.needsReview = false,
    this.studentAnswer,
  });

  /// Kept as text — `1(a)`, `Q.3`, `ii` — because papers number things
  /// however they like.
  final String number;
  final String text;
  final String type;
  final double? marks;
  final List<String> options;
  final int pageIndex;
  final double confidence;
  final bool needsReview;

  /// The child's handwritten answer, when the pages were a completed paper.
  final String? studentAnswer;

  /// Below this the review screen highlights the row and sorts it up.
  static const double reviewThreshold = 0.75;

  bool get wantsReview => needsReview || confidence < reviewThreshold;

  ScannedQuestion copyWith({
    String? number,
    String? text,
    String? type,
    double? marks,
    List<String>? options,
    int? pageIndex,
    double? confidence,
    bool? needsReview,
    String? studentAnswer,
    bool clearMarks = false,
  }) => ScannedQuestion(
    number: number ?? this.number,
    text: text ?? this.text,
    type: type ?? this.type,
    marks: clearMarks ? null : (marks ?? this.marks),
    options: options ?? this.options,
    pageIndex: pageIndex ?? this.pageIndex,
    confidence: confidence ?? this.confidence,
    needsReview: needsReview ?? this.needsReview,
    studentAnswer: studentAnswer ?? this.studentAnswer,
  );

  Map<String, Object?> toJson() => {
    'number': number,
    'text': text,
    'type': type,
    'marks': marks,
    'options': options,
    'pageIndex': pageIndex,
    'confidence': confidence,
    'needsReview': needsReview,
    'studentAnswer': studentAnswer,
  };

  static ScannedQuestion? tryParse(Map<String, Object?> m, {int index = 0}) {
    final text = J.str(m['text']).trim();
    if (text.isEmpty) return null;
    return ScannedQuestion(
      number: J.str(m['number'], '${index + 1}'),
      text: text,
      type: J.str(m['type'], 'short'),
      marks: J.number(m['marks']),
      options: J.strings(m['options']),
      pageIndex: J.integer(m['pageIndex']),
      confidence: J.confidence(m['confidence']),
      needsReview: J.flag(m['needsReview']),
      studentAnswer: J.strOrNull(m['studentAnswer']),
    );
  }
}

class ScannedSection {
  const ScannedSection({
    required this.name,
    this.instructions = '',
    this.questions = const [],
  });

  final String name;
  final String instructions;
  final List<ScannedQuestion> questions;

  ScannedSection copyWith({
    String? name,
    String? instructions,
    List<ScannedQuestion>? questions,
  }) => ScannedSection(
    name: name ?? this.name,
    instructions: instructions ?? this.instructions,
    questions: questions ?? this.questions,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'instructions': instructions,
    'questions': [for (final q in questions) q.toJson()],
  };

  factory ScannedSection.fromJson(Map<String, Object?> m) {
    final raw = J.maps(m['questions']);
    return ScannedSection(
      name: J.str(m['name'], 'Section'),
      instructions: J.str(m['instructions']),
      questions: [
        for (var i = 0; i < raw.length; i++)
          ?ScannedQuestion.tryParse(raw[i], index: i),
      ],
    );
  }
}

class UnreadableRegion {
  const UnreadableRegion({required this.pageIndex, required this.note});
  final int pageIndex;
  final String note;

  Map<String, Object?> toJson() => {'pageIndex': pageIndex, 'note': note};

  factory UnreadableRegion.fromJson(Map<String, Object?> m) =>
      UnreadableRegion(pageIndex: J.integer(m['pageIndex']), note: J.str(m['note']));
}

class ScannedPaper {
  const ScannedPaper({
    this.detected = const DetectedExam(),
    this.sections = const [],
    this.unreadableRegions = const [],
    this.pageCount = 0,
    this.hasStudentAnswers = false,
    this.model = '',
  });

  final DetectedExam detected;
  final List<ScannedSection> sections;
  final List<UnreadableRegion> unreadableRegions;
  final int pageCount;

  /// True when the parent said the pages carry the child's answers — the
  /// prerequisite for grading.
  final bool hasStudentAnswers;
  final String model;

  List<ScannedQuestion> get questions => [
    for (final s in sections) ...s.questions,
  ];
  int get reviewCount => questions.where((q) => q.wantsReview).length;
  double get totalMarks =>
      questions.fold(0.0, (sum, q) => sum + (q.marks ?? 0));

  ScannedPaper copyWith({
    DetectedExam? detected,
    List<ScannedSection>? sections,
    List<UnreadableRegion>? unreadableRegions,
    int? pageCount,
    bool? hasStudentAnswers,
    String? model,
  }) => ScannedPaper(
    detected: detected ?? this.detected,
    sections: sections ?? this.sections,
    unreadableRegions: unreadableRegions ?? this.unreadableRegions,
    pageCount: pageCount ?? this.pageCount,
    hasStudentAnswers: hasStudentAnswers ?? this.hasStudentAnswers,
    model: model ?? this.model,
  );

  ScannedPaper replaceQuestion(int sectionIndex, int questionIndex, ScannedQuestion? q) {
    final sections = [...this.sections];
    if (sectionIndex < 0 || sectionIndex >= sections.length) return this;
    final questions = [...sections[sectionIndex].questions];
    if (questionIndex < 0 || questionIndex >= questions.length) return this;
    if (q == null) {
      questions.removeAt(questionIndex);
    } else {
      questions[questionIndex] = q;
    }
    sections[sectionIndex] = sections[sectionIndex].copyWith(questions: questions);
    return copyWith(sections: sections);
  }

  Map<String, Object?> toJson() => {
    'detected': detected.toJson(),
    'sections': [for (final s in sections) s.toJson()],
    'unreadableRegions': [for (final r in unreadableRegions) r.toJson()],
    'pageCount': pageCount,
    'hasStudentAnswers': hasStudentAnswers,
    'model': model,
  };

  factory ScannedPaper.fromJson(Map<String, Object?> m) => ScannedPaper(
    detected: DetectedExam.fromJson(J.map(m['detected'])),
    sections: [for (final s in J.maps(m['sections'])) ScannedSection.fromJson(s)],
    unreadableRegions: [
      for (final r in J.maps(m['unreadableRegions'])) UnreadableRegion.fromJson(r),
    ],
    pageCount: J.integer(m['pageCount']),
    hasStudentAnswers: J.flag(m['hasStudentAnswers']),
    model: J.str(m['model']),
  );
}

// ── D. Answer key ─────────────────────────────────────────────────────────

class MarkingPoint {
  const MarkingPoint({required this.points, required this.reason});
  final double points;
  final String reason;

  Map<String, Object?> toJson() => {'points': points, 'for': reason};

  factory MarkingPoint.fromJson(Map<String, Object?> m) =>
      MarkingPoint(points: J.number(m['points']) ?? 0, reason: J.str(m['for']));
}

class AnswerKeyEntry {
  const AnswerKeyEntry({
    required this.number,
    required this.answer,
    this.workedSolution = const [],
    this.markingScheme = const [],
    this.commonMistakes = const [],
    this.confidence = 1,
  });

  final String number;
  final String answer;
  final List<String> workedSolution;
  final List<MarkingPoint> markingScheme;
  final List<String> commonMistakes;
  final double confidence;

  Map<String, Object?> toJson() => {
    'number': number,
    'answer': answer,
    'workedSolution': workedSolution,
    'markingScheme': [for (final p in markingScheme) p.toJson()],
    'commonMistakes': commonMistakes,
    'confidence': confidence,
  };

  static AnswerKeyEntry? tryParse(Map<String, Object?> m) {
    final number = J.str(m['number']).trim();
    if (number.isEmpty) return null;
    return AnswerKeyEntry(
      number: number,
      answer: J.str(m['answer']),
      workedSolution: J.strings(m['workedSolution']),
      markingScheme: [
        for (final p in J.maps(m['markingScheme'])) MarkingPoint.fromJson(p),
      ],
      commonMistakes: J.strings(m['commonMistakes']),
      confidence: J.confidence(m['confidence']),
    );
  }
}

class AnswerKey {
  const AnswerKey({this.answers = const [], this.model = ''});

  final List<AnswerKeyEntry> answers;
  final String model;

  AnswerKeyEntry? forNumber(String number) =>
      answers.where((a) => a.number == number).firstOrNull;

  Map<String, Object?> toJson() => {
    'answers': [for (final a in answers) a.toJson()],
    'model': model,
  };

  factory AnswerKey.fromJson(Map<String, Object?> m) => AnswerKey(
    answers: [for (final a in J.maps(m['answers'])) ?AnswerKeyEntry.tryParse(a)],
    model: J.str(m['model']),
  );
}

// ── D. Graded paper ───────────────────────────────────────────────────────

enum Verdict {
  correct('correct', 'Correct'),
  partial('partial', 'Partly correct'),
  incorrect('incorrect', 'Incorrect'),
  blank('blank', 'Not attempted');

  const Verdict(this.wire, this.label);
  final String wire;
  final String label;

  static Verdict fromWire(String? value) => switch (value) {
    'correct' => Verdict.correct,
    'partial' => Verdict.partial,
    'blank' => Verdict.blank,
    _ => Verdict.incorrect,
  };
}

class GradedQuestion {
  const GradedQuestion({
    required this.number,
    required this.awarded,
    required this.outOf,
    required this.verdict,
    this.reason = '',
    this.topic = '',
  });

  final String number;
  final double awarded;
  final double outOf;
  final Verdict verdict;
  final String reason;
  final String topic;

  GradedQuestion copyWith({double? awarded, Verdict? verdict, String? reason}) =>
      GradedQuestion(
        number: number,
        awarded: awarded ?? this.awarded,
        outOf: outOf,
        verdict: verdict ?? this.verdict,
        reason: reason ?? this.reason,
        topic: topic,
      );

  Map<String, Object?> toJson() => {
    'number': number,
    'awarded': awarded,
    'outOf': outOf,
    'verdict': verdict.wire,
    'reason': reason,
    'topic': topic,
  };

  static GradedQuestion? tryParse(Map<String, Object?> m) {
    final number = J.str(m['number']).trim();
    final outOf = J.number(m['outOf']);
    if (number.isEmpty || outOf == null || outOf <= 0) return null;
    final awarded = (J.number(m['awarded']) ?? 0).clamp(0, outOf).toDouble();
    return GradedQuestion(
      number: number,
      awarded: awarded,
      outOf: outOf,
      verdict: Verdict.fromWire(m['verdict'] as String?),
      reason: J.str(m['reason']),
      topic: J.str(m['topic']),
    );
  }
}

class GradedPaper {
  const GradedPaper({this.questions = const [], this.model = ''});

  final List<GradedQuestion> questions;
  final String model;

  double get awarded => questions.fold(0.0, (s, q) => s + q.awarded);
  double get outOf => questions.fold(0.0, (s, q) => s + q.outOf);
  double? get percent => outOf == 0 ? null : awarded / outOf * 100;

  GradedPaper replace(int index, GradedQuestion q) {
    if (index < 0 || index >= questions.length) return this;
    final list = [...questions];
    list[index] = q;
    return GradedPaper(questions: list, model: model);
  }

  Map<String, Object?> toJson() => {
    'questions': [for (final q in questions) q.toJson()],
    'model': model,
  };

  factory GradedPaper.fromJson(Map<String, Object?> m) => GradedPaper(
    questions: [for (final q in J.maps(m['questions'])) ?GradedQuestion.tryParse(q)],
    model: J.str(m['model']),
  );
}

// ── E. Report card ────────────────────────────────────────────────────────

class ExtractedScore {
  const ExtractedScore({
    required this.subject,
    this.marks,
    this.maxMarks,
    this.grade,
    this.classRank,
    this.remarks = '',
    this.absent = false,
    this.confidence = 1,
  });

  final String subject;
  final double? marks;
  final double? maxMarks;
  final String? grade;
  final int? classRank;
  final String remarks;
  final bool absent;
  final double confidence;

  /// The Dart-side sanity check the prompt requires: a row whose numbers do
  /// not add up is flagged, never dropped.
  bool get marksValid {
    if (marks == null && maxMarks == null) return true;
    if (marks == null || maxMarks == null) return false;
    return marks! >= 0 && maxMarks! > 0 && marks! <= maxMarks!;
  }

  bool get wantsReview =>
      !marksValid || confidence < ScannedQuestion.reviewThreshold;

  Map<String, Object?> toJson() => {
    'subject': subject,
    'marks': marks,
    'maxMarks': maxMarks,
    'grade': grade,
    'classRank': classRank,
    'remarks': remarks,
    'absent': absent,
    'confidence': confidence,
  };

  static ExtractedScore? tryParse(Map<String, Object?> m) {
    final subject = J.str(m['subject']).trim();
    if (subject.isEmpty) return null;
    return ExtractedScore(
      subject: subject,
      marks: J.number(m['marks']),
      maxMarks: J.number(m['maxMarks']),
      grade: J.strOrNull(m['grade']),
      classRank: J.intOrNull(m['classRank']),
      remarks: J.str(m['remarks']),
      absent: J.flag(m['absent']),
      confidence: J.confidence(m['confidence']),
    );
  }
}

class ReportCardExtraction {
  const ReportCardExtraction({
    this.examLabel = '',
    this.date,
    this.confidence = 0,
    this.attendancePercent,
    this.teacherRemarks = '',
    this.scores = const [],
    this.model = '',
  });

  final String examLabel;
  final DateTime? date;
  final double confidence;
  final double? attendancePercent;
  final String teacherRemarks;
  final List<ExtractedScore> scores;
  final String model;

  factory ReportCardExtraction.fromJson(Map<String, Object?> m) =>
      ReportCardExtraction(
        examLabel: J.str(m['examLabel']),
        date: DateTime.tryParse(J.str(m['date'])),
        confidence: J.confidence(m['confidence'], 0),
        attendancePercent: J.number(m['attendancePercent']),
        teacherRemarks: J.str(m['teacherRemarks']),
        scores: [for (final s in J.maps(m['scores'])) ?ExtractedScore.tryParse(s)],
        model: J.str(m['model']),
      );
}

// ── F. Focus plan ─────────────────────────────────────────────────────────

class PracticeSuggestion {
  const PracticeSuggestion({
    required this.type,
    required this.chapters,
    required this.questionCount,
  });

  final PaperOutput type;
  final List<String> chapters;
  final int questionCount;

  Map<String, Object?> toJson() => {
    'type': type.wire,
    'chapters': chapters,
    'questionCount': questionCount,
  };

  factory PracticeSuggestion.fromJson(Map<String, Object?> m) =>
      PracticeSuggestion(
        type: PaperOutput.fromWire(m['type'] as String?),
        chapters: J.strings(m['chapters']),
        questionCount: J.integer(m['questionCount'], 10).clamp(3, 40),
      );
}

class FocusWeek {
  const FocusWeek({required this.week, required this.actions});
  final int week;
  final List<String> actions;

  Map<String, Object?> toJson() => {'week': week, 'actions': actions};

  factory FocusWeek.fromJson(Map<String, Object?> m, {int fallback = 1}) =>
      FocusWeek(week: J.integer(m['week'], fallback), actions: J.strings(m['actions']));
}

class FocusSubject {
  const FocusSubject({
    required this.subject,
    this.why = '',
    this.focusChapters = const [],
    this.plan = const [],
    this.practiceSuggestion,
  });

  final String subject;
  final String why;
  final List<String> focusChapters;
  final List<FocusWeek> plan;
  final PracticeSuggestion? practiceSuggestion;

  Map<String, Object?> toJson() => {
    'subject': subject,
    'why': why,
    'focusChapters': focusChapters,
    'plan': [for (final w in plan) w.toJson()],
    'practiceSuggestion': practiceSuggestion?.toJson(),
  };

  static FocusSubject? tryParse(Map<String, Object?> m) {
    final subject = J.str(m['subject']).trim();
    if (subject.isEmpty) return null;
    final weeks = J.maps(m['plan']);
    final suggestion = m['practiceSuggestion'];
    return FocusSubject(
      subject: subject,
      why: J.str(m['why']),
      focusChapters: J.strings(m['focusChapters']),
      plan: [
        for (var i = 0; i < weeks.length; i++)
          FocusWeek.fromJson(weeks[i], fallback: i + 1),
      ],
      practiceSuggestion: suggestion is Map
          ? PracticeSuggestion.fromJson(Map<String, Object?>.from(suggestion))
          : null,
    );
  }
}

class FocusPlan {
  const FocusPlan({this.summary = '', this.subjects = const [], this.model = ''});

  final String summary;
  final List<FocusSubject> subjects;
  final String model;

  Map<String, Object?> toJson() => {
    'summary': summary,
    'subjects': [for (final s in subjects) s.toJson()],
    'model': model,
  };

  factory FocusPlan.fromJson(Map<String, Object?> m) => FocusPlan(
    summary: J.str(m['summary']),
    subjects: [for (final s in J.maps(m['subjects'])) ?FocusSubject.tryParse(s)],
    model: J.str(m['model']),
  );
}

// ── Persistence envelope ──────────────────────────────────────────────────

/// One document in `users/{uid}/children/{childId}/generated`. The payload is
/// the artefact's own `toJson()`; the envelope carries what lists and links
/// need without opening it.
class GeneratedDoc {
  const GeneratedDoc({
    required this.id,
    required this.childId,
    required this.kind,
    required this.title,
    required this.payload,
    this.subject = '',
    this.recordId,
    this.examRecordId,
    this.resultId,
    this.model = '',
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  final String id;
  final String childId;
  final GeneratedKind kind;
  final String title;
  final String subject;
  final Map<String, Object?> payload;

  /// The worksheet/exam record this artefact was filed under.
  final String? recordId;

  /// For an answer key or grading: the scanned exam record it belongs to.
  final String? examRecordId;

  /// For a graded paper: the [ExamResult] it was saved as.
  final String? resultId;
  final String model;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  GeneratedPaper get asPaper => GeneratedPaper.fromJson(payload);
  ScannedPaper get asScannedPaper => ScannedPaper.fromJson(payload);
  AnswerKey get asAnswerKey => AnswerKey.fromJson(payload);
  GradedPaper get asGradedPaper => GradedPaper.fromJson(payload);

  GeneratedDoc copyWith({
    String? id,
    String? childId,
    GeneratedKind? kind,
    String? title,
    String? subject,
    Map<String, Object?>? payload,
    String? recordId,
    String? examRecordId,
    String? resultId,
    String? model,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    DateTime? deletedAt,
  }) => GeneratedDoc(
    id: id ?? this.id,
    childId: childId ?? this.childId,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    subject: subject ?? this.subject,
    payload: payload ?? this.payload,
    recordId: recordId ?? this.recordId,
    examRecordId: examRecordId ?? this.examRecordId,
    resultId: resultId ?? this.resultId,
    model: model ?? this.model,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
