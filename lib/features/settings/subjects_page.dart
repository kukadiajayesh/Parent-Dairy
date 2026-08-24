import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';

/// Manage Subjects: reorder handle, badge, name and order, edit + delete.
class SubjectsPage extends StatelessWidget {
  const SubjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Manage Subjects'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  for (final subject in state.subjects) ...[
                    AppCard(
                      radius: 16,
                      child: Row(
                        children: [
                          StrokeIcon(
                            AppIcons.dragHandle,
                            size: 18,
                            color: k.bd5,
                          ),
                          const SizedBox(width: 12),
                          SubjectBadge(
                            abbr: subject.abbr,
                            hue: subject.hue,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subject.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'Order ${subject.order}',
                                  style:
                                      TextStyle(fontSize: 12, color: k.tx4),
                                ),
                              ],
                            ),
                          ),
                          AppIconButton(
                            size: 34,
                            borderRadius: 10,
                            tooltip: 'Edit',
                            onTap: () {},
                            child: StrokeIcon(
                              AppIcons.editSimple,
                              size: 17,
                              color: k.tx2,
                            ),
                          ),
                          AppIconButton(
                            size: 34,
                            borderRadius: 10,
                            tooltip: 'Delete',
                            hoverBackground: k.errC,
                            onTap: () async {
                              final confirmed = await confirmDelete(
                                context,
                                title: 'Delete ${subject.name}?',
                                description:
                                    'Records already saved under this subject '
                                    'keep their colour and label.',
                              );
                              if (confirmed) state.removeSubject(subject.name);
                            },
                            child: StrokeIcon(
                              AppIcons.trash,
                              size: 17,
                              color: k.err,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  AppOutlinedButton(
                    label: 'Add subject',
                    icon: const StrokeIcon(
                      AppIcons.plus,
                      size: 18,
                      strokeWidth: 2.2,
                    ),
                    onPressed: () => Navigator.of(context, rootNavigator: true)
                        .pushNamed(Routes.addSubject),
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
