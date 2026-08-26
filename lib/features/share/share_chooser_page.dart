import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stroke_icon.dart';
import 'attach_answer_key_page.dart';
import 'share_image_page.dart';

/// Landing screen for a file shared into the app: file it as a brand-new
/// record, or attach it as the answer key of a worksheet that already
/// exists. Reached only from the share-intent flow (§11) — the in-app
/// "From Image" entry point still goes straight to [ShareImagePage].
class ShareChooserPage extends StatelessWidget {
  const ShareChooserPage({super.key, required this.args});

  final ShareImageArgs args;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    // An answer key is a single attachment; a multi-file share can only be a
    // new record.
    final canAttachToExisting = args.files.length == 1;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Shared file', leadingIsClose: true),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Text(
                    'What would you like to do with this file?',
                    style: TextStyle(fontSize: 14, height: 1.5, color: k.tx3),
                  ),
                  const SizedBox(height: 18),
                  _ChoiceCard(
                    title: 'Create new record',
                    description: 'Save this as a new worksheet or classwork entry',
                    icon: AppIcons.plus,
                    tint: k.priC,
                    ink: k.priInk,
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ShareImagePage(args: args),
                        settings: const RouteSettings(name: Routes.shareImage),
                      ),
                    ),
                  ),
                  if (canAttachToExisting) ...[
                    const SizedBox(height: 12),
                    _ChoiceCard(
                      title: 'Attach as answer key',
                      description:
                          'Add this file as the answer key of an existing worksheet',
                      icon: AppIcons.attachment,
                      tint: k.secC,
                      ink: k.secInk,
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) =>
                              AttachAnswerKeyPage(file: args.files.first),
                          settings:
                              const RouteSettings(name: Routes.attachAnswerKey),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.tint,
    required this.ink,
    required this.onTap,
  });

  final String title;
  final String description;
  final SvgIcon icon;
  final Color tint;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Material(
      color: k.surf,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: StrokeIcon(icon, size: 20, color: ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(fontSize: 12.5, color: k.tx3),
                    ),
                  ],
                ),
              ),
              StrokeIcon(AppIcons.forward, size: 16, color: k.tx4),
            ],
          ),
        ),
      ),
    );
  }
}
