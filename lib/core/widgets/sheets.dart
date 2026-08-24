import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_icons.dart';
import 'buttons.dart';
import 'stroke_icon.dart';

/// Rounded modal sheet with the design's grab handle and 19/800 title.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GrabHandle(),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }

  /// Opens [builder] as a modal sheet using the design's scrim and radius.
  static Future<T?> show<T>(
    BuildContext context,
    WidgetBuilder builder,
  ) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: builder,
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: k.bd4,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// Destructive confirmation dialog ("Delete this record?").
Future<bool> confirmDelete(
  BuildContext context, {
  String title = 'Delete this record?',
  String description =
      'This record and its attachments will be removed from your academic diary.',
  String confirmLabel = 'Delete',
}) async {
  final k = context.t;
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x6B1F1B16),
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: k.errC,
                borderRadius: BorderRadius.circular(16),
              ),
              child: StrokeIcon(AppIcons.trashLines, size: 22, color: k.err),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(fontSize: 14, height: 1.55, color: k.tx3),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppOutlinedButton(
                    label: 'Cancel',
                    height: 50,
                    borderRadius: 15,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppFilledButton(
                    label: confirmLabel,
                    height: 50,
                    elevated: false,
                    color: k.errFill,
                    hoverColor: k.errFillH,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
