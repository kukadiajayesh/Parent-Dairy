import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A tap surface that expresses a press the way the host platform does, and is
/// otherwise a drop-in for [InkWell].
///
/// The two platforms disagree about what a press looks like, and matching each
/// one is what makes a screen feel native rather than ported:
///
/// * **Android** (and the desktop targets that follow Material) keeps the ink
///   ripple, plus the click sound and haptic the platform plays for a tap —
///   [InkWell] already forwards both through `enableFeedback`.
/// * **iOS / macOS** get no ripple, because iOS has never had one. The target
///   dips instead: a small scale-down and a fade, snapping down quickly and
///   easing back a little slower, the way a Cupertino control behaves.
///
/// Set [overlay] when the child paints something opaque — an image, a rendered
/// PDF page. Ink is drawn onto the [Material] *below* the child, so an opaque
/// child hides the ripple completely; [overlay] lifts the ink surface above
/// the content instead, where it is visible.
class AppInkWell extends StatefulWidget {
  const AppInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.customBorder,
    this.hoverColor,
    this.splashColor,
    this.highlightColor,
    this.overlay = false,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;
  final Color? hoverColor;
  final Color? splashColor;
  final Color? highlightColor;

  /// Paint the ink above the child rather than on the Material beneath it.
  /// Needed whenever the child is opaque.
  final bool overlay;

  /// Fire a selection haptic on tap. For controls that pick a value — chips,
  /// toggles, segmented choices. Plain buttons and navigation leave this off.
  ///
  /// Only takes effect on iOS: on Android [InkWell.enableFeedback] already
  /// plays the platform's own click sound and buzz, and firing a second one
  /// would double it.
  final bool haptic;

  @override
  State<AppInkWell> createState() => _AppInkWellState();
}

class _AppInkWellState extends State<AppInkWell> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  void _handleTap({required bool cupertino}) {
    if (widget.haptic && cupertino) HapticFeedback.selectionClick();
    widget.onTap!.call();
  }

  @override
  Widget build(BuildContext context) {
    final cupertino = _isCupertino(context);
    final enabled = widget.onTap != null || widget.onLongPress != null;

    // A PressDip above us wraps the Material that actually paints this
    // surface, so it can dip the whole thing; we just feed it the press.
    final host = cupertino && enabled ? _PressDipScope.maybeOf(context) : null;
    final down = cupertino && enabled && _pressed;

    Widget content = widget.child;
    if (cupertino) {
      // Whether or not a host is running the effect, shield anything nested
      // below from adopting it — an inner button dips itself, not the card.
      content = _PressDipScope(setPressed: null, child: content);
      if (host == null) content = _dip(pressed: down, child: content);
    }

    Widget ink({required Widget child}) => InkWell(
      onTap: widget.onTap == null
          ? null
          : () => _handleTap(cupertino: cupertino),
      onLongPress: widget.onLongPress,
      borderRadius: widget.borderRadius,
      customBorder: widget.customBorder,
      hoverColor: widget.hoverColor,
      // On iOS the dip is the entire effect, so every ink colour is silenced
      // rather than merely tinted.
      splashFactory: cupertino ? NoSplash.splashFactory : null,
      splashColor: cupertino ? Colors.transparent : widget.splashColor,
      highlightColor: cupertino ? Colors.transparent : widget.highlightColor,
      onHighlightChanged: !cupertino ? null : (host ?? _setPressed),
      child: child,
    );

    if (!widget.overlay) return ink(child: content);

    return Stack(
      children: [
        content,
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: ink(child: const SizedBox.expand()),
          ),
        ),
      ],
    );
  }
}

/// Carries the press sink an [AppInkWell] should report to, when a [PressDip]
/// above it has offered to run the effect on its behalf.
class _PressDipScope extends InheritedWidget {
  const _PressDipScope({required this.setPressed, required super.child});

  /// Null marks a barrier: an [AppInkWell] publishes one over its own subtree
  /// so a nested tap target dips itself rather than the card around it.
  final ValueChanged<bool>? setPressed;

  static ValueChanged<bool>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PressDipScope>()?.setPressed;

  @override
  bool updateShouldNotify(_PressDipScope oldWidget) =>
      setPressed != oldWidget.setPressed;
}

/// Lifts a descendant [AppInkWell]'s iOS press dip onto the surface that
/// paints it.
///
/// An ink well has to live inside a [Material], so left alone it can only
/// animate its own child: pressing a card would shrink the label while the
/// card sat still. Wrap the [Material] in a [PressDip] and the fill, border,
/// shadow and content all move together, which is what a press looks like on
/// iOS. On Material platforms this is a plain passthrough — the ripple is the
/// effect there.
class PressDip extends StatefulWidget {
  const PressDip({super.key, required this.child});

  final Widget child;

  @override
  State<PressDip> createState() => _PressDipState();
}

class _PressDipState extends State<PressDip> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scope = _PressDipScope(setPressed: _setPressed, child: widget.child);
    if (!_isCupertino(context)) return scope;
    return _dip(pressed: _pressed, child: scope);
  }
}

bool _isCupertino(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => true,
  _ => false,
};

// Tuned against CupertinoButton: down fast enough to feel attached to the
// finger, back slowly enough to be seen on a tap that is over in 60ms.
const _pressedScale = 0.97;
const _pressedOpacity = 0.62;
const _downDuration = Duration(milliseconds: 90);
const _upDuration = Duration(milliseconds: 220);

Widget _dip({required bool pressed, required Widget child}) => AnimatedScale(
  scale: pressed ? _pressedScale : 1,
  duration: pressed ? _downDuration : _upDuration,
  curve: pressed ? Curves.easeOut : Curves.easeOutCubic,
  child: AnimatedOpacity(
    opacity: pressed ? _pressedOpacity : 1,
    duration: pressed ? _downDuration : _upDuration,
    curve: Curves.easeOut,
    child: child,
  ),
);
