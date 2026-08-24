import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../core/services/prefs_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';

/// Brand splash on the primary fill — and the app's auth gate.
///
/// It holds the first frame only as long as Firebase takes to say whether a
/// session was restored, then routes: onboarding for a first run, login for a
/// returning parent who signed out, child setup for an account with no child,
/// and straight to the shell for everyone else. The design's "Tap to continue"
/// still works and skips the wait.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  AppState? _state;
  bool _navigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (identical(state, _state)) return;
    _state?.removeListener(_maybeRoute);
    _state = state..addListener(_maybeRoute);
    _maybeRoute();
  }

  @override
  void dispose() {
    _state?.removeListener(_maybeRoute);
    super.dispose();
  }

  void _maybeRoute() {
    final status = _state?.authStatus;
    if (status == null || status == AuthStatus.unknown) return;
    _go(status);
  }

  /// Tapping before auth resolves takes the first-run path; a session that
  /// resolves later is handled by [_maybeRoute] anyway.
  void _onTap() => _go(_state?.authStatus ?? AuthStatus.signedOut);

  void _go(AuthStatus status) {
    if (_navigated || !mounted) return;
    if (status == AuthStatus.unknown) return;
    _navigated = true;

    final route = switch (status) {
      AuthStatus.ready => Routes.shell,
      AuthStatus.needsChild => Routes.childSetup,
      _ => PrefsService.instance.hasOnboarded
          ? Routes.login
          : Routes.onboarding,
    };
    Navigator.of(context).pushReplacementNamed(route);
  }

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
          onTap: _onTap,
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
