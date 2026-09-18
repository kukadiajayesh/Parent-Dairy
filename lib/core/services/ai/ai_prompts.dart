import '../../../data/analytics/subject_insights.dart';
import '../../../data/models_ai.dart';

/// Every system instruction in one place, versioned. The version is logged
/// with each request so a change in output quality can be traced to a
/// change in wording.
///
/// No prompt here takes the child's name, school or any identifier — only
/// the grade, and everything is phrased around "the student".
abstract final class AiPrompts {
  static const int version = 1;

  /// The one rule every prompt repeats: extract, draft, explain — never
  /// decide, and never invent.
  static const _honesty =
      'Where the source is handwritten and unclear, leave that item out or mark '
      'it needsReview rather than guessing. Return JSON matching the schema '
      'exactly, with no commentary outside it.';

  static String generatePaper({
    required String grade,
    required PaperConfig config,
    required int sourceCount,
  }) {
    final mix = [
      for (final e in config.mix.entries)
        if (e.value > 0) '${e.value} × ${e.key.label} (${e.key.wire})',
    ].join(', ');
    final difficulty = switch (config.difficulty) {
      PaperDifficulty.sameAsSource => 'the same difficulty as the attached material',
      PaperDifficulty.easier => 'slightly easier than the attached material',
      PaperDifficulty.harder => 'slightly harder than the attached material, without leaving its topics',
      PaperDifficulty.mixed => 'a mix of easy, medium and hard, labelled per question',
    };
    final output = switch (config.output) {
      PaperOutput.practicePaper => 'a practice exam paper with sections',
      PaperOutput.quiz => 'a quick quiz of multiple-choice questions',
      PaperOutput.worksheet => 'a worksheet the student writes answers on',
      PaperOutput.flashcards =>
        'a set of flashcards: each "question" is the front, each "answer" the back',
      PaperOutput.revisionNotes =>
        'revision notes: each "question" is a heading, each "answer" the notes '
            'under it, in short plain sentences',
    };
    return 'You are an experienced $grade ${config.subject} teacher preparing '
        'practice material for one student, working only from the attached '
        '$sourceCount page${sourceCount == 1 ? '' : 's'} of that student\'s own '
        'classwork and worksheets. Match the syllabus, notation, vocabulary and '
        'question style visible in the attachments. Do not introduce topics '
        'that do not appear in them. Every question must be answerable from '
        'the attached material.\n\n'
        'Produce $output. Chapters to cover: '
        '${config.chapters.isEmpty ? 'whatever the attachments cover' : config.chapters.join(', ')}. '
        'Question mix: ${mix.isEmpty ? 'your choice, about ${config.questionCount} questions' : mix}. '
        'Difficulty: $difficulty. '
        'Total marks: ${config.totalMarks ?? config.derivedMarks}. '
        'Duration: ${config.durationMinutes ?? config.derivedDuration} minutes. '
        'Number questions continuously across sections. '
        'For each question set sourceRef to the attachment id it draws on, or '
        '"derived". Use plain Unicode for maths; LaTeX only inside \$…\$. '
        'Write in ${config.language.label}. '
        '${config.includeAnswerKey ? 'Include a correct answer and a one-line explanation for every question.' : 'Include the answer for every question; explanations may be brief.'}\n\n'
        '$_honesty';
  }

  static String regenerateQuestion({
    required String grade,
    required PaperConfig config,
    required GeneratedPaper paper,
    required PaperQuestion replace,
  }) =>
      'You are an experienced $grade ${config.subject} teacher. Below is a '
      'practice paper you already wrote. Replace question ${replace.number} '
      '(type ${replace.type.wire}, ${replace.marks} marks, chapter '
      '"${replace.chapter}") with a different question of the same type, marks '
      'and chapter that does not duplicate any other question on the paper. '
      'Keep the same language (${paper.language.label}). Return only the new '
      'question.\n\n$_honesty';

  static String scanPaper({required String grade, required bool withAnswers}) =>
      'You are reading photographed pages of a $grade school exam paper, in '
      'the order given (page 0 first). Some pages may be rotated, skewed, '
      'multi-column, or carry two questions on one line; read them as they '
      'are. Extract every question in order with its number exactly as '
      'printed (e.g. "1(a)", "Q.3", "ii"), its full text, type, marks, options '
      'for multiple-choice, the pageIndex it appears on, and your confidence '
      'that you read it correctly. Question numbers may restart in each '
      'section. Detect the subject, exam type, date, class and total marks '
      'from the header when present. Keep the paper\'s own language for '
      'content; the field names stay English. Use plain Unicode for maths and '
      'LaTeX only inside \$…\$.'
      '${withAnswers ? '\n\nThe pages also carry the student\'s handwritten answers. For each question set studentAnswer to what the student actually wrote, verbatim as far as it can be read, or null if blank. Do not correct it.' : '\n\nSet studentAnswer to null for every question.'}'
      '\n\nList any region you could not read under unreadableRegions.\n\n'
      '$_honesty';

  static String answerKey({required String grade, required String subject}) =>
      'You are an experienced $grade $subject teacher. For each question in '
      'the JSON below, give the correct answer, a short worked solution as '
      'steps, a marking scheme that adds up to the question\'s marks, and the '
      'common mistakes a student at this level makes. Keep the language of the '
      'questions. Use plain Unicode for maths and LaTeX only inside \$…\$. '
      'Set confidence lower where the question was ambiguous.\n\n$_honesty';

  static String gradePaper({required String grade, required String subject}) =>
      'You are an experienced $grade $subject teacher marking one student\'s '
      'completed paper. The JSON below lists each question with its marks and '
      'the student\'s handwritten answer as it was read. For each question '
      'award marks between 0 and outOf, give a verdict (correct, partial, '
      'incorrect, or blank when nothing was written), a one-sentence reason a '
      'parent can understand, and the topic the question tests. Be fair: '
      'method marks for a right approach with a slip, no marks for a blank. '
      'If the read answer looks garbled, say so in the reason and mark '
      'conservatively.\n\n$_honesty';

  static String reportCard({required String grade}) =>
      'You are reading a photographed school report card for a $grade '
      'student. Extract the exam name, its date if printed, attendance if '
      'printed, the teacher\'s remarks, and one row per subject with marks, '
      'maximum marks, grade, class rank and remarks exactly as printed — '
      'null for anything not on the card. Mark a subject absent if the card '
      'says so. Never compute a percentage or convert a grade. Give a '
      'confidence per row.\n\n$_honesty';

  static String focusPlan({required String grade}) =>
      'You are an experienced $grade teacher talking to a parent. The JSON '
      'below is a deterministic analysis of the student\'s recent results: '
      'per subject, the average percent, the latest percent, the difference '
      'from the student\'s own overall average, the trend, worksheet '
      'completion and the reasons the app flagged it. The verdicts are '
      'fixed — do not re-rank or dispute them. Your job is only to explain, '
      'in plain language a parent can act on, and to propose a short focus '
      'plan: for each flagged subject, one sentence on why (referencing the '
      'actual numbers), the chapters to focus on from the list given, a two '
      'to three week plan of concrete actions, and one practice suggestion. '
      'Keep the summary to two or three sentences. Do not mention the student '
      'by name.\n\n$_honesty';

  /// A photographed exam timetable / date sheet → one row per subject per
  /// day. Dates are day-first; a missing year is resolved from today.
  static String timetable({required String grade, required List<String> subjects, required String today}) =>
      'You are reading a photographed school exam timetable (date sheet) for '
      'a $grade student in India. Today is $today. Extract the exam name from '
      'the header (e.g. "Unit Test 2", "Half Yearly Examination") and one '
      'entry per subject per day: the subject exactly as printed, the date '
      'as YYYY-MM-DD, the start and end time as HH:MM (24-hour) when printed, '
      'and any note on that row (room, syllabus, "practical"). Read dates '
      'day-first: 24/11 is 24 November. When the year is not printed, use the '
      'next occurrence on or after today. Rows for holidays, study leave or '
      'breaks are not exams — leave them out. The student\'s subjects are: '
      '${subjects.isEmpty ? 'not known' : subjects.join(', ')} — keep the '
      'printed name anyway; matching is done later. Give a confidence per '
      'row and one overall. Put anything you could not read under '
      'unreadable.\n\n$_honesty';

  /// Prompt 03 §C stage 2. The rules already failed to read these; the
  /// model gets the same anchors (posted date, the child's subject names)
  /// and the same honesty rule. Dates are day-first, Indian convention.
  static String classifyNotices({required String grade, required List<String> subjects}) =>
      'You are reading notifications posted by a school app for a $grade '
      'student, in India. Each item gives the notification title, its text '
      'and the date it was posted (postedAt). For each item say what it is '
      'about (kind), give a short clean title, the subject if one of these '
      'is named or abbreviated (${subjects.isEmpty ? 'none known' : subjects.join(', ')}; '
      'otherwise null), the event date and, for assignments and fees, the '
      'due date. Read dates day-first: 24/11 is 24 November. Resolve '
      '"tomorrow", "next Monday" and a missing year from postedAt. Return '
      'ISO dates (YYYY-MM-DD) and 24-hour times (HH:MM), or null when the '
      'text does not say. Notices may be in Hindi, Gujarati or a mix; read '
      'them as they are and keep the title in the same language. Give a '
      'confidence between 0 and 1 for the kind and date together, and one '
      'sentence of reasoning.\n\n$_honesty';

  /// The insight objects, serialised for [focusPlan]. Only numbers and the
  /// reasons already shown in the app — no attachments, no names.
  static Map<String, Object?> insightsJson(
    List<SubjectInsight> insights, {
    required Map<String, List<String>> chaptersBySubject,
  }) => {
    'subjects': [
      for (final i in insights)
        {
          'subject': i.subject,
          'band': i.band.name,
          'averagePercent': i.averagePercent?.round(),
          'latestPercent': i.latestPercent?.round(),
          'deltaVsOwnAverage': i.deltaVsOwnAverage?.round(),
          'trendPerExam': i.trendPerExam == null
              ? null
              : double.parse(i.trendPerExam!.toStringAsFixed(1)),
          'results': i.sampleCount,
          'worksheetCompletion': double.parse(i.completionRate.toStringAsFixed(2)),
          'overdueWorksheets': i.overdueCount,
          'reasons': i.reasons,
          'focusChapters': i.focusChapters,
          'chaptersSeenThisYear': chaptersBySubject[i.subject] ?? const [],
        },
    ],
  };
}
