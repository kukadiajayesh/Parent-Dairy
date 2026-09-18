import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/data/mappers.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/models_ai.dart';

Future<Map<String, Object?>> fixture(String name) async =>
    Map<String, Object?>.from(jsonDecode(await File('test/fixtures/ai/$name').readAsString()) as Map);

void main() {
  group('GeneratedPaper', () {
    test('parses a clean paper with every question type', () async {
      final paper = GeneratedPaper.fromJson(await fixture('paper_clean.json'));
      expect(paper.title, 'Class 4 · Mathematics · Fractions practice');
      expect(paper.sections.length, 2);
      expect(paper.questionCount, 6);
      expect(paper.isPartial, isFalse);
      expect(paper.computedMarks, 12);
      expect(paper.totalMarks, 12);
      expect(
        paper.questions.map((q) => q.type),
        [
          QuestionType.mcq,
          QuestionType.trueFalse,
          QuestionType.short,
          QuestionType.long,
          QuestionType.fillIn,
          QuestionType.match,
        ],
      );
      expect(paper.questions.first.options.length, 4);
      expect(paper.questions.first.sourceRef, 'att-1');
      // Round trip through toJson.
      final again = GeneratedPaper.fromJson(paper.toJson());
      expect(again.questionCount, 6);
      expect(again.questions[3].marks, 5);
    });

    test('drops unreadable questions, counts them, and fills in totals', () async {
      final paper = GeneratedPaper.fromJson(await fixture('paper_with_bad_question.json'));
      expect(paper.questionCount, 2);
      expect(paper.droppedQuestions, 2);
      expect(paper.isPartial, isTrue);
      // "three" is not a number → falls back to its position; "weird" → mcq.
      final second = paper.questions[1];
      expect(second.number, 3);
      expect(second.marks, 2);
      expect(second.type, QuestionType.mcq);
      expect(paper.totalMarks, 3);
    });

    test('replaceQuestion edits, deletes and ignores bad indexes', () async {
      final paper = GeneratedPaper.fromJson(await fixture('paper_clean.json'));
      final edited = paper.replaceQuestion(0, 0, paper.questions.first.copyWith(text: 'New'));
      expect(edited.questions.first.text, 'New');
      final deleted = paper.replaceQuestion(1, 0, null);
      expect(deleted.questionCount, 5);
      expect(identical(paper.replaceQuestion(9, 0, null), paper), isTrue);
    });

    test('PaperConfig derives marks and duration and round-trips', () {
      const config = PaperConfig(
        subject: 'Mathematics',
        chapters: ['Chapter 4'],
        output: PaperOutput.practicePaper,
        mix: {QuestionType.mcq: 4, QuestionType.short: 4, QuestionType.long: 2},
        language: PaperLanguage.gujarati,
      );
      expect(config.questionCount, 10);
      expect(config.derivedMarks, 4 + 8 + 10);
      expect(config.derivedDuration, 35);
      final again = PaperConfig.fromJson(config.toJson());
      expect(again.mix[QuestionType.long], 2);
      expect(again.language, PaperLanguage.gujarati);
      expect(again.includeAnswerKey, isTrue);
    });
  });

  group('ScannedPaper', () {
    test('parses questions, flags low confidence, keeps student answers', () async {
      final paper = ScannedPaper.fromJson(await fixture('scanned_paper.json'));
      expect(paper.detected.subject, 'Science');
      expect(paper.detected.date, DateTime(2026, 9, 12));
      expect(paper.questions.length, 3);
      expect(paper.questions[0].studentAnswer, 'Photosynthesis');
      expect(paper.questions[1].wantsReview, isTrue, reason: 'confidence 0.62');
      expect(paper.questions[2].wantsReview, isTrue, reason: 'needsReview flag');
      expect(paper.reviewCount, 2);
      expect(paper.totalMarks, 8);
      expect(paper.unreadableRegions.single.note, contains('cut off'));
      final again = ScannedPaper.fromJson(paper.toJson());
      expect(again.questions[1].options, ['Leaf', 'Root', 'Stem', 'Flower']);
    });
  });

  group('AnswerKey and GradedPaper', () {
    test('answer key drops entries without a number and looks up by number', () async {
      final key = AnswerKey.fromJson(await fixture('answer_key.json'));
      expect(key.answers.length, 2);
      expect(key.forNumber('1(a)')!.markingScheme.length, 2);
      expect(key.forNumber('1(a)')!.workedSolution.length, 2);
      expect(key.forNumber('zzz'), isNull);
    });

    test('graded paper clamps awarded to outOf and drops a zero outOf', () async {
      final graded = GradedPaper.fromJson(await fixture('graded_paper.json'));
      expect(graded.questions.length, 4);
      expect(graded.questions[3].awarded, 5, reason: 'clamped from 9');
      expect(graded.awarded, 8);
      expect(graded.outOf, 13);
      expect(graded.percent!.round(), 62);
      expect(graded.questions[2].verdict, Verdict.blank);
    });
  });

  group('ReportCardExtraction', () {
    test('a marks card keeps every row and flags the impossible one', () async {
      final card = ReportCardExtraction.fromJson(await fixture('report_card_marks.json'));
      expect(card.examLabel, 'Term 1');
      expect(card.date, DateTime(2026, 9, 30));
      expect(card.attendancePercent, 94);
      expect(card.scores.length, 3);
      final evs = card.scores[2];
      expect(evs.marksValid, isFalse, reason: '105/100');
      expect(evs.wantsReview, isTrue);
      expect(card.scores[0].marksValid, isTrue);
      expect(card.scores[1].classRank, 3);
    });

    test('a grades-only card has no marks and parses', () async {
      final card = ReportCardExtraction.fromJson(await fixture('report_card_grades_only.json'));
      expect(card.date, isNull);
      expect(card.scores.every((s) => s.marks == null && s.grade != null), isTrue);
      expect(card.scores.every((s) => s.marksValid), isTrue);
    });

    test('an absent row survives and a blank subject is dropped', () async {
      final card = ReportCardExtraction.fromJson(await fixture('report_card_absent.json'));
      expect(card.scores.length, 2);
      expect(card.scores[1].absent, isTrue);
      expect(card.scores[1].marksValid, isFalse, reason: 'marks missing, max present');
    });
  });

  group('FocusPlan', () {
    test('parses the plan and drops a subject without a name', () async {
      final plan = FocusPlan.fromJson(await fixture('focus_plan.json'));
      expect(plan.subjects.length, 1);
      final maths = plan.subjects.single;
      expect(maths.plan.length, 2);
      expect(maths.practiceSuggestion!.type, PaperOutput.quiz);
      expect(maths.practiceSuggestion!.questionCount, 10);
      expect(plan.summary, contains('Mathematics'));
    });
  });

  group('GeneratedDoc mapping', () {
    test('round-trips through Firestore with its payload intact', () async {
      final db = FakeFirebaseFirestore();
      final paper = GeneratedPaper.fromJson(await fixture('paper_clean.json'));
      final doc = GeneratedDoc(
        id: '',
        childId: 'child-1',
        kind: GeneratedKind.paper,
        title: paper.title,
        subject: 'Mathematics',
        payload: paper.toJson(),
        recordId: 'rec-1',
        model: 'gemini-test',
      );
      final ref = db.collection('t').doc('g');
      await ref.set(Map$.generatedToMap(doc));
      final parsed = Map$.generatedFrom(await ref.get());
      expect(parsed.kind, GeneratedKind.paper);
      expect(parsed.recordId, 'rec-1');
      expect(parsed.asPaper.questionCount, 6);
      expect(parsed.isDeleted, isFalse);
      final data = (await ref.get()).data()!;
      expect(data['searchTerms'], containsAll(['fractions', 'mathematics']));
    });

    test('a record origin round-trips and defaults to manual', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('t').doc('r');
      await ref.set(
        Map$.recordToMap(
          DiaryRecord(
            id: '',
            type: RecordType.worksheet,
            subject: 'Mathematics',
            title: 'AI practice',
            date: DateTime(2026, 9, 1),
            origin: RecordOrigin.ai,
          ),
        ),
      );
      expect(Map$.recordFrom(await ref.get()).origin, RecordOrigin.ai);
      expect(Map$.recordFrom(await ref.get()).isAiGenerated, isTrue);

      await ref.set({'title': 'old', 'type': 'worksheet'});
      expect(Map$.recordFrom(await ref.get()).origin, RecordOrigin.manual);
    });
  });
}
