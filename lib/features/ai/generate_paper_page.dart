import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/services/ai/ai_attachments.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/models_ai.dart';
import 'ai_widgets.dart';
import 'generate_progress_page.dart';

/// What an entry point pre-fills. Everything is optional; the screen falls
/// back to the active subject and its focus chapters.
class GenerateArgs {
  const GenerateArgs({
    this.subject,
    this.chapters,
    this.output,
    this.sourceRecordIds,
    this.questionCount,
  });

  final String? subject;
  final List<String>? chapters;
  final PaperOutput? output;

  /// Pre-selected sources — "Make a similar worksheet" passes the one
  /// worksheet it was opened from.
  final List<String>? sourceRecordIds;
  final int? questionCount;
}

/// The generator's configuration screen (prompt 02 §C). Pre-filled from the
/// entry point so the common path is two taps: check the sources, Generate.
class GeneratePaperPage extends StatefulWidget {
  const GeneratePaperPage({super.key, this.args});

  final GenerateArgs? args;

  @override
  State<GeneratePaperPage> createState() => _GeneratePaperPageState();
}

class _GeneratePaperPageState extends State<GeneratePaperPage> {
  late String _subject;
  late List<String> _chapters;
  late PaperOutput _output;
  late Map<QuestionType, int> _mix;
  PaperDifficulty _difficulty = PaperDifficulty.sameAsSource;
  PaperLanguage _language = PaperLanguage.english;
  bool _includeAnswerKey = true;
  bool _bestQuality = false;
  final Set<String> _selectedSources = {};
  final _marks = TextEditingController();
  final _duration = TextEditingController();
  bool _marksEdited = false;
  bool _durationEdited = false;
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final state = AppScope.of(context);
    final args = widget.args;
    _subject = args?.subject ?? state.suggestedSubject;
    if (_subject.isEmpty && state.subjectNames.isNotEmpty) {
      _subject = state.subjectNames.first;
    }
    final focus = state.insightFor(_subject)?.focusChapters ?? const [];
    _chapters = [
      ...(args?.chapters ?? (focus.isNotEmpty ? focus : state.chaptersBySubject[_subject] ?? const [])),
    ];
    _output = args?.output ?? PaperOutput.practicePaper;
    _mix = _defaultMix(_output, args?.questionCount);
    _selectedSources.addAll(
      args?.sourceRecordIds ??
          state.sourceRecordsFor(_subject, chapters: _chapters).map((r) => r.id),
    );
    _syncDerived();
  }

  @override
  void dispose() {
    _marks.dispose();
    _duration.dispose();
    super.dispose();
  }

  static Map<QuestionType, int> _defaultMix(PaperOutput output, int? count) {
    final n = count ?? 10;
    return switch (output) {
      PaperOutput.quiz => {QuestionType.mcq: n},
      PaperOutput.flashcards => {QuestionType.short: n},
      PaperOutput.revisionNotes => {QuestionType.short: (n / 2).ceil().clamp(3, 12)},
      PaperOutput.worksheet => {
        QuestionType.fillIn: (n * 0.4).round(),
        QuestionType.short: (n * 0.4).round(),
        QuestionType.trueFalse: n - (n * 0.4).round() * 2,
      },
      PaperOutput.practicePaper => {
        QuestionType.mcq: (n * 0.4).round(),
        QuestionType.short: (n * 0.4).round(),
        QuestionType.long: n - (n * 0.4).round() * 2,
      },
    };
  }

  PaperConfig get _config => PaperConfig(
    subject: _subject,
    chapters: _chapters,
    output: _output,
    mix: {for (final e in _mix.entries) if (e.value > 0) e.key: e.value},
    difficulty: _difficulty,
    totalMarks: int.tryParse(_marks.text.trim()),
    durationMinutes: int.tryParse(_duration.text.trim()),
    language: _language,
    includeAnswerKey: _includeAnswerKey,
    sourceRecordIds: _selectedSources.toList(),
  );

  /// Marks and duration follow the mix until the parent types over them.
  void _syncDerived() {
    final c = _config;
    if (!_marksEdited) _marks.text = '${c.derivedMarks}';
    if (!_durationEdited) _duration.text = '${c.derivedDuration}';
  }

  Future<void> _pickSubject() async {
    final state = AppScope.read(context);
    final choice = await pickOption(
      context,
      title: 'Subject',
      options: state.subjectNames,
      current: _subject,
    );
    if (choice == null || !mounted || choice == _subject) return;
    setState(() {
      _subject = choice;
      final focus = state.insightFor(choice)?.focusChapters ?? const [];
      _chapters = [...(focus.isNotEmpty ? focus : state.chaptersBySubject[choice] ?? const [])];
      _selectedSources
        ..clear()
        ..addAll(state.sourceRecordsFor(choice, chapters: _chapters).map((r) => r.id));
    });
  }

  Future<void> _pickChapters() async {
    final picked = await pickMultipleOptions(
      context,
      title: 'Chapters',
      options: kChapterOptions,
      initial: _chapters,
    );
    if (picked == null || !mounted) return;
    final state = AppScope.read(context);
    setState(() {
      _chapters = picked;
      _selectedSources
        ..clear()
        ..addAll(state.sourceRecordsFor(_subject, chapters: _chapters).map((r) => r.id));
    });
  }

  Future<void> _generate() async {
    final state = AppScope.read(context);
    if (!await ensureAiReady(context)) return;
    if (!mounted) return;

    final sources = [
      for (final id in _selectedSources) ?state.recordById(id),
    ];
    // Caps are checked against the saved attachments' sizes before any
    // download or upload starts.
    try {
      final files = [
        for (final r in sources)
          for (final a in r.attachments)
            AiSourceFile(
              path: a.localPath ?? '',
              name: a.name,
              mimeType: a.mimeType ?? 'image/jpeg',
              isPdf: a.isPdf,
              bytes: a.fileSize,
              cacheKey: a.id,
            ),
      ];
      final images = files.where((f) => !f.isPdf).length;
      if (images > AiAttachments.maxImages) {
        throw StateError('$images images');
      }
    } catch (_) {
      AppToast.show(
        context,
        title: 'Too many pages',
        description: 'Gemini requests are capped at ${AiAttachments.maxImages} '
            'images. Untick a few sources.',
        kind: ToastKind.warn,
        actionLabel: 'Dismiss',
      );
      return;
    }

    Navigator.of(context).pushReplacementNamed(
      Routes.aiGenerateProgress,
      arguments: GenerateProgressArgs(
        config: _config,
        sources: sources,
        bestQuality: _bestQuality,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final candidates = state.sourceRecordsFor(_subject, chapters: _chapters, limit: 12);
    final config = _config;
    final offline = state.isOffline;
    final canGenerate = !offline && _selectedSources.isNotEmpty && config.questionCount > 0;
    final selectedPages = candidates
        .where((r) => _selectedSources.contains(r.id))
        .fold(0, (n, r) => n + r.attachments.length);

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Generate practice'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (offline) ...[
                    const OfflineBanner(),
                    const SizedBox(height: 14),
                  ],
                  PickerField(label: 'Subject', value: _subject, onTap: _pickSubject),
                  const SizedBox(height: 14),
                  PickerField(
                    label: 'Chapters',
                    value: _chapters.isEmpty ? 'All chapters seen this year' : _chapters.join(', '),
                    isPlaceholder: _chapters.isEmpty,
                    onTap: _pickChapters,
                  ),
                  const SizedBox(height: 18),
                  SectionLabel(
                    'Source pages · $selectedPages',
                    trailing: candidates.isEmpty
                        ? null
                        : SectionAction(
                            label: _selectedSources.length == candidates.length ? 'None' : 'All',
                            onTap: () => setState(() {
                              if (_selectedSources.length == candidates.length) {
                                _selectedSources.clear();
                              } else {
                                _selectedSources.addAll(candidates.map((r) => r.id));
                              }
                            }),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Questions are written only from these pages, in this '
                    'child\'s own notation and vocabulary.',
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: k.tx4),
                  ),
                  const SizedBox(height: 10),
                  if (candidates.isEmpty)
                    EmptyListNotice(
                      title: 'No worksheets or classwork yet',
                      description:
                          'Save a few $_subject pages first — Gemini writes '
                          'from your child\'s own material, never from thin air.',
                    )
                  else
                    for (final record in candidates) ...[
                      _SourceRow(
                        record: record,
                        selected: _selectedSources.contains(record.id),
                        onToggle: () => setState(() {
                          if (!_selectedSources.remove(record.id)) {
                            _selectedSources.add(record.id);
                          }
                        }),
                      ),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 14),
                  const SectionLabel('Output'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in PaperOutput.values)
                        AppChip(
                          label: o.label,
                          selected: _output == o,
                          onTap: () => setState(() {
                            _output = o;
                            _mix = _defaultMix(o, widget.args?.questionCount);
                            _syncDerived();
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SectionLabel('Question mix · ${config.questionCount}'),
                  const SizedBox(height: 8),
                  AppCard(
                    radius: 16,
                    padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                    child: Column(
                      children: [
                        for (final type in QuestionType.values)
                          CountStepper(
                            label: type.label,
                            value: _mix[type] ?? 0,
                            onChanged: (v) => setState(() {
                              _mix = {..._mix, type: v};
                              _syncDerived();
                            }),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Difficulty'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in PaperDifficulty.values)
                        AppChip(
                          label: d.label,
                          selected: _difficulty == d,
                          onTap: () => setState(() => _difficulty = d),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Total marks',
                          controller: _marks,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _marksEdited = true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppTextField(
                          label: 'Duration (min)',
                          controller: _duration,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _durationEdited = true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Language'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final l in PaperLanguage.values)
                        AppChip(
                          label: l.label,
                          selected: _language == l,
                          onTap: () => setState(() => _language = l),
                        ),
                    ],
                  ),
                  if (_language != PaperLanguage.english) ...[
                    const SizedBox(height: 8),
                    Text(
                      'The printed PDF uses the app\'s Latin font, so Hindi or '
                      'Gujarati text shows fully on screen but may not print. '
                      'Share the questions as text if that happens.',
                      style: TextStyle(fontSize: 12, height: 1.4, color: k.warnInk),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        label: 'Include answer key',
                        subtitle: 'As a separate section at the end',
                        showChevron: false,
                        trailing: AppSwitch(
                          value: _includeAnswerKey,
                          onChanged: (v) => setState(() => _includeAnswerKey = v),
                        ),
                      ),
                      SettingsRow(
                        label: 'Best quality',
                        subtitle: 'Slower and uses more of your quota',
                        showChevron: false,
                        trailing: AppSwitch(
                          value: _bestQuality,
                          onChanged: (v) => setState(() => _bestQuality = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            StickyFooter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!canGenerate)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        offline
                            ? 'Generating needs an internet connection.'
                            : _selectedSources.isEmpty
                            ? 'Tick at least one source page.'
                            : 'Add at least one question to the mix.',
                        style: TextStyle(fontSize: 12.5, color: k.tx4),
                      ),
                    ),
                  AppFilledButton(
                    label: 'Generate',
                    onPressed: canGenerate ? _generate : null,
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

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.record,
    required this.selected,
    required this.onToggle,
  });

  final DiaryRecord record;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final pages = record.attachments.length;
    return PressDip(
      child: Material(
        color: selected ? k.priC : k.surf,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? k.priBd : k.bd),
        ),
        clipBehavior: Clip.antiAlias,
        child: AppInkWell(
          onTap: onToggle,
          haptic: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
            child: Row(
              children: [
                attachmentThumb(
                  context,
                  record.attachments.firstOrNull,
                  radius: 10,
                  width: 46,
                  height: 46,
                  showCaption: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: selected ? k.priInk : k.tx,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${record.isWorksheet ? 'Worksheet' : 'Classwork'} · '
                        '$pages page${pages == 1 ? '' : 's'}'
                        '${record.chapters.isEmpty ? '' : ' · ${record.chapterLabel}'}',
                        style: TextStyle(fontSize: 12, color: selected ? k.priInk2 : k.tx4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected ? k.priFill : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: selected ? k.priFill : k.bd5, width: 1.5),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
