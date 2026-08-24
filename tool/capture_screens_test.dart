import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/app/app.dart';

/// Not a golden test — a helper that renders real screens with the bundled
/// Figtree faces so the layout can be eyeballed. It lives outside `test/` so
/// `flutter test` does not treat the screenshots as assertions. Refresh with:
///   flutter test tool/capture_screens_test.dart --update-goldens
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Figtree');
    for (final weight in const [
      'Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold',
    ]) {
      loader.addFont(
        File('assets/fonts/Figtree-$weight.ttf')
            .readAsBytes()
            .then((b) => ByteData.view(b.buffer)),
      );
    }
    await loader.load();
  });

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  testWidgets('capture', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ParentAcademicDiaryApp());
    await tester.pumpAndSettle();
    await shoot(tester, '01-splash');

    await tester.tap(find.text('Tap to continue'));
    await shoot(tester, '02-onboarding');

    await tester.tap(find.text('Next'));
    await shoot(tester, '03-onboarding-2');

    await tester.tap(find.text('Get Started'));
    await shoot(tester, '04-login');

    await tester.tap(find.text('Continue with Google'));
    await shoot(tester, '05-child-setup');

    await tester.tap(find.text('Continue'));
    await shoot(tester, '06-home');

    await tester.tap(find.text('Timeline'));
    await shoot(tester, '07-timeline');

    await tester.tap(find.text('Fractions Practice').first);
    await shoot(tester, '08-worksheet-detail');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await shoot(tester, '09-more');

    await tester.tap(find.text('Theme'));
    await shoot(tester, '10-more-dark');

    await tester.tap(find.text('Home'));
    await shoot(tester, '11-home-dark');

    await tester.tap(find.text('Worksheet').first);
    await shoot(tester, '12-add-worksheet-dark');
  });
}
