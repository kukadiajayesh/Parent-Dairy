import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/services/ai/ai_prompts.dart';
import 'package:parent_academic_diary/core/services/ai/ai_redaction.dart';
import 'package:parent_academic_diary/data/analytics/subject_insights.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/models_ai.dart';

void main() {
  final child = Child(
    name: 'Aarav Patel',
    initials: 'AP',
    school: 'Sunrise English School',
    grade: 'Class 4',
    section: 'B',
    year: '2026–27',
    grNumber: 'GR-88231',
    rollNumber: '17',
    dateOfBirth: DateTime(2017, 3, 9),
  );

  const config = PaperConfig(
    subject: 'Mathematics',
    chapters: ['Chapter 4'],
    output: PaperOutput.practicePaper,
    mix: {QuestionType.mcq: 4, QuestionType.short: 4, QuestionType.long: 2},
  );

  test('every prompt built from a fully-populated child is clean', () {
    final prompts = [
      AiPrompts.generatePaper(grade: AiRedaction.gradeContext(child), config: config, sourceCount: 3),
      AiPrompts.scanPaper(grade: AiRedaction.gradeContext(child), withAnswers: true),
      AiPrompts.answerKey(grade: AiRedaction.gradeContext(child), subject: 'Mathematics'),
      AiPrompts.gradePaper(grade: AiRedaction.gradeContext(child), subject: 'Mathematics'),
      AiPrompts.reportCard(grade: AiRedaction.gradeContext(child)),
      AiPrompts.focusPlan(grade: AiRedaction.gradeContext(child)),
    ];
    for (final p in prompts) {
      expect(AiRedaction.isClean(p, child), isTrue, reason: p);
      expect(p, contains('Class 4'));
      for (final leak in ['Aarav', 'Patel', 'Sunrise', 'GR-88231', '2017-03-09']) {
        expect(p, isNot(contains(leak)));
      }
    }
  });

  test('scrub replaces every identifier in free text', () {
    final scrubbed = AiRedaction.scrub(
      'Aarav Patel (GR-88231, roll 17) at Sunrise English School must revise chapter 4. AARAV tries hard.',
      child,
    );
    expect(scrubbed, isNot(contains('Aarav')));
    expect(scrubbed, isNot(contains('AARAV')));
    expect(scrubbed, isNot(contains('Sunrise')));
    expect(scrubbed, isNot(contains('GR-88231')));
    expect(scrubbed, contains('the student'));
    expect(scrubbed, contains('revise chapter 4'));
  });

  test('the focus-plan payload carries numbers and reasons, not names', () {
    const insight = SubjectInsight(
      subject: 'Mathematics',
      band: InsightBand.weak,
      averagePercent: 45,
      latestPercent: 40,
      deltaVsOwnAverage: -20,
      trendPerExam: -6,
      sampleCount: 3,
      completionRate: 0.4,
      overdueCount: 3,
      reasons: ['Averaging 45% — below a passing mark', "20 points below the student's own average"],
      confidence: 0.8,
      focusChapters: ['Chapter 4'],
      signalScore: 7,
    );
    final json = AiPrompts.insightsJson([insight], chaptersBySubject: {'Mathematics': ['Chapter 3', 'Chapter 4']});
    final text = json.toString();
    expect(AiRedaction.isClean(text, child), isTrue);
    expect(text, contains('45'));
    expect(text, contains('Chapter 4'));
  });

  test('gradeContext falls back when the grade is blank', () {
    expect(AiRedaction.gradeContext(child.copyWith(grade: '')), 'primary school');
    expect(AiRedaction.gradeContext(child), 'Class 4');
  });
}
