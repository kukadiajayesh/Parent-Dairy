// This file is a test in every way but its directory: it runs under
// `flutter test` and legitimately uses the @visibleForTesting Firestore seam.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/app/routes.dart';
import 'package:parent_academic_diary/core/services/connectivity_service.dart';
import 'package:parent_academic_diary/core/services/prefs_service.dart';
import 'package:parent_academic_diary/core/theme/app_theme.dart';
import 'package:parent_academic_diary/data/app_state.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/auth_repository.dart';
import 'package:parent_academic_diary/features/auth/login_page.dart';
import 'package:parent_academic_diary/features/children/child_setup_page.dart';
import 'package:parent_academic_diary/features/onboarding/onboarding_page.dart';
import 'package:parent_academic_diary/features/onboarding/splash_page.dart';
import 'package:parent_academic_diary/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Not a golden test — a helper that renders real screens with the bundled
/// Figtree faces so the layout can be eyeballed. It lives outside `test/` so
/// `flutter test` does not treat the screenshots as assertions. Refresh with:
///   flutter test tool/capture_screens_test.dart --update-goldens
///
/// Screens are pumped individually rather than by walking the app: the entry
/// point now calls `Firebase.initializeApp`, which cannot run under the test
/// binding, so the state is built over an in-memory Firestore instead.
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

  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Paths.db = FakeFirebaseFirestore();
  });

  tearDown(() => Paths.db = null);

  /// A signed-in parent with one child and a few records to photograph.
  Future<void> seed(WidgetTester tester, {bool signedIn = true}) async {
    await tester.runAsync(() async {
      await PrefsService.init();
      state = AppState(
        auth: AuthRepository(
          auth: signedIn
              ? MockFirebaseAuth(
                  signedIn: true,
                  mockUser: MockUser(
                    uid: 'parent-1',
                    email: 'jayesh.patel@gmail.com',
                    displayName: 'Jayesh Patel',
                  ),
                )
              : MockFirebaseAuth(),
        ),
        connectivity: ConnectivityService.fixed(),
      );
      if (!signedIn) return;

      await state.bootstrap();
      await _settle();
      await state.saveChild(
        const Child(
          name: 'Aarav Patel',
          initials: 'AP',
          school: 'Sunrise English School',
          grade: 'Class 5',
          section: 'B',
          year: '2026–27',
        ),
      );
      await _settle(12);

      for (final (subject, title, type, day) in const [
        ('Mathematics', 'Fractions Practice', RecordType.worksheet, 23),
        ('English', 'Chapter 4 Questions', RecordType.classwork, 23),
        ('Science', 'Plants and animals — label diagram', RecordType.worksheet, 20),
        ('Hindi', 'Dictation practice', RecordType.classwork, 21),
      ]) {
        await state.saveRecord(
          DiaryRecord(
            id: '',
            academicYearId: '2026–27',
            type: type,
            subject: subject,
            title: title,
            date: DateTime(2026, 8, day),
            dueDate: type == RecordType.worksheet
                ? DateTime(2026, 8, day + 5)
                : null,
          ),
        );
      }
      await _settle(14);
    });
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.themeMode,
            onGenerateRoute: Routes.onGenerateRoute,
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  testWidgets('onboarding screens', (tester) async {
    // Never bootstrapped, so authStatus stays `unknown` and the splash holds
    // still instead of routing away mid-capture.
    await seed(tester, signedIn: false);

    await pump(tester, const SplashPage());
    await shoot(tester, '01-splash');

    await pump(tester, const OnboardingPage());
    await shoot(tester, '02-onboarding');

    await tester.tap(find.text('Next'));
    await shoot(tester, '03-onboarding-2');

    await pump(tester, const LoginPage());
    await shoot(tester, '04-login');

    await pump(tester, const ChildSetupPage());
    await shoot(tester, '05-child-setup');
  });

  testWidgets('main screens', (tester) async {
    await seed(tester);

    await pump(tester, const MainShell());
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

Future<void> _settle([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
