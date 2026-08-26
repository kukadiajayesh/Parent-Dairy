import 'package:flutter/material.dart';

import '../core/config/feature_flags.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_icons.dart';
import '../core/widgets/stroke_icon.dart';
import '../features/home/home_page.dart';
import '../features/settings/more_page.dart';
import '../features/timeline/timeline_page.dart';
import 'shell_scope.dart';

/// The three-tab frame the design keeps behind most screens. Each tab owns a
/// nested [Navigator] so pushing "Worksheets" or "Manage children" keeps the
/// bottom bar, exactly as the prototype's `tabOf` mapping describes. Screens on
/// the design's `chromeless` list are pushed on the root navigator instead.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _tabs = <_TabSpec>[
    _TabSpec('home', 'Home', AppIcons.navHome),
    _TabSpec('timeline', 'Timeline', AppIcons.navTimeline),
    // The design's "Performance" tab sits between Timeline and More and is
    // gated on showExamMarks; with the flag off it is not built at all.
    _TabSpec('more', 'More', AppIcons.navMore),
  ];

  final _navigatorKeys = List.generate(
    _tabs.length,
    (_) => GlobalKey<NavigatorState>(),
  );

  int _index = 0;

  NavigatorState get _currentNavigator => _navigatorKeys[_index].currentState!;

  void _onTabTapped(int index) {
    if (index == _index) {
      // Tapping the active tab returns to its root, the usual mobile idiom.
      _currentNavigator.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _index = index);
  }

  Widget _rootFor(int index) => switch (_tabs[index].id) {
    'home' => const HomePage(),
    'timeline' => const TimelinePage(),
    _ => const MorePage(),
  };

  @override
  Widget build(BuildContext context) {
    final k = context.t;

    return ShellScope(
      goToTab: (id) {
        final index = _tabs.indexWhere((t) => t.id == id);
        if (index != -1) _onTabTapped(index);
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _currentNavigator.maybePop()) return;
          if (_index != 0) {
            setState(() => _index = 0);
          }
        },
        child: Scaffold(
          backgroundColor: k.bg,
          body: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Navigator(
                  key: _navigatorKeys[i],
                  onGenerateRoute: (settings) => MaterialPageRoute<void>(
                    builder: (_) => _rootFor(i),
                    settings: settings,
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _BottomBar(
            tabs: _tabs,
            index: _index,
            onTap: _onTabTapped,
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.id, this.label, this.icon);
  final String id;
  final String label;
  final SvgIcon icon;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tabs,
    required this.index,
    required this.onTap,
  });

  final List<_TabSpec> tabs;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      decoration: BoxDecoration(
        color: k.bg,
        border: Border(top: BorderSide(color: k.bd2)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _NavItem(
                      spec: tabs[i],
                      selected: i == index,
                      onTap: () => onTap(i),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final color = selected ? k.priInk : k.tx3;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? k.priC : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: StrokeIcon(
                spec.icon,
                size: 22,
                color: color,
                strokeWidth: selected ? 2.3 : 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              spec.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kept next to the shell so the flag's effect on navigation is visible here.
const bool showsPerformanceTab = kShowExamMarks;
