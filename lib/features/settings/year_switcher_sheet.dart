import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';

/// "Academic year" sheet — the design's `overlay.year`.
abstract final class YearSwitcherSheet {
  static Future<void> show(BuildContext context) async {
    final state = AppScope.read(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    await AppSheet.show(context, (sheetContext) {
      final k = sheetContext.t;
      return AppSheet(
        title: 'Academic year',
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final year in state.years) ...[
                AppCard(
                  radius: 16,
                  padding: const EdgeInsets.all(16),
                  background: year.label == state.activeYear ? k.secC : k.surf,
                  borderColor:
                      year.label == state.activeYear ? k.sec : k.bd,
                  onTap: () {
                    state.selectYear(year.label);
                    Navigator.of(sheetContext).pop();
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          year.label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (year.label == state.activeYear)
                        Text(
                          'ACTIVE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .5,
                            color: k.sec,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              AppOutlinedButton(
                label: 'Add academic year',
                icon: const StrokeIcon(AppIcons.plus, size: 18, strokeWidth: 2.2),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  rootNavigator.pushNamed(Routes.addYear);
                },
              ),
            ],
          ),
        ),
      );
    });
  }
}
