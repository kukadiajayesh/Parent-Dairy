import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/app/app.dart';
import 'package:parent_academic_diary/core/config/feature_flags.dart';

/// Walks the whole flow the design describes and asserts nothing throws while
/// every screen builds. Widget errors surface as test failures here rather than
/// as a red screen on device.
void main() {
  setUp(() {
    // A tall surface so long forms lay out without overflow noise.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ParentAcademicDiaryApp());
    await tester.pumpAndSettle();
  }

  testWidgets('splash → onboarding → login → child setup → home', (tester) async {
    await pumpApp(tester);

    expect(find.text('Parent Academic Diary'), findsOneWidget);
    expect(find.text('Tap to continue'), findsOneWidget);

    await tester.tap(find.text('Tap to continue'));
    await tester.pumpAndSettle();
    expect(find.text('Keep Schoolwork Organized'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Capture in Seconds'), findsOneWidget);

    // With exam/marks off the second slide is the last one.
    expect(find.text('Get Started'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text("Let's add your child"), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Good morning,'), findsOneWidget);
    expect(find.text('QUICK ACTIONS'), findsOneWidget);
  });

  testWidgets('bottom navigation has no Performance tab', (tester) async {
    await pumpApp(tester);
    await _skipToHome(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Performance'), findsNothing);
    expect(kShowExamMarks, isFalse);
  });

  testWidgets('home hides every exam and marks surface', (tester) async {
    await pumpApp(tester);
    await _skipToHome(tester);

    expect(find.text('Worksheet'), findsOneWidget);
    expect(find.text('Classwork'), findsOneWidget);
    expect(find.text('Exam'), findsNothing);
    expect(find.text('Marks'), findsNothing);
    expect(find.text('LATEST MARKS'), findsNothing);
  });

  testWidgets('add sheet offers worksheet and classwork only', (tester) async {
    await pumpApp(tester);
    await _skipToHome(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Add to diary'), findsOneWidget);
    expect(find.text('From Image'), findsOneWidget);
    expect(find.text('Save a worksheet or homework'), findsOneWidget);
    expect(find.text('Save classwork photos'), findsOneWidget);
    expect(find.text('Add an exam/test'), findsNothing);
    expect(find.text('Record exam marks'), findsNothing);
  });

  testWidgets('saving a worksheet puts it on the timeline', (tester) async {
    await pumpApp(tester);
    await _skipToHome(tester);

    await tester.tap(find.text('Worksheet').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Worksheet'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Long division set 2');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Worksheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.text('Long division set 2'), findsOneWidget);
  });

  testWidgets('timeline filter sheet excludes exam and marks types',
      (tester) async {
    await pumpApp(tester);
    await _skipToHome(tester);

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Filter timeline'), findsOneWidget);
    // The timeline behind the sheet also labels its cards, so these are
    // "at least one" — the assertion that matters is the two absences.
    expect(find.text('Worksheet'), findsWidgets);
    expect(find.text('Classwork'), findsWidgets);
    expect(find.text('Exam'), findsNothing);
    expect(find.text('Marks'), findsNothing);
  });

  testWidgets('more screen renders and toggles dark theme', (tester) async {
    await pumpApp(tester);
    await _skipToHome(tester);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Jayesh Patel'), findsOneWidget);
    expect(find.text('Manage children'), findsOneWidget);
    expect(find.text('Academic years'), findsOneWidget);
    expect(find.text('Subjects'), findsOneWidget);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);

    // Everything must still build under the dark palette.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('QUICK ACTIONS'), findsOneWidget);
  });

  testWidgets('worksheet detail opens and marks completed', (tester) async {
    await pumpApp(tester);
    await _skipToHome(tester);

    await tester.tap(find.text('Fractions Practice').first);
    await tester.pumpAndSettle();

    expect(find.text('Mark completed'), findsOneWidget);
    await tester.tap(find.text('Mark completed'));
    await tester.pumpAndSettle();
    expect(find.text('Mark pending'), findsOneWidget);
  });

  testWidgets('settings destinations all build', (tester) async {
    await pumpApp(tester);
    await _skipToHome(tester);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    for (final (row, heading) in const [
      ('Manage children', 'Manage Children'),
      ('Academic years', 'Academic Years'),
      ('Subjects', 'Manage Subjects'),
      ('Empty, loading & error states', 'Design states'),
    ]) {
      await tester.scrollUntilVisible(find.text(row), 200);
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(find.text(heading), findsOneWidget, reason: 'opening $row');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}

/// Fast-forwards past splash, onboarding, login and child setup.
Future<void> _skipToHome(WidgetTester tester) async {
  await tester.tap(find.text('Tap to continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue with Google'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}
