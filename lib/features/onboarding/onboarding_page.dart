import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/config/feature_flags.dart';
import '../../core/services/prefs_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/image_slot.dart';
import '../../core/widgets/stroke_icon.dart';

/// Three-slide intro. The third slide is entirely about recording marks and
/// reading a performance trend, so it follows [kShowExamMarks] — promising a
/// feature the build does not ship would be worse than one slide fewer.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _index = 0;

  static const _slides = <_Slide>[
    _Slide(
      // The design says "…homework and exam papers"; exam records are not part
      // of this build, so the promise is trimmed to what the app stores.
      title: 'Keep Schoolwork Organized',
      description: 'Save worksheets, classwork and homework in one place.',
    ),
    _Slide(
      title: 'Capture in Seconds',
      description:
          'Share an image directly from WhatsApp, Gallery or Files and save it '
          'as classwork or a worksheet.',
    ),
    _Slide(
      title: 'Track Academic Progress',
      description:
          "Record marks and easily understand your child's performance over time.",
      requiresExamMarks: true,
    ),
  ];

  List<_Slide> get _visible =>
      _slides.where((s) => kShowExamMarks || !s.requiresExamMarks).toList();

  void _next() {
    if (_index < _visible.length - 1) {
      setState(() => _index++);
    } else {
      _goToLogin();
    }
  }

  /// Recorded so a returning parent who signs out lands on Login rather than
  /// being walked through the tour again.
  void _goToLogin() {
    unawaited(PrefsService.instance.setOnboarded(true));
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final slides = _visible;
    final slide = slides[_index];
    final isLast = _index == slides.length - 1;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < slides.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            width: i == _index ? 22 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _index ? k.priFill : k.bd4,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                      ],
                    ),
                    AppIconButton(
                      onTap: _goToLogin,
                      size: 40,
                      borderRadius: 10,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: k.tx3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey(slide.title),
                      child: _SlideArtwork(slide: slide),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                slide.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                slide.description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, height: 1.55, color: k.tx3),
              ),
              const SizedBox(height: 22),
              AppFilledButton(
                label: isLast ? 'Get Started' : 'Next',
                onPressed: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.title,
    required this.description,
    this.requiresExamMarks = false,
  });

  final String title;
  final String description;
  final bool requiresExamMarks;
}

class _SlideArtwork extends StatelessWidget {
  const _SlideArtwork({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    if (slide.requiresExamMarks) return const _TrendArtwork();
    return switch (slide.title) {
      'Capture in Seconds' => const _ShareArtwork(),
      _ => const _CollageArtwork(),
    };
  }
}

/// Staggered 2×2 collage of attachment placeholders.
class _CollageArtwork extends StatelessWidget {
  const _CollageArtwork();

  @override
  Widget build(BuildContext context) {
    // "Exam paper" in the design; without exam records the closest real
    // artefact this build stores is homework.
    const captions = ['Worksheet', 'Classwork', 'Answer key', 'Homework'];
    const offsets = [0.0, 26.0, -14.0, 12.0];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final column in [0, 1])
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: column == 1 ? 12 : 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in [0, 1])
                    Padding(
                      padding: EdgeInsets.only(
                        top: offsets[column + row * 2] > 0
                            ? offsets[column + row * 2]
                            : 0,
                        bottom: row == 0 ? 12 : 0,
                      ),
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          offsets[column + row * 2] < 0
                              ? offsets[column + row * 2]
                              : 0,
                        ),
                        child: ImageSlot(
                          placeholder: captions[column + row * 2],
                          radius: 18,
                          height: 150,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Share sheet → saved as worksheet" illustration.
class _ShareArtwork extends StatelessWidget {
  const _ShareArtwork();

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: k.surf,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: k.bd),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: k.subSciC,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Image from WhatsApp',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'Share',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: k.sec,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        StrokeIcon(AppIcons.arrowDown, size: 30, color: k.tx5),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: k.priC,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: k.priFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const StrokeIcon(
                  AppIcons.plus,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Academic Diary',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: k.priInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Saved as worksheet',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: k.priInk2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Marks trend bars — only reachable while [kShowExamMarks] is on.
class _TrendArtwork extends StatelessWidget {
  const _TrendArtwork();

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    const bars = [('80%', 62.0), ('84%', 80.0), ('88%', 100.0), ('90%', 118.0)];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: k.surf,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: k.bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Mathematics',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: k.tx3,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (label, height) in bars)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: k.pri,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: height,
                            decoration: BoxDecoration(
                              color: k.priFill,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                                bottom: Radius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: k.bd),
          const SizedBox(height: 14),
          Text(
            'Steady improvement across 4 tests',
            style: TextStyle(fontSize: 13, color: k.tx3),
          ),
        ],
      ),
    );
  }
}
