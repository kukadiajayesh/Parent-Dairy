import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'notice_widgets.dart';

/// More → Notices (prompt 03 §E.1): Inbox, Upcoming, All.
class NoticesPage extends StatefulWidget {
  const NoticesPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  late int _tab = widget.initialTab;

  static const _emptyCopy =
      'Academic Diary only reads notifications from the apps you pick, and '
      'none of them have posted anything since you turned this on.';

  Future<void> _ignore(CapturedNotice notice) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.ignoreNotice(notice.id);
      if (!mounted) return;
      AppToast.showOn(
        messenger,
        context,
        title: 'Ignored',
        description: notice.displayTitle,
        actionLabel: 'Undo',
        onAction: () => state.restoreNotice(notice.id),
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't ignore that");
    }
  }

  void _open(CapturedNotice notice) => Navigator.of(context, rootNavigator: true)
      .pushNamed(Routes.noticeDetail, arguments: notice.id);

  void _openSettings() =>
      Navigator.of(context, rootNavigator: true).pushNamed(Routes.noticeSettings);

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final inbox = state.noticeInbox;
    final upcoming = state.upcomingNotices;
    final all = state.notices;
    final items = switch (_tab) {
      0 => inbox,
      1 => upcoming,
      _ => all,
    };

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: 'Notices',
                subtitle: state.noticeCaptureActive
                    ? 'Reading ${state.watchedPackages.length} app${state.watchedPackages.length == 1 ? '' : 's'}'
                    : (state.noticeCaptureEnabled ? 'Access not granted' : 'Capture is off'),
                actions: [
                  AppIconButton(
                    tooltip: 'Notification capture settings',
                    onTap: _openSettings,
                    child: StrokeIcon(AppIcons.settings, size: 20, color: k.tx2),
                  ),
                ],
              ),
            ),
            if (state.noticeCaptureSupported && state.noticeCaptureEnabled) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      AppChip(
                        label: inbox.isEmpty ? 'Inbox' : 'Inbox · ${inbox.length}',
                        selected: _tab == 0,
                        onTap: () => setState(() => _tab = 0),
                      ),
                      const SizedBox(width: 8),
                      AppChip(
                        label: 'Upcoming',
                        selected: _tab == 1,
                        onTap: () => setState(() => _tab = 1),
                      ),
                      const SizedBox(width: 8),
                      AppChip(
                        label: 'All',
                        selected: _tab == 2,
                        onTap: () => setState(() => _tab = 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Expanded(
              child: RefreshIndicator(
                onRefresh: state.refreshNoticeCapture,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  children: [
                    if (!state.noticeCaptureSupported)
                      const EmptyStateView(
                        title: 'Android only',
                        description:
                            'Reading school-app notifications needs Android\'s '
                            'notification access, which iOS does not offer.',
                      )
                    else if (!state.noticeCaptureEnabled)
                      EmptyStateView(
                        title: 'Notification capture is off',
                        description:
                            'Turn it on and pick your school\'s app to have exam '
                            'dates and deadlines land here automatically.',
                        actionLabel: 'Turn on',
                        onAction: _openSettings,
                      )
                    else if (state.lastError != null && all.isEmpty)
                      ErrorStateView(
                        title: "Couldn't load notices",
                        description: state.lastError!.message,
                        actionLabel: 'Retry',
                        onAction: state.retryNotices,
                        onCancel: () => Navigator.of(context).maybePop(),
                      )
                    else if (state.isLoadingNotices && all.isEmpty)
                      const Skeletons(
                        child: Column(
                          children: [
                            SkeletonBox(height: 92, radius: 16),
                            SizedBox(height: 8),
                            SkeletonBox(height: 92, radius: 16),
                            SizedBox(height: 8),
                            SkeletonBox(height: 92, radius: 16),
                          ],
                        ),
                      )
                    else if (items.isEmpty)
                      switch (_tab) {
                        0 => all.isEmpty
                            ? EmptyStateView(
                                title: 'No notices yet',
                                description: _emptyCopy,
                                actionLabel: state.watchedPackages.isEmpty ? 'Pick apps' : null,
                                onAction: state.watchedPackages.isEmpty ? _openSettings : null,
                              )
                            : const EmptyListNotice(
                                title: 'Inbox is clear',
                                description: 'Nothing is waiting for a decision.',
                              ),
                        1 => const EmptyListNotice(
                            title: 'Nothing upcoming',
                            description: 'Confirmed notices with a date still to come show here.',
                          ),
                        _ => EmptyStateView(title: 'No notices yet', description: _emptyCopy),
                      }
                    else
                      for (final n in items) ...[
                        Dismissible(
                          key: ValueKey('notice-${n.id}'),
                          direction: n.status == NoticeStatus.ignored
                              ? DismissDirection.none
                              : DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 18),
                            decoration: BoxDecoration(
                              color: k.errC,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Ignore',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: k.err),
                            ),
                          ),
                          onDismissed: (_) => _ignore(n),
                          child: NoticeRow(notice: n, onTap: () => _open(n)),
                        ),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
