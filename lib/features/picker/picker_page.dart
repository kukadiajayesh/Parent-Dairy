import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/image_slot.dart';
import '../../core/widgets/stroke_icon.dart';

/// Dark capture / review screen. Returns the number of attachments the caller
/// should add, so the form that pushed it can update its own list.
class PickerPage extends StatefulWidget {
  const PickerPage({super.key});

  @override
  State<PickerPage> createState() => _PickerPageState();
}

class _PickerPageState extends State<PickerPage> {
  static const _ink = Color(0xFF1F1B16);
  static const _chip = Color(0xFF33302B);
  static const _muted = Color(0xFFBDB5AA);

  int _shots = 2;
  int _selected = 0;

  void _capture() => setState(() {
        _shots++;
        _selected = _shots - 1;
      });

  void _deleteSelected() {
    if (_shots == 0) return;
    setState(() {
      _shots--;
      _selected = _selected.clamp(0, _shots == 0 ? 0 : _shots - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;

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
                      onTap: () => Navigator.of(context).pop(0),
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
                      onTap: () => Navigator.of(context).pop(_shots),
                      borderRadius: BorderRadius.circular(10),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9FB6DE),
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
                  child: ImageSlot(
                    key: ValueKey(_selected),
                    placeholder: _shots == 0
                        ? 'No photos yet'
                        : 'Captured photo preview',
                    radius: 18,
                  ),
                ),
              ),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _shots + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    if (index == _shots) {
                      return InkWell(
                        onTap: _capture,
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
                    return GestureDetector(
                      onTap: () => setState(() => _selected = index),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: index == _selected
                                ? const Color(0xFF9FB6DE)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ImageSlot(
                          placeholder: '${index + 1}',
                          radius: 12,
                          width: 64,
                          height: 64,
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
                    _Tool(icon: AppIcons.crop, label: 'Crop', onTap: () {}),
                    _Tool(icon: AppIcons.rotate, label: 'Rotate', onTap: () {}),
                    _Tool(
                      icon: AppIcons.trash,
                      label: 'Delete',
                      tint: const Color(0xFFE8A79F),
                      onTap: _deleteSelected,
                    ),
                    _Tool(icon: AppIcons.plus, label: 'Add', onTap: _capture),
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
                        onPressed: _capture,
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
                        onPressed: _capture,
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppTonalButton(
                      label: 'Files',
                      height: 50,
                      fontSize: 14.5,
                      borderRadius: 15,
                      background: _chip,
                      hoverBackground: const Color(0xFF3B372F),
                      foreground: Colors.white,
                      onPressed: _capture,
                    ),
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
  final VoidCallback onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
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
    );
  }
}
