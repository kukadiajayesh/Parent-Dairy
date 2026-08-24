import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

/// Academic Years: the active year highlighted in secondary, past years below.
class YearsPage extends StatelessWidget {
  const YearsPage({super.key});

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
              child: ScreenHeader(title: 'Academic Years'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  for (final year in state.years) ...[
                    _YearCard(
                      year: year,
                      isActive: year.label == state.activeYear,
                      onSwitch: () => state.selectYear(year.label),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  AppOutlinedButton(
                    label: 'Add academic year',
                    icon: const StrokeIcon(
                      AppIcons.plus,
                      size: 18,
                      strokeWidth: 2.2,
                    ),
                    onPressed: () => Navigator.of(context, rootNavigator: true)
                        .pushNamed(Routes.addYear),
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

class _YearCard extends StatelessWidget {
  const _YearCard({
    required this.year,
    required this.isActive,
    required this.onSwitch,
  });

  final AcademicYear year;
  final bool isActive;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? k.secC : k.surf,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? k.sec : k.bd,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  year.label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isActive ? k.secInk : k.tx,
                  ),
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: k.surf,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .5,
                      color: k.sec,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            year.meta,
            style: TextStyle(
              fontSize: 12.5,
              color: isActive ? k.secInk2 : k.tx4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isActive) ...[
                _YearAction(
                  label: 'Switch',
                  background: k.priC,
                  foreground: k.priInk,
                  onTap: onSwitch,
                ),
                const SizedBox(width: 8),
              ],
              _YearAction(
                label: 'Edit',
                background: isActive ? k.surf : k.surf2,
                foreground: isActive ? k.secInk : k.tx2,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _YearAction(
                label: 'Archive',
                background: isActive
                    ? Colors.white.withValues(alpha: .55)
                    : k.surf2,
                foreground: isActive ? k.secInk : k.tx2,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YearAction extends StatelessWidget {
  const _YearAction({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
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
