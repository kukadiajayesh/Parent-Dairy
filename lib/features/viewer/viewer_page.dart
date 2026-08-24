import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/attachment_actions.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/image_slot.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/models.dart';

class ViewerArgs {
  const ViewerArgs({required this.attachments, this.initialIndex = 0});

  final List<Attachment> attachments;
  final int initialIndex;
}

/// Full-screen attachment viewer: pinch to zoom, swipe to browse, with a
/// filmstrip and page dots along the bottom.
class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.args});

  final ViewerArgs args;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  static const _bg = Color(0xFF141210);
  static const _chip = Color(0xFF26231F);
  static const _muted = Color(0xFF9C948A);

  late final PageController _controller =
      PageController(initialPage: widget.args.initialIndex);
  late int _index = widget.args.initialIndex;
  bool _busy = false;

  List<Attachment> get _items => widget.args.attachments;

  Attachment get _current => _items[_index];

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) AppToast.failure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _run(() => AttachmentActions.share(_current));

  Future<void> _download() => _run(() async {
    final path = await AttachmentActions.saveToDevice(_current);
    if (!mounted) return;
    AppToast.show(
      context,
      title: 'Saved to this phone',
      // Show just "Academic Diary/fractions-page-1.jpg", not the full
      // sandbox path, which means nothing to a parent.
      description: path.split('/').reversed.take(2).toList().reversed.join('/'),
      actionLabel: 'Open',
      onAction: () => _run(() => AttachmentActions.open(_current)),
    );
  });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, _items.length - 1);
    if (next == _index) return;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Scaffold(backgroundColor: _bg, body: SizedBox.shrink());
    }
    final current = _items[_index];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _bg,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    AppIconButton(
                      onTap: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                      child: const StrokeIcon(
                        AppIcons.close,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            current.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${current.isPdf ? 'Document' : 'Image'} '
                            '${_index + 1} of ${_items.length}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      onTap: _busy ? null : _share,
                      tooltip: 'Share',
                      child: const StrokeIcon(
                        AppIcons.share,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                    AppIconButton(
                      onTap: _busy ? null : _download,
                      tooltip: 'Download',
                      child: const StrokeIcon(
                        AppIcons.download,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PageView.builder(
                      controller: _controller,
                      itemCount: _items.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: _items[index].isPdf
                              ? _PdfPlaceholder(
                                  attachment: _items[index],
                                  onOpen: () => _run(
                                    () => AttachmentActions.open(_items[index]),
                                  ),
                                )
                              : ImageSlot(
                                  placeholder: _items[index].meta,
                                  image: attachmentImage(_items[index]),
                                  radius: 10,
                                ),
                        ),
                      ),
                    ),
                    if (_index > 0)
                      Positioned(
                        left: 18,
                        child: _ArrowButton(
                          icon: AppIcons.back,
                          onTap: () => _go(-1),
                        ),
                      ),
                    if (_index < _items.length - 1)
                      Positioned(
                        right: 18,
                        child: _ArrowButton(
                          icon: AppIcons.forward,
                          onTap: () => _go(1),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: i == _index ? 20 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? Colors.white
                            : const Color(0xFF5A534B),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 58,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          if (item.isPdf) {
                            return GestureDetector(
                              onTap: () => _controller.jumpToPage(index),
                              child: Container(
                                width: 58,
                                height: 58,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _chip,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'PDF',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFBDB5AA),
                                  ),
                                ),
                              ),
                            );
                          }
                          return ImageSlot(
                            placeholder: '${index + 1}',
                            image: attachmentImage(_items[index]),
                            radius: 10,
                            width: 58,
                            height: 58,
                            onTap: () => _controller.jumpToPage(index),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 58,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _chip,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Pinch to zoom · swipe to browse',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                ),
              ),
              const SizedBox(height: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});

  final SvgIcon icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .5),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: 38,
          child: Center(
            child: StrokeIcon(
              icon,
              size: 20,
              color: Colors.white,
              strokeWidth: 2.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A PDF cannot be drawn inline without embedding a renderer, so the viewer
/// shows the document's identity and hands off to the phone's PDF app.
class _PdfPlaceholder extends StatelessWidget {
  const _PdfPlaceholder({required this.attachment, required this.onOpen});

  final Attachment attachment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF26231F),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PDF',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFFBDB5AA),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                attachment.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Color(0xFF9C948A),
                ),
              ),
            ),
            const SizedBox(height: 14),
            AppTonalButton(
              label: 'Open document',
              height: 44,
              fontSize: 13.5,
              borderRadius: 13,
              background: const Color(0xFF34302B),
              hoverBackground: const Color(0xFF3E3933),
              foreground: Colors.white,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}
