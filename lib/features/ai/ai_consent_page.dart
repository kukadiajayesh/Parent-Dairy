import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';

/// The full-screen explainer shown before the first AI action (prompt 02
/// §G.1), and re-openable from AI settings. Pops `true` on accept.
///
/// The copy below is the consent as shipped; bump [kAiConsentVersion] when
/// it changes materially.
class AiConsentPage extends StatelessWidget {
  const AiConsentPage({super.key, this.readOnly = false});

  /// Opened from settings to re-read: no Accept, shows when it was accepted.
  final bool readOnly;

  static const termsUrl = 'https://ai.google.dev/gemini-api/terms';

  static const sections = <({String title, String body})>[
    (
      title: 'What leaves your phone',
      body:
          'Only the pages you select for a request — the worksheet photos or '
          'PDF you tick, or the exam paper and report card you photograph — '
          'and the text the app extracts from them. Images are shrunk to '
          '1600px and stripped of location data first.',
    ),
    (
      title: 'Where it goes',
      body:
          "Straight to Google's Gemini API, using your own Google AI Studio "
          'key. Nothing passes through any server of ours. The key itself '
          'is stored in this phone\'s secure keystore and is sent only to '
          'generativelanguage.googleapis.com.',
    ),
    (
      title: 'What is never sent',
      body:
          "Your child's name, school, GR or roll number, date of birth or "
          'photo, and any page you did not select. Prompts refer to '
          '"the student" and the class only.',
    ),
    (
      title: "Google's terms",
      body:
          'On the free tier, Google may use what you submit to improve its '
          'models and may review it. On a paid key it does not. Read the '
          'terms before deciding which key to use.',
    ),
    (
      title: 'You stay in control',
      body:
          'The model drafts and explains; it never decides who is weak and '
          'never saves anything until you confirm it. Everything it makes is '
          'labelled AI-generated. Revoke in More → AI wipes your keys, the '
          'cached uploads and the activity log.',
    ),
  ];

  Future<void> _openTerms(BuildContext context) async {
    final ok = await launchUrl(
      Uri.parse(termsUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      AppToast.show(
        context,
        title: "Couldn't open the link",
        description: termsUrl,
        kind: ToastKind.warn,
        actionLabel: 'Dismiss',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final acceptedAt = state.aiConsented
        ? PrefsAccepted.label(state)
        : null;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: 'Before you use Gemini AI',
                leadingIsClose: !readOnly,
                onBack: () => Navigator.of(context).pop(false),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: k.priC,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        StrokeIcon(AppIcons.sparkle, size: 26, color: k.priInk),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Generate practice papers, read exam papers and '
                            'report cards, and get a plain-language focus '
                            'plan — with your own free Google key.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                              color: k.priInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final s in sections) ...[
                    Text(
                      s.title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.body,
                      style: TextStyle(fontSize: 14, height: 1.55, color: k.tx2),
                    ),
                    if (s.title == "Google's terms") ...[
                      const SizedBox(height: 6),
                      SectionAction(
                        label: 'Read the Gemini API terms',
                        onTap: () => _openTerms(context),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                  if (acceptedAt != null)
                    Text(
                      'Accepted $acceptedAt.',
                      style: TextStyle(fontSize: 12.5, color: k.tx4),
                    ),
                ],
              ),
            ),
            if (!readOnly)
              StickyFooter(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppFilledButton(
                      label: 'I understand, continue',
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        await state.setAiConsented(true);
                        navigator.pop(true);
                      },
                    ),
                    const SizedBox(height: 10),
                    AppOutlinedButton(
                      label: 'Not now',
                      height: 48,
                      onPressed: () => Navigator.of(context).pop(false),
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

/// "on 19 Sep 2026" for the read-only view.
abstract final class PrefsAccepted {
  static String? label(AppState state) {
    final at = state.aiConsentedAt;
    return at == null ? null : 'on ${AppDate.full(at)}';
  }
}
