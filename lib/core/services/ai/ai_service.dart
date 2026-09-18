import 'dart:async';
import 'dart:convert';

import '../../../data/analytics/subject_insights.dart';
import '../../../data/models.dart';
import '../../../data/models_ai.dart';
import '../../errors/app_failure.dart';
import '../telemetry_service.dart';
import 'ai_activity_log.dart';
import 'ai_attachments.dart';
import 'ai_models.dart';
import 'ai_prompts.dart';
import 'ai_redaction.dart';
import 'gemini_client.dart';
import 'gemini_key_store.dart';
import 'gemini_schemas.dart';

/// Where a long call is, for the progress screen.
typedef AiStage = void Function(String stage);

/// Asked before a large request goes out: "This will read {pages} pages
/// (~{tokens} tokens). Continue?" Returning false cancels.
typedef AiConfirm = Future<bool> Function(int pages, int tokens);

/// The app's AI surface: one method per feature, each of which builds the
/// prompt, prepares the attachments, runs the call under a rotating key,
/// parses the reply and logs what it cost. Screens never touch
/// [GeminiClient] directly.
class AiService {
  AiService({
    required GeminiClient client,
    required AiActivityLog log,
    required String Function(AiTask task) modelFor,
  }) : _client = client,
       _log = log,
       _modelFor = modelFor;
  // ignore_for_file: prefer_initializing_formals — the public parameter
  // names read better at call sites than `_client:`.

  final GeminiClient _client;
  final AiActivityLog _log;
  final String Function(AiTask) _modelFor;

  GeminiClient get client => _client;

  // ── §C ──────────────────────────────────────────────────────────────────

  Future<GeneratedPaper> generatePaper({
    required PaperConfig config,
    required List<AiSourceFile> sources,
    required Child child,
    bool bestQuality = false,
    CancellationToken? cancel,
    AiStage? onStage,
    AiConfirm? confirm,
  }) async {
    final model = _modelFor(bestQuality ? AiTask.best : AiTask.generation);
    final grade = AiRedaction.gradeContext(child);
    final system = AiPrompts.generatePaper(
      grade: grade,
      config: config,
      sourceCount: sources.length,
    );
    _assertClean(system, child);

    return _run('generatePaper', model, () async {
      onStage?.call('Preparing pages…');
      return _client.withKey((key) async {
        final parts = await AiAttachments.toParts(
          sources,
          client: _client,
          key: key,
          cancel: cancel,
          onProgress: (done, total) =>
              onStage?.call('Preparing page $done of $total…'),
        );
        final request = GeminiRequest(
          model: model,
          systemInstruction: system,
          parts: [
            TextPart(
              'Attachment ids, in order: '
              '${sources.map((s) => s.cacheKey).join(', ')}. '
              'Generate the material now.',
            ),
            ...parts,
          ],
          responseSchema: GeminiSchemas.paper,
          temperature: 0.7,
          maxOutputTokens: 16384,
          timeout: const Duration(seconds: 180),
        );
        await _confirmLarge(request, sources, key, confirm, onStage, cancel);
        onStage?.call('Asking Gemini…');
        return _client.generate(
          request,
          parse: GeneratedPaper.fromJson,
          cancel: cancel,
          key: key,
        );
      }, cancel: cancel);
    }).then(
      (r) => r.value.copyWith(
        model: r.model,
        generatedAt: DateTime.now(),
        language: config.language,
        subject: r.value.subject.isEmpty ? config.subject : r.value.subject,
      ),
    );
  }

  /// A small follow-up carrying the paper's context and the one question to
  /// replace. Text only — no pages resent.
  Future<PaperQuestion> regenerateQuestion({
    required GeneratedPaper paper,
    required PaperQuestion question,
    required PaperConfig config,
    required Child child,
    CancellationToken? cancel,
  }) async {
    final model = _modelFor(AiTask.generation);
    final system = AiPrompts.regenerateQuestion(
      grade: AiRedaction.gradeContext(child),
      config: config,
      paper: paper,
      replace: question,
    );
    _assertClean(system, child);
    final result = await _run(
      'regenerateQuestion',
      model,
      () => _client.generate(
        GeminiRequest(
          model: model,
          systemInstruction: system,
          parts: [TextPart(jsonEncode(paper.toJson()))],
          responseSchema: GeminiSchemas.singleQuestion,
          temperature: 0.8,
          maxOutputTokens: 2048,
        ),
        parse: (json) {
          final q = PaperQuestion.tryParse(J.map(json['question']));
          if (q == null) throw const FormatException('no question');
          return q;
        },
        cancel: cancel,
      ),
    );
    return result.value.copyWith(
      number: question.number,
      marks: question.marks,
      type: question.type,
    );
  }

  // ── §D ──────────────────────────────────────────────────────────────────

  Future<ScannedPaper> scanPaper({
    required List<AiSourceFile> pages,
    required bool withAnswers,
    required Child child,
    CancellationToken? cancel,
    AiStage? onStage,
    AiConfirm? confirm,
  }) async {
    final model = _modelFor(AiTask.vision);
    final system = AiPrompts.scanPaper(
      grade: AiRedaction.gradeContext(child),
      withAnswers: withAnswers,
    );
    _assertClean(system, child);
    final result = await _run('scanPaper', model, () {
      onStage?.call('Preparing pages…');
      return _client.withKey((key) async {
        final parts = await AiAttachments.toParts(
          pages,
          client: _client,
          key: key,
          cancel: cancel,
          onProgress: (done, total) =>
              onStage?.call('Preparing page $done of $total…'),
        );
        final request = GeminiRequest(
          model: model,
          systemInstruction: system,
          parts: [
            TextPart('${pages.length} page(s) follow, in order.'),
            ...parts,
          ],
          responseSchema: GeminiSchemas.scannedPaper,
          temperature: 0.1,
          maxOutputTokens: 16384,
          timeout: const Duration(seconds: 180),
        );
        await _confirmLarge(request, pages, key, confirm, onStage, cancel);
        onStage?.call('Reading the paper…');
        return _client.generate(
          request,
          parse: ScannedPaper.fromJson,
          cancel: cancel,
          key: key,
        );
      }, cancel: cancel);
    });
    return result.value.copyWith(
      model: result.model,
      pageCount: pages.length,
      hasStudentAnswers: withAnswers,
    );
  }

  /// Over the structured questions, not the images — cheap and repeatable.
  Future<AnswerKey> answerKey({
    required ScannedPaper paper,
    required String subject,
    required Child child,
    CancellationToken? cancel,
  }) async {
    final model = _modelFor(AiTask.generation);
    final system = AiPrompts.answerKey(
      grade: AiRedaction.gradeContext(child),
      subject: subject,
    );
    _assertClean(system, child);
    final result = await _run(
      'answerKey',
      model,
      () => _client.generate(
        GeminiRequest(
          model: model,
          systemInstruction: system,
          parts: [TextPart(jsonEncode(_questionsOnly(paper)))],
          responseSchema: GeminiSchemas.answerKey,
          temperature: 0.2,
          maxOutputTokens: 16384,
          timeout: const Duration(seconds: 120),
        ),
        parse: AnswerKey.fromJson,
        cancel: cancel,
      ),
    );
    return AnswerKey(answers: result.value.answers, model: result.model);
  }

  Future<GradedPaper> gradePaper({
    required ScannedPaper paper,
    required String subject,
    required Child child,
    CancellationToken? cancel,
  }) async {
    if (!paper.hasStudentAnswers) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'This scan has no student answers to grade. Scan the completed paper '
        'with "Pages include answers" on.',
        canRetry: false,
      );
    }
    final model = _modelFor(AiTask.generation);
    final system = AiPrompts.gradePaper(
      grade: AiRedaction.gradeContext(child),
      subject: subject,
    );
    _assertClean(system, child);
    final result = await _run(
      'gradePaper',
      model,
      () => _client.generate(
        GeminiRequest(
          model: model,
          systemInstruction: system,
          parts: [TextPart(jsonEncode(_questionsWithAnswers(paper)))],
          responseSchema: GeminiSchemas.gradedPaper,
          temperature: 0.1,
          maxOutputTokens: 16384,
          timeout: const Duration(seconds: 120),
        ),
        parse: GradedPaper.fromJson,
        cancel: cancel,
      ),
    );
    return GradedPaper(questions: result.value.questions, model: result.model);
  }

  // ── §E ──────────────────────────────────────────────────────────────────

  Future<ReportCardExtraction> scanReportCard({
    required List<AiSourceFile> pages,
    required Child child,
    CancellationToken? cancel,
    AiStage? onStage,
  }) async {
    final model = _modelFor(AiTask.vision);
    final system = AiPrompts.reportCard(grade: AiRedaction.gradeContext(child));
    _assertClean(system, child);
    final result = await _run('scanReportCard', model, () {
      onStage?.call('Preparing pages…');
      return _client.withKey((key) async {
        final parts = await AiAttachments.toParts(
          pages,
          client: _client,
          key: key,
          cancel: cancel,
        );
        onStage?.call('Reading the report card…');
        return _client.generate(
          GeminiRequest(
            model: model,
            systemInstruction: system,
            parts: [const TextPart('The report card follows.'), ...parts],
            responseSchema: GeminiSchemas.reportCard,
            temperature: 0.1,
            maxOutputTokens: 8192,
            timeout: const Duration(seconds: 120),
          ),
          parse: ReportCardExtraction.fromJson,
          cancel: cancel,
          key: key,
        );
      }, cancel: cancel);
    });
    final v = result.value;
    return ReportCardExtraction(
      examLabel: v.examLabel,
      date: v.date,
      confidence: v.confidence,
      attendancePercent: v.attendancePercent,
      teacherRemarks: v.teacherRemarks,
      scores: v.scores,
      model: result.model,
    );
  }

  // ── §F ──────────────────────────────────────────────────────────────────

  /// No attachments, no name, no school: the insight numbers and the
  /// chapter list, nothing else.
  Future<FocusPlan> focusPlan({
    required List<SubjectInsight> insights,
    required Map<String, List<String>> chaptersBySubject,
    required Child child,
    CancellationToken? cancel,
  }) async {
    final model = _modelFor(AiTask.generation);
    final system = AiPrompts.focusPlan(grade: AiRedaction.gradeContext(child));
    // Reasons are app-generated but can quote a teacher's remark that names
    // the child; scrub them like any free text.
    final scrubbed = [
      for (final i in insights)
        SubjectInsight(
          subject: i.subject,
          band: i.band,
          averagePercent: i.averagePercent,
          latestPercent: i.latestPercent,
          deltaVsOwnAverage: i.deltaVsOwnAverage,
          trendPerExam: i.trendPerExam,
          sampleCount: i.sampleCount,
          completionRate: i.completionRate,
          overdueCount: i.overdueCount,
          reasons: [for (final r in i.reasons) AiRedaction.scrub(r, child)],
          confidence: i.confidence,
          focusChapters: i.focusChapters,
          signalScore: i.signalScore,
        ),
    ];
    final body = jsonEncode(
      AiPrompts.insightsJson(scrubbed, chaptersBySubject: chaptersBySubject),
    );
    _assertClean('$system\n$body', child);
    final result = await _run(
      'focusPlan',
      model,
      () => _client.generate(
        GeminiRequest(
          model: model,
          systemInstruction: system,
          parts: [TextPart(body)],
          responseSchema: GeminiSchemas.focusPlan,
          temperature: 0.5,
          maxOutputTokens: 4096,
        ),
        parse: FocusPlan.fromJson,
        cancel: cancel,
      ),
    );
    return FocusPlan(
      summary: result.value.summary,
      subjects: result.value.subjects,
      model: result.model,
    );
  }

  // ── plumbing ────────────────────────────────────────────────────────────

  /// Prompt 02 §B.5: over six images, count the tokens first and let the
  /// parent decide. Files under the cap go straight through.
  Future<void> _confirmLarge(
    GeminiRequest request,
    List<AiSourceFile> files,
    GeminiKey key,
    AiConfirm? confirm,
    AiStage? onStage,
    CancellationToken? cancel,
  ) async {
    final images = files.where((f) => !f.isPdf).length;
    if (confirm == null || images <= AiAttachments.confirmAboveImages) return;
    onStage?.call('Estimating size…');
    final tokens = await _client.countTokens(request, cancel: cancel, key: key);
    if (!await confirm(files.length, tokens)) throw AppFailure.cancelled;
  }

  /// Wraps a call with the activity log and telemetry. The log entry
  /// carries counts and the outcome kind — never content.
  Future<GeminiResult<T>> _run<T>(
    String feature,
    String model,
    Future<GeminiResult<T>> Function() body,
  ) async {
    final started = DateTime.now();
    unawaited(Telemetry.aiRequested(feature, model));
    try {
      final result = await body();
      unawaited(
        _log.add(
          AiActivityEntry(
            at: started,
            feature: feature,
            model: result.model,
            keyLabel: result.keyLabel,
            promptTokens: result.usage.promptTokens,
            responseTokens: result.usage.responseTokens,
            duration: DateTime.now().difference(started),
            outcome: 'ok',
          ),
        ),
      );
      unawaited(
        Telemetry.aiSucceeded(
          feature,
          result.usage.promptTokens + result.usage.responseTokens,
        ),
      );
      return result;
    } catch (error) {
      final failure = AppFailure.from(error);
      final kind = failure.cause is GeminiException
          ? (failure.cause! as GeminiException).kind.name
          : failure.kind.name;
      unawaited(
        _log.add(
          AiActivityEntry(
            at: started,
            feature: feature,
            model: model,
            keyLabel: failure.cause is GeminiException
                ? (failure.cause! as GeminiException).keyLabel ?? ''
                : '',
            promptTokens: 0,
            responseTokens: 0,
            duration: DateTime.now().difference(started),
            outcome: kind,
          ),
        ),
      );
      unawaited(Telemetry.aiFailed(feature, kind));
      throw failure;
    }
  }

  /// Debug-time guard that no identifier slipped into a prompt. Release
  /// builds rely on the prompt builders never taking one.
  void _assertClean(String prompt, Child child) {
    assert(
      AiRedaction.isClean(prompt, child),
      'AI prompt contains an identifier for the child',
    );
  }

  static Map<String, Object?> _questionsOnly(ScannedPaper paper) => {
    'sections': [
      for (final s in paper.sections)
        {
          'name': s.name,
          'instructions': s.instructions,
          'questions': [
            for (final q in s.questions)
              {
                'number': q.number,
                'text': q.text,
                'type': q.type,
                'marks': q.marks,
                'options': q.options,
              },
          ],
        },
    ],
  };

  static Map<String, Object?> _questionsWithAnswers(ScannedPaper paper) => {
    'sections': [
      for (final s in paper.sections)
        {
          'name': s.name,
          'questions': [
            for (final q in s.questions)
              {
                'number': q.number,
                'text': q.text,
                'type': q.type,
                'marks': q.marks ?? 1,
                'options': q.options,
                'studentAnswer': q.studentAnswer,
              },
          ],
        },
    ],
  };
}
