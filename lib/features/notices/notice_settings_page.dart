import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/analytics/notice_reminders.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'watched_apps_page.dart';

/// Settings → Notification capture (prompt 03 §E.3). On anything but
/// Android the whole screen is the "Android only" state — there is no
/// switch to flip.
class NoticeSettingsPage extends StatefulWidget {
  const NoticeSettingsPage({super.key});

  @override
  State<NoticeSettingsPage> createState() => _NoticeSettingsPageState();
}

class _NoticeSettingsPageState extends State<NoticeSettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppScope.read(context);
      if (state.noticeCaptureSupported) state.noticeCapture.refresh();
    });
  }

  /// The §H disclosure gates the system screen: it is shown before the
  /// permission prompt the first time, and re-readable afterwards.
  Future<bool> _ensureDisclosed(AppState state) async {
    if (state.noticeDisclosureAccepted) return true;
    final ok = await Navigator.of(context, rootNavigator: true).pushNamed<bool>(Routes.noticeDisclosure);
    return ok == true;
  }

  Future<void> _toggle(bool value) async {
    final state = AppScope.read(context);
    try {
      if (value && !await _ensureDisclosed(state)) return;
      if (!mounted) return;
      await state.setNoticeCaptureEnabled(value);
      if (value && !state.noticeCapture.isGranted && mounted) await _grant();
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't change the setting");
    }
  }

  Future<void> _grant() async {
    final state = AppScope.read(context);
    try {
      if (!await _ensureDisclosed(state)) return;
      await state.noticeCapture.openSettings();
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't open system settings");
    }
  }

  Future<void> _pickRule(String packageName, String label) async {
    final state = AppScope.read(context);
    final current = state.noticeRuleFor(packageName);
    final choice = await pickOption(
      context,
      title: label,
      options: [for (final r in NoticeAppRule.values) r.label],
      current: current.label,
    );
    if (choice == null || !mounted) return;
    await state.setNoticeRule(packageName, NoticeAppRule.values.firstWhere((r) => r.label == choice));
  }

  Future<void> _pickOffsets(NoticeKind kind) async {
    final state = AppScope.read(context);
    final current = state.noticeOffsets[kind] ?? const [];
    final picked = await pickMultipleOptions(
      context,
      title: '${kind.label} reminders',
      options: [for (final d in NoticeReminders.offsetChoices) NoticeReminders.offsetLabel(d)],
      initial: [for (final d in current) NoticeReminders.offsetLabel(d)],
    );
    if (picked == null || !mounted) return;
    final days = [
      for (final d in NoticeReminders.offsetChoices)
        if (picked.contains(NoticeReminders.offsetLabel(d))) d,
    ].take(NoticeReminders.maxPerNotice).toList();
    await state.setNoticeOffsets(kind, days);
  }

  Future<void> _pickRetention() async {
    final state = AppScope.read(context);
    final choice = await pickOption(
      context,
      title: 'Keep captured notices for',
      options: const ['30 days', '90 days', '180 days'],
      current: '${state.noticeRetentionDays} days',
    );
    if (choice == null || !mounted) return;
    await state.setNoticeRetentionDays(int.parse(choice.split(' ').first));
  }

  Future<void> _deleteAll() async {
    final state = AppScope.read(context);
    final ok = await confirmDelete(
      context,
      title: 'Delete all captured notices?',
      description: 'Every notice read from your school apps is removed from your account and every reminder set from them is cancelled. Your settings stay.',
      confirmLabel: 'Delete all',
    );
    if (!ok || !mounted) return;
    try {
      await state.deleteAllNotices();
      if (!mounted) return;
      AppToast.show(context, title: 'Deleted', description: 'No captured notices remain.');
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't delete");
    }
  }

  Future<void> _allowExact() async {
    final granted = await NotificationService.instance.requestExactAlarms();
    if (!mounted) return;
    setState(() {});
    AppToast.show(
      context,
      title: granted ? 'Exact reminders on' : 'Still inexact',
      description: granted ? 'Notice reminders will fire at 07:00 sharp.' : 'Reminders may arrive up to an hour late.',
      kind: granted ? ToastKind.ok : ToastKind.warn,
      actionLabel: 'OK',
    );
  }

  static String _offsetsLabel(List<int> days) {
    if (days.isEmpty) return 'Off';
    final sorted = days.toSet().toList()..sort((a, b) => b.compareTo(a));
    return sorted.map(NoticeReminders.offsetLabel).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final capture = state.noticeCapture;
    final exact = NotificationService.instance.exactAlarmsAllowed;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Notification capture'),
            ),
            Expanded(
              child: !state.noticeCaptureSupported
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: EmptyStateView(
                        title: 'Android only',
                        description:
                            'Reading school-app notifications needs Android\'s '
                            'notification access, which iOS does not offer. '
                            'Nothing is captured on this phone.',
                      ),
                    )
                  : ListenableBuilder(
                      listenable: capture,
                      builder: (context, _) => ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        children: [
                          SettingsGroup(
                            children: [
                              SettingsRow(
                                label: 'Read school-app notifications',
                                subtitle: 'Only from the apps you pick below',
                                showChevron: false,
                                trailing: AppSwitch(value: state.noticeCaptureEnabled, onChanged: _toggle),
                                onTap: () => _toggle(!state.noticeCaptureEnabled),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          const SectionLabel('Permission'),
                          const SizedBox(height: 10),
                          SettingsGroup(
                            children: [
                              SettingsRow(
                                label: 'Notification access',
                                subtitle: !capture.hasChecked
                                    ? 'Checking…'
                                    : !capture.isGranted
                                        ? 'Not granted — nothing is read'
                                        : capture.isListenerConnected
                                            ? 'Granted and running'
                                            : 'Granted, but the service is not running',
                                value: capture.isGranted ? 'Granted' : 'Grant access',
                                onTap: _grant,
                              ),
                              SettingsRow(
                                label: 'What we read',
                                subtitle: state.noticeDisclosureAccepted ? 'Accepted · tap to read again' : 'Not yet read',
                                onTap: () => Navigator.of(context, rootNavigator: true)
                                    .pushNamed(Routes.noticeDisclosure, arguments: true),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'The title and text of notifications from the apps you tick, and '
                            'nothing else. Granted in Android\'s own settings screen; Android '
                            'or a battery manager can switch it off again without telling us, '
                            'so it is re-checked every time the app opens.',
                            style: TextStyle(fontSize: 12, height: 1.45, color: k.tx4),
                          ),
                          if (state.noticeBatteryHintDue) ...[
                            const SizedBox(height: 12),
                            _Hint(
                              title: 'Nothing captured in two weeks',
                              body: 'Some phones stop background services to save battery. '
                                  'Exclude Academic Diary from battery optimisation in '
                                  'Android settings if your school app has been posting.',
                              onDismiss: state.dismissNoticeBatteryHint,
                            ),
                          ],
                          if (exact == false) ...[
                            const SizedBox(height: 12),
                            _Hint(
                              title: 'Reminders may arrive up to an hour late',
                              body: 'Android has not allowed exact alarms for this app. '
                                  'Allow them to get school reminders at 07:00 sharp.',
                              actionLabel: 'Allow',
                              onAction: _allowExact,
                            ),
                          ],
                          const SizedBox(height: 22),
                          const SectionLabel('Watched apps'),
                          const SizedBox(height: 10),
                          SettingsGroup(
                            children: [
                              SettingsRow(
                                label: 'Choose apps',
                                subtitle: state.watchedPackages.isEmpty
                                    ? 'Pick your school\'s app'
                                    : '${state.watchedPackages.length} app${state.watchedPackages.length == 1 ? '' : 's'} watched',
                                leading: StrokeIcon(AppIcons.bell, size: 18, color: k.priInk),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(builder: (_) => const WatchedAppsPage()),
                                ),
                              ),
                              for (final p in state.watchedPackages)
                                SettingsRow(
                                  label: _labelFor(state, p),
                                  subtitle: p,
                                  value: state.noticeRuleFor(p).label,
                                  onTap: () => _pickRule(p, _labelFor(state, p)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          const SectionLabel('Default reminders'),
                          const SizedBox(height: 10),
                          SettingsGroup(
                            children: [
                              for (final kind in const [
                                NoticeKind.exam,
                                NoticeKind.assignment,
                                NoticeKind.activity,
                                NoticeKind.meeting,
                                NoticeKind.holiday,
                                NoticeKind.fee,
                              ])
                                SettingsRow(
                                  label: kind.label,
                                  subtitle: _offsetsLabel(state.noticeOffsets[kind] ?? const []),
                                  onTap: () => _pickOffsets(kind),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'All at 07:00. When a notice carries a time, the morning-of '
                            'reminder fires an hour before it instead. A notice can carry '
                            'at most four reminders; you can switch any off before confirming.',
                            style: TextStyle(fontSize: 12, height: 1.45, color: k.tx4),
                          ),
                          const SizedBox(height: 22),
                          const SectionLabel('Storage'),
                          const SizedBox(height: 10),
                          SettingsGroup(
                            children: [
                              SettingsRow(
                                label: 'Keep notices for',
                                subtitle: 'Older ones are deleted when the app opens',
                                value: '${state.noticeRetentionDays} days',
                                onTap: _pickRetention,
                              ),
                              SettingsRow(
                                label: 'Delete all captured notices',
                                subtitle: 'Removes the text and cancels their reminders',
                                labelColor: k.err,
                                hoverColor: k.errC,
                                showChevron: false,
                                onTap: _deleteAll,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The app's label from a captured notice, else the package name.
  static String _labelFor(AppState state, String packageName) =>
      state.notices.where((n) => n.packageName == packageName).firstOrNull?.appLabel ??
      WatchedAppsPage.labelCache[packageName] ??
      packageName;
}

class _Hint extends StatelessWidget {
  const _Hint({required this.title, required this.body, this.actionLabel, this.onAction, this.onDismiss});

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: k.warnC, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: StrokeIcon(AppIcons.info, size: 18, color: k.warnInk),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: k.warnInk)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(fontSize: 12.5, height: 1.4, color: k.warnInk2)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (actionLabel != null)
            SectionAction(label: actionLabel!, onTap: onAction)
          else if (onDismiss != null)
            SectionAction(label: 'Dismiss', onTap: onDismiss),
        ],
      ),
    );
  }
}
