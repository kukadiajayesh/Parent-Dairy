import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/stroke_icon.dart';

/// Brand splash on the primary fill. Tapping anywhere continues, matching the
/// design's "Tap to continue" affordance.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: k.priFill,
      ),
      child: Scaffold(
        backgroundColor: k.priFill,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              Navigator.of(context).pushReplacementNamed(Routes.onboarding),
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 46),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 86,
                          height: 86,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: k.surf,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: StrokeIcon(
                            AppIcons.book,
                            size: 42,
                            color: k.pri,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Parent Academic Diary',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Everything about your child's academics, in one place.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                            color: Color(0xFFC6CDF0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 56,
                  child: Text(
                    'Tap to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9AA5DD),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
