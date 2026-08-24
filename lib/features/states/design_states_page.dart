import 'package:flutter/material.dart';

import '../../core/config/feature_flags.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../data/app_state.dart';

/// Gallery of the empty / loading / error states the design catalogues on its
/// last three screens. The states themselves are the reusable widgets in
/// `core/widgets/states.dart`, used by the real screens; this page exists so
/// every variant in the design file stays reviewable in the running app.
class DesignStatesPage extends StatefulWidget {
  const DesignStatesPage({super.key});

  @override
  State<DesignStatesPage> createState() => _DesignStatesPageState();
}

class _DesignStatesPageState extends State<DesignStatesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Design states'),
            ),
            TabBar(
              controller: _tabs,
              labelColor: k.priInk,
              unselectedLabelColor: k.tx3,
              indicatorColor: k.priFill,
              dividerColor: k.bd2,
              labelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(text: 'Empty'),
                Tab(text: 'Loading'),
                Tab(text: 'Errors'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  _EmptyGallery(),
                  _LoadingGallery(),
                  _ErrorGallery(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGallery extends StatefulWidget {
  const _EmptyGallery();

  @override
  State<_EmptyGallery> createState() => _EmptyGalleryState();
}

class _EmptyGalleryState extends State<_EmptyGallery> {
  static const _copy = <String, (String, String, String)>{
    'Worksheets': (
      'No worksheets yet',
      'Your worksheets will appear here.',
      'Add Worksheet',
    ),
    'Classwork': (
      'No classwork yet',
      "Start saving your child's classwork photos.",
      'Add Classwork',
    ),
    'Exams': ('No exams yet', 'No exams added yet.', 'Add Exam'),
    'Marks': (
      'No marks yet',
      'Add exam marks to start tracking performance.',
      'Add Marks',
    ),
    'Timeline': (
      'Nothing here yet',
      "Your child's academic journey will appear here.",
      'Add First Record',
    ),
  };

  String _kind = 'Worksheets';

  List<String> get _kinds => _copy.keys
      .where((k) => kShowExamMarks || (k != 'Exams' && k != 'Marks'))
      .toList();

  @override
  Widget build(BuildContext context) {
    final (title, description, cta) = _copy[_kind]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        _KindChips(
          kinds: _kinds,
          selected: _kind,
          onSelected: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: 16),
        EmptyStateView(
          title: title,
          description: description,
          actionLabel: cta,
          onAction: () {},
        ),
      ],
    );
  }
}

class _LoadingGallery extends StatefulWidget {
  const _LoadingGallery();

  @override
  State<_LoadingGallery> createState() => _LoadingGalleryState();
}

class _LoadingGalleryState extends State<_LoadingGallery> {
  String _kind = 'Dashboard';

  List<String> get _kinds => [
        'Dashboard',
        'Timeline',
        if (kShowExamMarks) 'Marks',
        'Subject',
        'Lists',
      ];

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        _KindChips(
          kinds: _kinds,
          selected: _kind,
          onSelected: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: 16),
        Skeletons(child: _skeletonFor(_kind)),
        const SizedBox(height: 16),
        Text(
          '$_kind skeleton · no blank screens while loading',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: k.tx4),
        ),
      ],
    );
  }

  Widget _skeletonFor(String kind) => switch (kind) {
        'Timeline' => const _TimelineSkeleton(),
        'Subject' => const _SubjectSkeleton(),
        'Lists' => const _ListSkeleton(),
        'Marks' => const _MarksSkeleton(),
        _ => const _DashboardSkeleton(),
      };
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.t.surf2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              const SkeletonBox(
                width: 40,
                height: 40,
                radius: 999,
                tone: SkeletonTone.solid,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 80, height: 12, tone: SkeletonTone.solid),
                  SizedBox(height: 6),
                  SkeletonBox(width: 130, height: 10, tone: SkeletonTone.soft),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2,
          children: const [
            SkeletonBox(height: 86, radius: 18),
            SkeletonBox(height: 86, radius: 18),
            SkeletonBox(height: 86, radius: 18),
            SkeletonBox(height: 86, radius: 18),
          ],
        ),
        const SizedBox(height: 14),
        const SkeletonBox(height: 76, radius: 20),
        const SizedBox(height: 14),
        // Stands in for the home screen's pending-worksheet strip, which
        // scrolls horizontally. Two 190dp cards plus their gap are wider than
        // any phone, so a plain Row overflows on every device — this clips the
        // second card at the edge exactly as the real strip does.
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            // A loading placeholder should not be draggable.
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              SkeletonBox(width: 190, height: 112, radius: 18),
              SizedBox(width: 12),
              SkeletonBox(width: 190, height: 112, radius: 18),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineSkeleton extends StatelessWidget {
  const _TimelineSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget card(double lastWidthFactor, {bool withPill = true}) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.t.surf2,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(
                width: 88,
                height: 92,
                radius: 14,
                tone: SkeletonTone.solid,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    const SkeletonBox(
                      width: 96,
                      height: 10,
                      tone: SkeletonTone.solid,
                    ),
                    const SizedBox(height: 8),
                    const SkeletonBox(height: 14, tone: SkeletonTone.solid),
                    const SizedBox(height: 8),
                    FractionallySizedBox(
                      widthFactor: lastWidthFactor,
                      child: const SkeletonBox(
                        height: 14,
                        tone: SkeletonTone.soft,
                      ),
                    ),
                    if (withPill) ...[
                      const SizedBox(height: 8),
                      const SkeletonBox(
                        width: 120,
                        height: 20,
                        radius: 8,
                        tone: SkeletonTone.soft,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SkeletonBox(width: 110, height: 11, tone: SkeletonTone.solid),
        const SizedBox(height: 14),
        card(.7),
        const SizedBox(height: 14),
        card(.6, withPill: false),
      ],
    );
  }
}

class _SubjectSkeleton extends StatelessWidget {
  const _SubjectSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        SkeletonBox(height: 92, radius: 20),
        SizedBox(height: 12),
        Row(
          children: [
            SkeletonBox(width: 88, height: 34, radius: 999),
            SizedBox(width: 8),
            SkeletonBox(width: 96, height: 34, radius: 999),
            SizedBox(width: 8),
            SkeletonBox(width: 84, height: 34, radius: 999),
          ],
        ),
        SizedBox(height: 12),
        SkeletonBox(height: 150, radius: 20),
        SizedBox(height: 12),
        SkeletonBox(height: 64, radius: 16),
      ],
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        SkeletonBox(height: 120, radius: 20),
        SizedBox(height: 12),
        SkeletonBox(height: 120, radius: 20),
        SizedBox(height: 12),
        SkeletonBox(height: 120, radius: 20),
      ],
    );
  }
}

class _MarksSkeleton extends StatelessWidget {
  const _MarksSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        SkeletonBox(height: 88, radius: 20),
        SizedBox(height: 12),
        SkeletonBox(height: 62, radius: 16),
        SizedBox(height: 12),
        SkeletonBox(height: 62, radius: 16),
        SizedBox(height: 12),
        SkeletonBox(height: 62, radius: 16),
      ],
    );
  }
}

class _ErrorGallery extends StatefulWidget {
  const _ErrorGallery();

  @override
  State<_ErrorGallery> createState() => _ErrorGalleryState();
}

class _ErrorGalleryState extends State<_ErrorGallery> {
  static const _copy = <String, (String, String, String)>{
    'Internet unavailable': (
      'No internet connection',
      'Check your connection and try again. Saved records are still available '
          'offline.',
      'Retry',
    ),
    'Firebase unavailable': (
      "Can't reach the server",
      'We could not connect to your diary right now. Please try again in a '
          'moment.',
      'Retry',
    ),
    'Upload failed': (
      'Upload failed',
      "Your image couldn't be uploaded. Check your internet connection and try "
          'again.',
      'Retry',
    ),
    'Authentication failed': (
      'Sign-in failed',
      'Google sign-in did not complete. Please try signing in again.',
      'Try again',
    ),
    'File too large': (
      'File too large',
      'This file is over 20 MB. Try a smaller photo or compress the PDF.',
      'Choose another',
    ),
    'Unsupported file': (
      'Unsupported file',
      'Only images and PDF files can be saved as attachments.',
      'Choose another',
    ),
    'Permission denied': (
      'Permission needed',
      'Allow photo access so you can attach worksheets and classwork.',
      'Open settings',
    ),
  };

  String _kind = 'Upload failed';

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final (title, description, cta) = _copy[_kind]!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in _copy.keys)
              AppChip(
                label: kind,
                selected: _kind == kind,
                fontSize: 12.5,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                selectedBackground: k.errC,
                selectedBorder: k.err,
                selectedForeground: k.errInk,
                onTap: () => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: 16),
        ErrorStateView(
          title: title,
          description: description,
          actionLabel: cta,
          onAction: () {},
          onCancel: () {},
        ),
        const SizedBox(height: 16),
        const InlineErrorBanner(
          title: 'Inline variant',
          description: 'Shown above the form when a save fails.',
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final state = AppScope.of(context);
            return OfflineBanner(onDismiss: state.toggleOffline);
          },
        ),
      ],
    );
  }
}

class _KindChips extends StatelessWidget {
  const _KindChips({
    required this.kinds,
    required this.selected,
    required this.onSelected,
  });

  final List<String> kinds;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in kinds)
          AppChip(
            label: kind,
            selected: kind == selected,
            fontSize: 12.5,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            selectedBackground: k.priC,
            selectedBorder: k.priBd,
            selectedForeground: k.priInk,
            onTap: () => onSelected(kind),
          ),
      ],
    );
  }
}
