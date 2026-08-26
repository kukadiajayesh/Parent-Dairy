import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/image_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import 'attachment_source_row.dart';

/// Dark capture / review screen (§12).
///
/// Returns the files the parent kept, so the form that pushed it can attach
/// them. Cancelling returns an empty list, never a partial one.
class PickerPage extends StatefulWidget {
  const PickerPage({
    super.key,
    this.initialSource,
    this.allowMultiple = true,
    this.imagesOnly = false,
  });

  /// Opens straight into the camera or gallery, so "Camera" on a form is one
  /// tap rather than two (§37).
  final AttachmentSource? initialSource;

  final bool allowMultiple;

  /// Hides the "Files" source — camera and gallery only ever produce images,
  /// so this is enough to enforce "image attachment only" (exam timetable,
  /// previous exam papers) without touching [ImageService].
  final bool imagesOnly;

  @override
  State<PickerPage> createState() => _PickerPageState();
}

class _PickerPageState extends State<PickerPage> {
  static const _ink = Color(0xFF1F1B16);
  static const _chip = Color(0xFF33302B);
  static const _muted = Color(0xFFBDB5AA);
  static const _accent = Color(0xFF9FB6DE);

  final List<PickedAttachment> _shots = [];
  int _selected = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final source = widget.initialSource;
    if (source != null) {
      // After the first frame so the dark scaffold is behind the system camera
      // rather than a white flash.
      WidgetsBinding.instance.addPostFrameCallback((_) => _pick(source));
    }
  }

  PickedAttachment? get _current =>
      _shots.isEmpty ? null : _shots[_selected.clamp(0, _shots.length - 1)];

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

  Future<void> _pick(AttachmentSource source) => _run(() async {
    final picked = switch (source) {
      AttachmentSource.camera => [
        ?await ImageService.capture(),
      ],
      AttachmentSource.gallery => await ImageService.pickFromGallery(
        multiple: widget.allowMultiple,
      ),
      AttachmentSource.files => await ImageService.pickFiles(
        multiple: widget.allowMultiple,
      ),
    };
    if (picked.isEmpty || !mounted) return;

    setState(() {
      if (widget.allowMultiple) {
        _shots.addAll(picked);
      } else {
        _shots
          ..clear()
          ..add(picked.first);
      }
      _selected = _shots.length - 1;
    });
  });

  Future<void> _crop() => _run(() async {
    final current = _current;
    if (current == null) return;
    final cropped = await ImageService.crop(current, tokens: context.t);
    if (!mounted) return;
    setState(() => _shots[_selected] = cropped);
  });

  Future<void> _rotate() => _run(() async {
    final current = _current;
    if (current == null) return;
    final rotated = await ImageService.rotate(current);
    if (!mounted) return;
    setState(() => _shots[_selected] = rotated);
  });

  void _deleteSelected() {
    if (_shots.isEmpty) return;
    setState(() {
      _shots.removeAt(_selected);
      _selected = _shots.isEmpty ? 0 : _selected.clamp(0, _shots.length - 1);
    });
  }

  void _done() => Navigator.of(context).pop<List<PickedAttachment>>(_shots);

  void _cancel() =>
      Navigator.of(context).pop<List<PickedAttachment>>(const []);

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final current = _current;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _ink,
      ),
      child: Scaffold(
        backgroundColor: _ink,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    AppIconButton(
                      onTap: _cancel,
                      tooltip: 'Cancel',
                      child: const StrokeIcon(
                        AppIcons.close,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Add attachment',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _shots.isEmpty ? null : _done,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _shots.isEmpty ? _muted : _accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      pickedAttachmentThumb(
                        context,
                        current,
                        radius: 18,
                        showCaption: false,
                      ),
                      if (_busy)
                        const ColoredBox(
                          color: Color(0x66000000),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _shots.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    if (index == _shots.length) {
                      return InkWell(
                        onTap: () => _pick(AttachmentSource.camera),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _chip, width: 1.5),
                          ),
                          child: const Center(
                            child: StrokeIcon(
                              AppIcons.plus,
                              size: 20,
                              color: _muted,
                            ),
                          ),
                        ),
                      );
                    }
                    final shot = _shots[index];
                    return GestureDetector(
                      onTap: () => setState(() => _selected = index),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: index == _selected
                                ? _accent
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: pickedAttachmentThumb(
                          context,
                          shot,
                          radius: 12,
                          width: 64,
                          height: 64,
                          showCaption: false,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Tool(
                      icon: AppIcons.crop,
                      label: 'Crop',
                      // Cropping a PDF is meaningless; the tool greys out
                      // rather than failing after the tap.
                      onTap: (current?.isPdf ?? true) ? null : _crop,
                    ),
                    _Tool(
                      icon: AppIcons.rotate,
                      label: 'Rotate',
                      onTap: (current?.isPdf ?? true) ? null : _rotate,
                    ),
                    _Tool(
                      icon: AppIcons.trash,
                      label: 'Delete',
                      tint: const Color(0xFFE8A79F),
                      onTap: _shots.isEmpty ? null : _deleteSelected,
                    ),
                    _Tool(
                      icon: AppIcons.plus,
                      label: 'Add',
                      onTap: () => _pick(AttachmentSource.gallery),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 26),
                child: Row(
                  children: [
                    Expanded(
                      child: AppTonalButton(
                        label: 'Take Photo',
                        height: 50,
                        fontSize: 14.5,
                        borderRadius: 15,
                        background: k.surf,
                        hoverBackground: k.hov2,
                        foreground: k.tx,
                        onPressed: () => _pick(AttachmentSource.camera),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTonalButton(
                        label: 'Gallery',
                        height: 50,
                        fontSize: 14.5,
                        borderRadius: 15,
                        background: _chip,
                        hoverBackground: const Color(0xFF3B372F),
                        foreground: Colors.white,
                        onPressed: () => _pick(AttachmentSource.gallery),
                      ),
                    ),
                    if (!widget.imagesOnly) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppTonalButton(
                          label: 'Files',
                          height: 50,
                          fontSize: 14.5,
                          borderRadius: 15,
                          background: _chip,
                          hoverBackground: const Color(0xFF3B372F),
                          foreground: Colors.white,
                          onPressed: () => _pick(AttachmentSource.files),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint = Colors.white,
  });

  final SvgIcon icon;
  final String label;
  final VoidCallback? onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        opacity: enabled ? 1 : .4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF33302B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: StrokeIcon(icon, size: 20, color: tint, strokeWidth: 1.9),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFBDB5AA),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
