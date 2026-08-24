import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_icons.dart';
import '../core/widgets/stroke_icon.dart';

/// Shown when Firebase could not start — a missing `google-services.json`, or a
/// Firebase API that has not been enabled for the project yet.
///
/// The parent gets one sentence they can act on; the underlying reason is kept
/// behind a disclosure for whoever is debugging the build.
class StartupErrorPage extends StatelessWidget {
  const StartupErrorPage({super.key, required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    // Rendered outside the themed MaterialApp's own routes, so the tokens are
    // attached here rather than inherited.
    return Theme(
      data: AppTheme.light(),
      child: Builder(
        builder: (context) {
          final k = context.t;
          return Scaffold(
            backgroundColor: k.bg,
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: k.errC,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: StrokeIcon(
                          AppIcons.warningTriangle,
                          size: 34,
                          color: k.err,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Couldn't connect to your account",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'The app could not reach Firebase. Check your internet '
                        'connection and reopen the app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.55,
                          color: k.tx3,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            'Technical details',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: k.tx4,
                            ),
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: k.surf2,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: SelectableText(
                                detail,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  fontFamily: 'monospace',
                                  color: k.tx3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
