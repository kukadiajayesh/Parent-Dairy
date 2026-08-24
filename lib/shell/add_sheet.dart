import 'package:flutter/material.dart';

import '../app/routes.dart';
import '../core/config/feature_flags.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_icons.dart';
import '../core/widgets/layout.dart';
import '../core/widgets/sheets.dart';
import '../core/widgets/stroke_icon.dart';

/// "Add to diary" sheet: the highlighted From-Image entry point plus one row
/// per record type. Exam and Marks rows are gated on [kShowExamMarks].
abstract final class AddSheet {
  static Future<void> show(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    await AppSheet.show(context, (sheetContext) {
      final k = sheetContext.t;
      void go(String route) {
        Navigator.of(sheetContext).pop();
        navigator.pushNamed(route);
      }

      return AppSheet(
        title: 'Add to diary',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FromImageCard(onTap: () => go(Routes.shareImage)),
            const SizedBox(height: 12),
            _AddRow(
              title: 'Worksheet',
              description: 'Save a worksheet or homework',
              abbr: 'WS',
              tint: k.subMathC,
              ink: k.priInk,
              onTap: () => go(Routes.addWorksheet),
            ),
            const SizedBox(height: 8),
            _AddRow(
              title: 'Classwork',
              description: 'Save classwork photos',
              abbr: 'CW',
              tint: k.subSciC,
              ink: k.subSciInk,
              onTap: () => go(Routes.addClasswork),
            ),
            if (kShowExamMarks) ...[
              const SizedBox(height: 8),
              _AddRow(
                title: 'Exam',
                description: 'Add an exam/test',
                abbr: 'EX',
                tint: k.warnC,
                ink: k.warnInk,
                onTap: () {},
              ),
              const SizedBox(height: 8),
              _AddRow(
                title: 'Marks',
                description: 'Record exam marks',
                abbr: 'MK',
                tint: k.subHinC,
                ink: k.subHinInk,
                onTap: () {},
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _FromImageCard extends StatelessWidget {
  const _FromImageCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Material(
      color: k.secFill,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: k.secFillH,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const StrokeIcon(
                  AppIcons.upload,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From Image',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Create a record from a shared image',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFFCADED9)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.title,
    required this.description,
    required this.abbr,
    required this.tint,
    required this.ink,
    required this.onTap,
  });

  final String title;
  final String description;
  final String abbr;
  final Color tint;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return AppCard(
      onTap: onTap,
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              abbr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  description,
                  style: TextStyle(fontSize: 12.5, color: k.tx3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
