import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/widgets/pressable.dart';

const _target = Key('target');

Widget _host({required TargetPlatform platform, VoidCallback? onTap}) {
  return MaterialApp(
    theme: ThemeData(platform: platform),
    home: Scaffold(
      body: Center(
        child: Material(
          child: AppInkWell(
            onTap: onTap,
            child: const SizedBox(
              key: _target,
              width: 120,
              height: 48,
              child: Text('Tap'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// How wide the target actually paints. Layout size never changes — a press
/// scales the child through a transform — so comparing the painted rect
/// against the laid-out size is what tells us the dip reached the screen.
double _paintedWidth(WidgetTester tester) =>
    tester.getRect(find.byKey(_target)).width;

double _layoutWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(_target)).width;

/// Presses, then settles both the tap recogniser's deadline and the implicit
/// animation that follows it.
Future<TestGesture> _pressAndSettle(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_target)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(milliseconds: 150));
  return gesture;
}

void main() {
  testWidgets('iOS dips the target instead of rippling', (tester) async {
    await tester.pumpWidget(_host(platform: TargetPlatform.iOS, onTap: () {}));
    expect(_paintedWidth(tester), _layoutWidth(tester));

    final gesture = await _pressAndSettle(tester);

    expect(_paintedWidth(tester), lessThan(_layoutWidth(tester)));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byType(AppInkWell),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      lessThan(1),
    );
    // No ink is drawn: iOS has never had a ripple.
    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.splashFactory, NoSplash.splashFactory);
    expect(inkWell.splashColor, Colors.transparent);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_paintedWidth(tester), _layoutWidth(tester));
  });

  testWidgets('Android keeps the ripple and does not dip', (tester) async {
    await tester.pumpWidget(
      _host(platform: TargetPlatform.android, onTap: () {}),
    );

    // No Cupertino press wrapper is inserted at all on Material platforms.
    expect(
      find.descendant(
        of: find.byType(AppInkWell),
        matching: find.byType(AnimatedScale),
      ),
      findsNothing,
    );

    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.splashFactory, isNull, reason: 'theme ripple is kept');
    expect(inkWell.onHighlightChanged, isNull);

    final gesture = await _pressAndSettle(tester);
    expect(_paintedWidth(tester), _layoutWidth(tester));
    await gesture.up();
  });

  testWidgets('a disabled target never dips', (tester) async {
    await tester.pumpWidget(_host(platform: TargetPlatform.iOS));

    final gesture = await _pressAndSettle(tester);
    expect(_paintedWidth(tester), _layoutWidth(tester));
    await gesture.up();
  });

  testWidgets('overlay puts the ink surface above the content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 80,
              height: 80,
              child: AppInkWell(
                onTap: () {},
                overlay: true,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );

    final stack = find.descendant(
      of: find.byType(AppInkWell),
      matching: find.byType(Stack),
    );
    expect(stack, findsOneWidget);
    // The ink rides in a Positioned.fill layer painted after the content,
    // rather than on a Material underneath it where an opaque child would
    // hide it.
    expect(
      find.descendant(of: stack, matching: find.byType(Positioned)),
      findsOneWidget,
    );
    expect(find.byType(InkWell), findsOneWidget);
    await tester.tap(find.byType(AppInkWell));
  });

  testWidgets('PressDip dips the surface, not just the content', (
    tester,
  ) async {
    const surface = Key('surface');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Center(
            child: PressDip(
              child: Material(
                key: surface,
                color: Colors.amber,
                child: AppInkWell(
                  onTap: () {},
                  child: const SizedBox(
                    key: _target,
                    width: 120,
                    height: 48,
                    child: Text('Tap'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    double painted() => tester.getRect(find.byKey(surface)).width;
    final resting = painted();

    final gesture = await _pressAndSettle(tester);
    expect(painted(), lessThan(resting));
    // The ink well hands the effect up rather than running a second one of
    // its own inside the surface.
    expect(
      find.descendant(
        of: find.byType(AppInkWell),
        matching: find.byType(AnimatedScale),
      ),
      findsNothing,
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(painted(), resting);
  });

  testWidgets('a nested tap target dips itself, not the card around it', (
    tester,
  ) async {
    const card = Key('card');
    const inner = Key('inner');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Center(
            child: PressDip(
              child: Material(
                key: card,
                color: Colors.amber,
                child: AppInkWell(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AppInkWell(
                      onTap: () {},
                      child: const SizedBox(key: inner, width: 40, height: 40),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final cardWidth = tester.getRect(find.byKey(card)).width;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(inner)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));

    expect(tester.getRect(find.byKey(card)).width, cardWidth);
    expect(
      tester.getRect(find.byKey(inner)).width,
      lessThan(tester.getSize(find.byKey(inner)).width),
    );

    await gesture.up();
  });
}
