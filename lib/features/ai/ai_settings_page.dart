import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../core/errors/app_failure.dart';
import '../../core/format.dart';
import '../../core/services/ai/ai_activity_log.dart';
import '../../core/services/ai/ai_models.dart';
import '../../core/services/ai/gemini_client.dart';
import '../../core/services/ai/gemini_key_store.dart';
import '../../core/services/prefs_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';

/// More → AI: the master switch, the parent's keys with their health, the
/// per-task model choice, the activity log and the consent screen.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  static const keyUrl = 'https://aistudio.google.com/apikey';

  List<GeminiModel>? _models;
  bool _loadingModels = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = AppScope.read(context);
      if (!state.aiKeys.isLoaded) state.aiKeys.load();
    });
  }

  Future<void> _toggle(bool value) async {
    final state = AppScope.read(context);
    try {
      await state.setAiEnabled(value);
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't change the setting");
    }
  }

  Future<void> _addKey() async {
    final state = AppScope.read(context);
    final added = await AppSheet.show<bool>(
      context,
      (sheetContext) => _AddKeySheet(state: state),
    );
    if (added == true && mounted) {
      AppToast.show(
        context,
        title: 'Key added',
        description: 'Verified with Google and saved to this phone only.',
      );
    }
  }

  Future<void> _keyActions(GeminiKey key) async {
    final state = AppScope.read(context);
    final k = context.t;
    final now = DateTime.now();
    final enabled = key.status != KeyStatus.disabled;
    final choice = await AppSheet.show<String>(
      context,
      (sheetContext) => AppSheet(
        title: key.label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${key.masked} · ${key.effectiveStatus(now).label} · '
              '${key.requestsThisMonth(now)} requests this month',
              style: TextStyle(fontSize: 13, color: k.tx3),
            ),
            if (key.lastErrorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last error: ${key.lastErrorMessage}',
                style: TextStyle(fontSize: 12.5, color: k.err),
              ),
            ],
            const SizedBox(height: 14),
            for (final option in [
              'Rename',
              if (key.status == KeyStatus.invalid) 'Re-check',
              enabled ? 'Turn off' : 'Turn on',
              'Delete',
            ]) ...[
              AppTonalButton(
                label: option,
                height: 48,
                borderRadius: 14,
                background: option == 'Delete' ? k.errC : k.surf2,
                hoverBackground: option == 'Delete' ? k.errCH : k.hov,
                foreground: option == 'Delete' ? k.err : k.tx,
                onPressed: () => Navigator.of(sheetContext).pop(option),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      switch (choice) {
        case 'Rename':
          final name = await _askLabel(key.label);
          if (name != null && name.isNotEmpty) await state.aiKeys.rename(key.id, name);
        case 'Re-check':
          await state.ai.client.listModels(verify: key.secret);
          await state.aiKeys.markActive(key.id);
          if (mounted) {
            AppToast.show(
              context,
              title: 'Key works again',
              description: '${key.label} is back in the rotation.',
            );
          }
        case 'Turn off':
          await state.aiKeys.setEnabled(key.id, false);
        case 'Turn on':
          await state.aiKeys.setEnabled(key.id, true);
        case 'Delete':
          final ok = await confirmDelete(
            context,
            title: 'Delete this key?',
            description:
                'It is removed from this phone only; the key itself stays '
                'valid in Google AI Studio.',
          );
          if (ok) await state.aiKeys.remove(key.id);
      }
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't update the key");
    }
  }

  Future<String?> _askLabel(String current) async {
    final controller = TextEditingController(text: current);
    final name = await AppSheet.show<String>(
      context,
      (sheetContext) => AppSheet(
        title: 'Rename key',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Label',
              controller: controller,
              hintText: 'Personal, Work…',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            AppFilledButton(
              label: 'Save',
              height: 50,
              elevated: false,
              onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return name;
  }

  Future<List<GeminiModel>?> _loadModels({bool force = false}) async {
    if (_models != null && !force) return _models;
    final state = AppScope.read(context);
    setState(() => _loadingModels = true);
    try {
      final models = await state.ai.client.listModels(
        cache: PrefsService.instance.raw,
        forceRefresh: force,
      );
      final usable = models.where((m) => m.supportsGenerate).toList();
      if (mounted) setState(() => _models = usable);
      return usable;
    } catch (error) {
      if (mounted) AppToast.failure(context, error, title: "Couldn't list models");
      return null;
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _pickModel(AiTask task) async {
    final models = await _loadModels();
    if (!mounted) return;
    final current = PrefsService.instance.aiModelFor(task);
    // The live list, with the default kept visible even when the list
    // could not be fetched — never a picker with nothing in it.
    final ids = <String>{
      if (models != null) ...models.map((m) => m.id) else task.defaultModel,
      current,
    }.toList();
    final choice = await pickOption(
      context,
      title: '${task.label} model',
      options: [
        for (final id in ids) id == task.defaultModel ? '$id (default)' : id,
      ],
      current: current == task.defaultModel ? '$current (default)' : current,
    );
    if (choice == null || !mounted) return;
    final id = choice.replaceAll(' (default)', '');
    await PrefsService.instance.setAiModelFor(task, id == task.defaultModel ? null : id);
    setState(() {});
  }

  Future<void> _revoke() async {
    final state = AppScope.read(context);
    final ok = await confirmDelete(
      context,
      title: 'Revoke Gemini access?',
      description:
          'Every key, cached upload and the activity log on this phone will '
          'be wiped, and the AI switch turned off. Your keys stay valid in '
          'Google AI Studio.',
      confirmLabel: 'Revoke',
    );
    if (!ok || !mounted) return;
    try {
      await state.revokeAi();
      if (!mounted) return;
      AppToast.show(
        context,
        title: 'Access revoked',
        description: 'Nothing AI-related remains on this phone.',
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't revoke");
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final keys = state.aiKeys;
    final now = DateTime.now();
    final monthly = state.aiLog.monthly(now);

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'AI'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        label: 'Use Gemini AI',
                        subtitle: 'With your own Google AI Studio key',
                        showChevron: false,
                        trailing: AppSwitch(
                          value: state.aiEnabled,
                          onChanged: _toggle,
                        ),
                        onTap: () => _toggle(!state.aiEnabled),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SectionLabel(
                    'API keys',
                    trailing: SectionAction(label: 'Add key', onTap: _addKey),
                  ),
                  const SizedBox(height: 10),
                  if (keys.loadError != null) ...[
                    InlineErrorBanner(
                      title: "Couldn't read saved keys",
                      description: keys.loadError!.message,
                      onAction: keys.load,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (!keys.isLoaded)
                    const Skeletons(child: SkeletonBox(height: 72, radius: 16))
                  else if (keys.isEmpty)
                    EmptyStateView(
                      title: 'No keys yet',
                      description:
                          'A free Google AI Studio key stays on this phone and '
                          'is only ever sent to Google.',
                      actionLabel: 'Add key',
                      onAction: _addKey,
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: keys.keys.length,
                      onReorderItem: (from, to) {
                        final ids = keys.keys.map((k) => k.id).toList();
                        ids.insert(to, ids.removeAt(from));
                        keys.reorder(ids);
                      },
                      itemBuilder: (context, index) {
                        final key = keys.keys[index];
                        return Padding(
                          key: ValueKey(key.id),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _KeyCard(
                            keyInfo: key,
                            index: index,
                            now: now,
                            onTap: () => _keyActions(key),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Keys are tried in this order. When one hits its daily '
                    'limit the next takes over until midnight UTC.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: k.tx4),
                  ),
                  const SizedBox(height: 22),
                  SectionLabel(
                    'Models',
                    trailing: SectionAction(
                      label: _loadingModels ? 'Loading…' : 'Refresh',
                      onTap: _loadingModels ? null : () => _loadModels(force: true),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      for (final task in AiTask.values)
                        SettingsRow(
                          label: task.label,
                          subtitle: task.description,
                          value: PrefsService.instance.aiModelFor(task),
                          onTap: () => _pickModel(task),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('Activity & privacy'),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        label: 'AI activity',
                        subtitle: '${monthly.requests} requests · '
                            '${_tokens(monthly.tokens)} tokens this month',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AiActivityPage(),
                          ),
                        ),
                      ),
                      SettingsRow(
                        label: 'Privacy & consent',
                        subtitle: state.aiConsented
                            ? 'Accepted · tap to read again'
                            : 'Not yet accepted',
                        onTap: () => Navigator.of(context, rootNavigator: true)
                            .pushNamed(Routes.aiConsent, arguments: true),
                      ),
                      SettingsRow(
                        label: 'Revoke access',
                        subtitle: 'Wipe keys, cached uploads and the log',
                        labelColor: k.err,
                        hoverColor: k.errC,
                        showChevron: false,
                        onTap: _revoke,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _tokens(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.keyInfo,
    required this.index,
    required this.now,
    required this.onTap,
  });

  final GeminiKey keyInfo;
  final int index;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final status = keyInfo.effectiveStatus(now);
    final (bg, ink, dot) = switch (status) {
      KeyStatus.active => (k.secC, k.secInk, k.sec),
      KeyStatus.invalid => (k.errC, k.errInk, k.err),
      KeyStatus.exhausted => (k.warnC, k.warnInk, k.warn),
      KeyStatus.disabled => (k.surf2, k.tx3, k.tx5),
    };
    return AppCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: k.priC,
              borderRadius: BorderRadius.circular(12),
            ),
            child: StrokeIcon(AppIcons.key, size: 18, color: k.priInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  keyInfo.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${keyInfo.masked} · ${keyInfo.requestsThisMonth(now)} this month',
                  style: TextStyle(fontSize: 12, color: k.tx4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(label: status.label, background: bg, foreground: ink, dotColor: dot),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: StrokeIcon(AppIcons.dragHandle, size: 18, color: k.tx5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paste, label, verify. A key is saved only after `models.list` answered
/// 200 with it — an invalid key must never be stored as working.
class _AddKeySheet extends StatefulWidget {
  const _AddKeySheet({required this.state});

  final AppState state;

  @override
  State<_AddKeySheet> createState() => _AddKeySheetState();
}

class _AddKeySheetState extends State<_AddKeySheet> {
  final _secret = TextEditingController();
  final _label = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _secret.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() => _secret.text = text);
  }

  Future<void> _verifyAndSave() async {
    final secret = _secret.text.trim();
    if (secret.length < 20) {
      setState(() => _error = 'That does not look like a Google AI Studio key.');
      return;
    }
    if (widget.state.aiKeys.keys.any((k) => k.secret == secret)) {
      setState(() => _error = 'That key is already added.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await widget.state.ai.client.listModels(verify: secret);
      await widget.state.aiKeys.add(label: _label.text, secret: secret);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      final failure = AppFailure.from(error);
      final gemini = failure.cause;
      setState(() {
        _error = gemini is GeminiException && gemini.kind == GeminiErrorKind.invalidKey
            ? 'Google rejected that key. Copy it again from AI Studio.'
            : failure.message;
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return AppSheet(
      title: 'Add a Gemini key',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Free from Google AI Studio. It stays on this phone and is only '
            'ever sent to Google with your requests.',
            style: TextStyle(fontSize: 13, height: 1.45, color: k.tx3),
          ),
          const SizedBox(height: 6),
          SectionAction(
            label: 'Get a key at aistudio.google.com',
            onTap: () => launchUrl(
              Uri.parse(_AiSettingsPageState.keyUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _ObscuredField(
                  controller: _secret,
                  errorText: _error,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              const SizedBox(width: 10),
              AppTonalButton(
                label: 'Paste',
                height: 56,
                fontSize: 14,
                borderRadius: 14,
                background: k.priC,
                hoverBackground: k.priCH,
                foreground: k.priInk,
                onPressed: _paste,
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Label (optional)',
            controller: _label,
            hintText: 'Personal, Work…',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 18),
          AppFilledButton(
            label: _verifying ? 'Verifying…' : 'Verify & save',
            elevated: false,
            onPressed: _verifying ? null : _verifyAndSave,
          ),
        ],
      ),
    );
  }
}

/// The key field: obscured, monospaced, no autocorrect, trimmed on use.
class _ObscuredField extends StatelessWidget {
  const _ObscuredField({
    required this.controller,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('API key', emphasis: hasError ? FieldEmphasis.error : FieldEmphasis.neutral),
        const SizedBox(height: 6),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: hasError ? k.errC : k.surf2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hasError ? k.err : k.bd3, width: 1.5),
          ),
          child: TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            onChanged: onChanged,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: k.tx),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'AIza…',
              hintStyle: TextStyle(fontSize: 15, color: k.tx6),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(errorText!, style: TextStyle(fontSize: 12, color: k.err)),
        ],
      ],
    );
  }
}

/// The last 100 calls with their cost, and a Clear.
class AiActivityPage extends StatelessWidget {
  const AiActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final log = state.aiLog;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: log,
          builder: (context, _) {
            final entries = log.entries;
            final monthly = log.monthly(DateTime.now());
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ScreenHeader(
                    title: 'AI activity',
                    actions: [
                      if (entries.isNotEmpty)
                        AppIconButton(
                          tooltip: 'Clear',
                          hoverBackground: k.errC,
                          onTap: () async {
                            if (await confirmDelete(
                              context,
                              title: 'Clear the activity log?',
                              description: 'Only this phone\'s record of past calls is removed.',
                              confirmLabel: 'Clear',
                            )) {
                              await log.clear();
                            }
                          },
                          child: StrokeIcon(AppIcons.trash, size: 19, color: k.err),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: k.priC,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            _Stat(value: '${monthly.requests}', label: 'requests this month'),
                            const SizedBox(width: 22),
                            _Stat(
                              value: _AiSettingsPageState._tokens(monthly.tokens),
                              label: 'tokens this month',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Google does not expose free-tier usage, so this is the '
                        'app\'s own tally. Nothing here includes what was sent '
                        'or received.',
                        style: TextStyle(fontSize: 12, height: 1.4, color: k.tx4),
                      ),
                      const SizedBox(height: 18),
                      if (entries.isEmpty)
                        const EmptyListNotice(
                          title: 'No AI calls yet',
                          description: 'Each request is listed here with its cost.',
                        )
                      else
                        for (final e in entries) ...[
                          _EntryRow(entry: e),
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1, color: k.priInk),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: k.priInk2)),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final AiActivityEntry entry;

  static const _features = {
    'generatePaper': 'Practice paper',
    'regenerateQuestion': 'Replace question',
    'scanPaper': 'Scan exam paper',
    'answerKey': 'Answer key',
    'gradePaper': 'Grade paper',
    'scanReportCard': 'Scan report card',
    'focusPlan': 'Focus plan',
  };

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final ok = entry.succeeded;
    return AppCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _features[entry.feature] ?? entry.feature,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppDate.short(entry.at)} · ${entry.model}'
                  '${entry.keyLabel.isEmpty ? '' : ' · ${entry.keyLabel}'} · '
                  '${(entry.duration.inMilliseconds / 1000).toStringAsFixed(1)}s',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: k.tx4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (ok)
            Text(
              '${entry.totalTokens} tok',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: k.tx3),
            )
          else
            StatusPill(
              label: entry.outcome,
              background: k.errC,
              foreground: k.errInk,
              dotColor: k.err,
            ),
        ],
      ),
    );
  }
}
