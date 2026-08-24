import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';
import '../../data/sample_data.dart';
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
  bool _notifications = true;

  void _push(Widget page) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );

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
                        const Monogram(
                          initials: SampleData.parentInitials,
                          size: 48,
                          fontSize: 16,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                SampleData.parentFullName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                SampleData.parentEmail,
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
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('App'),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        label: 'Notifications',
                        showChevron: false,
                        onTap: () =>
                            setState(() => _notifications = !_notifications),
                        trailing: AppSwitch(
                          value: _notifications,
                          width: 48,
                          height: 28,
                          onChanged: (v) => setState(() => _notifications = v),
                        ),
                      ),
                      SettingsRow(
                        label: 'Theme',
                        subtitle: state.themeLabel,
                        showChevron: false,
                        onTap: state.toggleTheme,
                        trailing: AppSwitch(
                          value: state.isDark,
                          width: 48,
                          height: 28,
                          activeColor: k.priFill,
                          onChanged: (_) => state.toggleTheme(),
                        ),
                      ),
                      SettingsRow(
                        label: 'Backup & sync',
                        subtitle: state.isOffline
                            ? 'Waiting for a connection'
                            : 'Last synced 2 minutes ago',
                        showChevron: false,
                        onTap: state.toggleOffline,
                        trailing: StatusPill(
                          label: state.isOffline ? 'Offline' : 'Synced',
                          background: state.isOffline ? k.warnC : k.secC,
                          foreground:
                              state.isOffline ? k.warnInk : k.secInk,
                          dotColor: state.isOffline ? k.warn : k.secFill,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Account'),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      for (final label in const [
                        'Google account',
                        'Privacy',
                        'Terms',
                        'Help & support',
                      ])
                        SettingsRow(label: label, onTap: () {}),
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
                        onTap: () async {
                          final confirmed = await confirmDelete(
                            context,
                            title: 'Log out?',
                            description:
                                'You can sign back in with Google at any time.',
                            confirmLabel: 'Log out',
                          );
                          if (!confirmed || !context.mounted) return;
                          Navigator.of(context, rootNavigator: true)
                              .pushNamedAndRemoveUntil(
                            Routes.login,
                            (_) => false,
                          );
                        },
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
