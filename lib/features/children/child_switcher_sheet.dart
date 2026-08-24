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

/// "Switch child" sheet — the design's `overlay.child`.
abstract final class ChildSwitcherSheet {
  static Future<void> show(BuildContext context) async {
    final state = AppScope.read(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    await AppSheet.show(context, (sheetContext) {
      final k = sheetContext.t;
      return AppSheet(
        title: 'Switch child',
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < state.children.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    final child = state.children[i];
                    final selected = child.name == state.activeChild.name;
                    return AppCard(
                      radius: 18,
                      background: selected ? k.priC : k.surf,
                      borderColor: selected ? k.priFill : k.bd,
                      onTap: () {
                        state.selectChild(i);
                        Navigator.of(sheetContext).pop();
                      },
                      child: Row(
                        children: [
                          Monogram(initials: child.initials, size: 46, fontSize: 16),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  child.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  child.meta,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, color: k.tx3),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            Text(
                              'Selected',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: k.sec,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 10),
              AppOutlinedButton(
                label: 'Add child',
                icon: const StrokeIcon(AppIcons.plus, size: 18, strokeWidth: 2.2),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  rootNavigator.pushNamed(Routes.childSetup);
                },
              ),
            ],
          ),
        ),
      );
    });
  }
}
