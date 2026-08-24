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

/// Manage Children: one card per child with edit and delete actions.
class ChildrenPage extends StatelessWidget {
  const ChildrenPage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final root = Navigator.of(context, rootNavigator: true);

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Manage Children'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  for (final child in state.children) ...[
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Monogram(
                                initials: child.initials,
                                size: 48,
                                fontSize: 16,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      child.name,
                                      style: const TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      child.meta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: k.tx3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              StatusPill(
                                label: child.year,
                                background: k.surf2,
                                foreground: k.tx3,
                                fontSize: 11.5,
                              ),
                              const Spacer(),
                              _SmallAction(
                                label: 'Edit',
                                background: k.surf2,
                                hoverBackground: k.hov,
                                foreground: k.tx2,
                                onTap: () => root.pushNamed(
                                  Routes.childSetup,
                                  arguments: child,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _SmallAction(
                                label: 'Delete',
                                background: k.errC,
                                hoverBackground: k.errCH,
                                foreground: k.err,
                                onTap: () => confirmDelete(
                                  context,
                                  title: 'Delete ${child.name}?',
                                  description:
                                      'Every record saved for ${child.name} '
                                      'will be removed from your diary.',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  AppOutlinedButton(
                    label: 'Add child',
                    icon: const StrokeIcon(
                      AppIcons.plus,
                      size: 18,
                      strokeWidth: 2.2,
                    ),
                    onPressed: () => root.pushNamed(Routes.childSetup),
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

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.label,
    required this.background,
    required this.hoverBackground,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color hoverBackground;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverBackground,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
