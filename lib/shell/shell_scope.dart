import 'package:flutter/material.dart';

/// Lets a screen inside a tab ask the shell to switch tabs — used by
/// "View all" links that point at a different tab's root.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.goToTab, required super.child});

  final void Function(String tabId) goToTab;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}
