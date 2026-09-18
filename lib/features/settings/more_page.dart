import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/config/feature_flags.dart';
import '../../core/config/grade_scale.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../states/design_states_page.dart';
import 'children_page.dart';
import 'subjects_page.dart';
import 'years_page.dart';

/// More / settings: account card, child and academic groups, app preferences.
class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  final NotificationService _notificationService = NotificationService.instance;

  void _push(Widget page) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );

  /// The scale that turns this child's report-card grades into percents.
  /// Per child, so it lives with the child rather than in app preferences.
  Future<void> _pickGradeScale() async {
    final state = AppScope.read(context);
    final choice = await pickOption(
      context,
      title: 'Grade scale',
      options: [for (final s in GradeScale.all) s.label],
      current: state.gradeScale.label,
    );
    if (choice == null || !mounted) return;
    final scale = GradeScale.all.firstWhere((s) => s.label == choice);
    try {
      await state.setGradeScale(scale.id);
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't change grade scale");
    }
  }

  Future<void> _logout() async {
    final confirmed = await confirmDelete(
      context,
      title: 'Log out?',
      description: 'You can sign back in with Google at any time.',
      confirmLabel: 'Log out',
    );
    if (!confirmed || !mounted) return;

    final state = AppScope.read(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    try {
      await _notificationService.cancelAll();
      await state.signOut();
      if (!mounted) return;
      navigator.pushNamedAndRemoveUntil(Routes.login, (_) => false);
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't log out");
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: k.bg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              titleSpacing: 20,
              title: const Text(
                'More',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              sliver: SliverList.list(
                children: [
                  AppCard(
                    child: Row(
                      children: [
                        Monogram(
                          initials: state.parentInitials,
                          size: 48,
                          fontSize: 16,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.parentFullName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                state.parentEmail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: k.tx4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Child'),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        label: 'Manage children',
                        value: '${state.children.length}',
                        onTap: () => _push(const ChildrenPage()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Academic'),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        label: 'Academic years',
                        value: state.activeYear,
                        onTap: () => _push(const YearsPage()),
                      ),
                      SettingsRow(
                        label: 'Subjects',
                        value: '${state.subjects.length}',
                        onTap: () => _push(const SubjectsPage()),
                      ),
                      if (kShowExamMarks)
                        SettingsRow(
                          label: 'Grade scale',
                          subtitle: 'How letter grades become percentages',
                          value: state.gradeScale.label,
                          onTap: _pickGradeScale,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Account'),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        label: 'Google account',
                        value: state.parentEmail,
                        showChevron: false,
                        onTap: () {},
                      ),
                      SettingsRow(
                        label: 'Logout',
                        labelColor: k.err,
                        showChevron: false,
                        hoverColor: k.errC,
                        leading: StrokeIcon(
                          AppIcons.logout,
                          size: 18,
                          color: k.err,
                        ),
                        onTap: _logout,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Design reference'),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        label: 'Empty, loading & error states',
                        subtitle: 'Gallery of the states in the design file',
                        onTap: () => _push(const DesignStatesPage()),
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
}
