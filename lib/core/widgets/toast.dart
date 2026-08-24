import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_icons.dart';
import 'stroke_icon.dart';

enum ToastKind { ok, warn }

/// The design's dark floating toast: it sits above the bottom bar, carries a
/// title, a description and one trailing action ("View" / "Undo").
abstract final class AppToast {
  static void show(
    BuildContext context, {
    required String title,
    required String description,
    ToastKind kind = ToastKind.ok,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final k = Theme.of(context).extension<AppTokens>()!;
    final messenger = ScaffoldMessenger.of(context);
    final label = actionLabel ?? (kind == ToastKind.warn ? 'Undo' : 'View');

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 4200),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2C2A26),
          elevation: 10,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kind == ToastKind.warn ? k.errC : k.secC,
                  shape: BoxShape.circle,
                ),
                child: StrokeIcon(
                  kind == ToastKind.warn ? AppIcons.trash : AppIcons.check,
                  size: 16,
                  strokeWidth: 2.4,
                  color: kind == ToastKind.warn ? k.err : k.secInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Color(0xFFBDB5AA),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onAction?.call();
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9FB6DE),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
