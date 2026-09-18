import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/errors/app_failure.dart';
import '../../core/services/ai/ai_attachments.dart';
import '../../core/services/ai/gemini_client.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/models_ai.dart';
import 'ai_widgets.dart';
import 'paper_preview_page.dart';

class GenerateProgressArgs {
  const GenerateProgressArgs({
    required this.config,
    required this.sources,
    this.bestQuality = false,
  });

  final PaperConfig config;
  final List<DiaryRecord> sources;
  final bool bestQuality;
}

/// Runs one generation with a real Cancel, then hands off to the preview.
/// A failure keeps the configuration so Try again is one tap.
class GenerateProgressPage extends StatefulWidget {
  const GenerateProgressPage({super.key, required this.args});

  final GenerateProgressArgs args;

  @override
  State<GenerateProgressPage> createState() => _GenerateProgressPageState();
}

class _GenerateProgressPageState extends State<GenerateProgressPage> {
  CancellationToken? _cancel;
  String _stage = 'Starting…';
  AppFailure? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<bool> _confirm(int pages, int tokens) async {
    if (!mounted) return false;
    final k = context.t;
    final subject = widget.args.config.subject;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x6B1F1B16),
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Large request',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2),
              ),
              const SizedBox(height: 12),
              Text(
                'This will read $pages pages from $subject '
                '(about ${(tokens / 1000).toStringAsFixed(1)}k tokens of your '
                'daily quota). Continue?',
                style: TextStyle(fontSize: 14, height: 1.55, color: k.tx3),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: AppOutlinedButton(
                      label: 'Cancel',
                      height: 50,
                      borderRadius: 15,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppFilledButton(
                      label: 'Continue',
                      height: 50,
                      elevated: false,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  Future<void> _run() async {
    final state = AppScope.read(context);
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _failure = null;
      _stage = 'Fetching pages…';
    });
    try {
      final files = <AiSourceFile>[];
      for (final record in widget.args.sources) {
        files.addAll(
          await AiAttachments.fromAttachments(record.attachments, subject: record.subject),
        );
      }
      cancel.throwIfCancelled();
      await AiAttachments.summarise(files);
      final paper = await state.ai.generatePaper(
        config: widget.args.config,
        sources: files,
        child: state.activeChild,
        bestQuality: widget.args.bestQuality,
        cancel: cancel,
        onStage: (s) {
          if (mounted) setState(() => _stage = s);
        },
        confirm: _confirm,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        Routes.paperPreview,
        arguments: PaperPreviewArgs(paper: paper, config: widget.args.config),
      );
    } catch (error) {
      final failure = AppFailure.from(error);
      if (!mounted) return;
      if (failure.isCancellation) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _failure = failure);
    }
  }

  void _cancelRun() {
    _cancel?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final failure = _failure;
    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: 'Generating',
                leadingIsClose: true,
                onBack: () {
                  _cancelRun();
                  Navigator.of(context).pop();
                },
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                children: [
                  if (failure == null)
                    AiProgressView(
                      title: widget.args.config.output.label,
                      stage: _stage,
                      onCancel: _cancelRun,
                    )
                  else
                    AiFailureView(
                      failure: failure,
                      onRetry: _run,
                      onCancel: () => Navigator.of(context).pop(),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    '${widget.args.config.subject} · '
                    '${widget.args.config.questionCount} questions · '
                    '${widget.args.sources.length} source record'
                    '${widget.args.sources.length == 1 ? '' : 's'}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: k.tx4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
