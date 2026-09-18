import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services/prefs_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';

/// Prompt 03 §H: shown before the system permission screen opens, and
/// repeated in the privacy policy. Pops `true` when the parent continues.
class NoticeDisclosurePage extends StatelessWidget {
  const NoticeDisclosurePage({super.key, this.readOnly = false});

  /// Opened from settings to re-read.
  final bool readOnly;

  static const headline = 'Academic Diary can read notifications from apps you choose.';

  static const intro =
      "Pick your school's app and we'll read the notifications it posts — the "
      'title and the message text — so exam dates, assignment deadlines and '
      'school events can be saved and reminded about automatically.';

  static List<String> bullets({required bool aiOn, required int retentionDays}) => [
    'We only read notifications from the apps you tick. Nothing else is read.',
    'The text is stored in your own Academic Diary account and is deleted '
        'after $retentionDays days.',
    aiOn
        ? "Nothing is sent to anyone else, except that unclear dates may be sent "
            "to Google's Gemini API under your own API key so they can be read — "
            'you can turn that off in AI settings.'
        : 'Nothing is sent to anyone else.',
    'You can turn this off, or delete everything captured, at any time in '
        'Settings → Notification capture.',
  ];

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final acceptedAt = PrefsService.instance.noticeDisclosureAt;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: 'Before you turn this on',
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
                    decoration: BoxDecoration(color: k.priC, borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      children: [
                        StrokeIcon(AppIcons.bell, size: 26, color: k.priInk),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            headline,
                            style: TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w700, color: k.priInk),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(intro, style: TextStyle(fontSize: 14, height: 1.55, color: k.tx2)),
                  const SizedBox(height: 16),
                  for (final b in bullets(aiOn: state.aiEnabled, retentionDays: state.noticeRetentionDays)) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(width: 6, height: 6, decoration: BoxDecoration(color: k.pri, shape: BoxShape.circle)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(b, style: TextStyle(fontSize: 14, height: 1.55, color: k.tx2))),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Android will ask you to allow "Academic Diary notice capture" '
                    'on the next screen. This is a system setting; you can '
                    'revoke it there at any time.',
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: k.tx4),
                  ),
                  if (readOnly && acceptedAt != null) ...[
                    const SizedBox(height: 12),
                    Text('Accepted on ${AppDate.full(acceptedAt)}.', style: TextStyle(fontSize: 12.5, color: k.tx4)),
                  ],
                ],
              ),
            ),
            if (!readOnly)
              StickyFooter(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppFilledButton(
                      label: 'Continue',
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        await state.acceptNoticeDisclosure();
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
