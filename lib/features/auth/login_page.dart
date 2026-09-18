import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';

/// Google-only sign-in, matching the design.
///
/// Where the parent lands afterwards depends on the account: a brand-new one
/// has no child yet and goes to setup, while a reinstall on a new phone already
/// has children in Firestore and goes straight to the shell (§39).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);

    final state = AppScope.read(context);
    try {
      await state.signInWithGoogle();
      if (!mounted) return;

      // The children stream may not have delivered yet. Waiting for it here
      // keeps the parent on a spinner rather than flashing child setup at
      // someone who already has three children on another device.
      final destination = await _resolveDestination(state);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(destination);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.failure(context, error, title: "Couldn't sign in", onRetry: _signIn);
    }
  }

  Future<String> _resolveDestination(AppState state) async {
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (state.authStatus == AuthStatus.unknown &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    // On timeout, assume setup: an empty form is a smaller misstep than a shell
    // with no child selected.
    return state.authStatus == AuthStatus.ready
        ? Routes.shell
        : Routes.childSetup;
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: k.priC,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: StrokeIcon(AppIcons.book, size: 38, color: k.pri),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Welcome to Parent Academic Diary',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Keep your child's academic journey organized.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.55,
                          color: k.tx3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _GoogleButton(onPressed: _busy ? null : _signIn, busy: _busy),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _LegalLink(label: 'Privacy Policy', onTap: () {}),
                  Text('·', style: TextStyle(fontSize: 12, color: k.tx4)),
                  _LegalLink(label: 'Terms of Service', onTap: () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed, this.busy = false});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return PressDip(
      child: Material(
        color: k.surf,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: k.bd4, width: 1.5),
        ),
        child: AppInkWell(
          onTap: onPressed,
          hoverColor: k.hov2,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: k.tx3,
                    ),
                  )
                else
                  const _GoogleMark(size: 20),
                const SizedBox(width: 12),
                Text(
                  busy ? 'Signing in…' : 'Continue with Google',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: busy ? k.tx3 : k.tx,
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

/// The four-colour Google "G", painted from the same path data as the design.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark({this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  static const _parts = <(String, Color)>[
    (
      'M45 24c0-1.6-.1-2.7-.4-4H24v8h12c-.2 2-1.5 5-4 6.9l6.2 4.8C41.8 36.2 45 30.7 45 24z',
      Color(0xFF4285F4),
    ),
    (
      'M24 46c5.9 0 10.9-2 14.2-5.3l-6.2-4.8C30.2 37.2 27.4 38 24 38c-5.8 0-10.7-3.8-12.5-9l-6.4 4.9C8.4 41.2 15.6 46 24 46z',
      Color(0xFF34A853),
    ),
    (
      'M11.5 29c-.5-1.4-.8-2.9-.8-5s.3-3.6.8-5L5.1 14C3.7 16.9 3 20.3 3 24s.7 7.1 2.1 10z',
      Color(0xFFFBBC05),
    ),
    (
      'M24 10c3.2 0 6.1 1.1 8.4 3.3l5.5-5.5C34.4 4.5 29.9 2 24 2 15.6 2 8.4 6.8 5.1 14l6.4 5c1.8-5.2 6.7-9 12.5-9z',
      Color(0xFFEA4335),
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48);
    final paint = Paint()..isAntiAlias = true;
    for (final (d, color) in _parts) {
      canvas.drawPath(SvgPath.parse(d), paint..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleMarkPainter oldDelegate) => false;
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return AppInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: k.pri,
          ),
        ),
      ),
    );
  }
}
