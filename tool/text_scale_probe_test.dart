// Audit probe, not a regression test: pumps the main screens at large text
// sizes and in both themes, and prints every layout overflow it meets instead
// of failing on the first. Run with:
//   flutter test tool/text_scale_probe_test.dart
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
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
import 'package:parent_academic_diary/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;
  final findings = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Paths.db = FakeFirebaseFirestore();
  });

  tearDown(() {
    state.dispose();
    Paths.db = null;
  });

  tearDownAll(() {
    print('\n==== overflow findings (${findings.length}) ====');
    for (final f in findings) {
      print(f);
    }
  });

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
      for (final (type, subject, title, day) in const [
        (RecordType.worksheet, 'Mathematics', 'Fractions Practice', 23),
        (RecordType.classwork, 'English', 'Chapter 4 Questions', 23),
        (RecordType.worksheet, 'Science', 'Plants and Animals', 20),
      ]) {
        await state.saveRecord(
          DiaryRecord(
            id: '',
            academicYearId: '2026–27',
            type: type,
            subject: subject,
            title: title,
            chapters: const ['Chapter 4'],
            date: DateTime(2026, 8, day),
            dueDate: type == RecordType.worksheet
                ? DateTime(2026, 8, day + 5)
                : null,
          ),
        );
      }
      await state.saveResult(
        ExamResult(
          id: '',
          childId: '',
          academicYearId: '',
          examLabel: 'Unit Test 1',
          date: DateTime(2026, 7, 10),
          scores: const [
            SubjectScore(subject: 'Mathematics', marks: 48, maxMarks: 100),
            SubjectScore(subject: 'English', marks: 70, maxMarks: 100),
            SubjectScore(subject: 'Science', marks: 86, maxMarks: 100),
          ],
        ),
      );
      await _settle(14);
    });
  }

  /// Pumps [home] with the given scale and theme and records every overflow
  /// raised while [drive] runs.
  Future<void> probe(
    WidgetTester tester, {
    required String screen,
    required Widget home,
    required double scale,
    required Brightness brightness,
    Future<void> Function()? drive,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final label =
        '$screen @${scale}x ${brightness == Brightness.dark ? 'dark' : 'light'}';
    final original = FlutterError.onError;
    final seen = <String>{};
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed')) {
        // One line: which widget and by how much.
        final firstLine = text.split('\n').first;
        // The overflow's own stack is framework-only; the app widget that
        // caused it is named in the diagnostics ("relevant error-causing
        // widget was ... file:///…/lib/x.dart:12:3").
        final where = RegExp(r'lib/[\w/]+\.dart:\d+')
            .firstMatch(details.toString())
            ?.group(0);
        final entry = '$label: $firstLine ← $where';
        if (seen.add(firstLine)) findings.add(entry);
        return;
      }
      original?.call(details);
    };
    try {
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.system,
            onGenerateRoute: Routes.onGenerateRoute,
            home: home,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (drive != null) await drive();
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = original;
      // Errors already reported by the framework would fail the test; the
      // probe swallowed them into findings, so clear the binding's record.
      tester.binding.takeException();
    }
  }

  for (final scale in const [1.3, 2.0]) {
    for (final brightness in const [Brightness.light, Brightness.dark]) {
      testWidgets('signed-out screens @$scale $brightness', (tester) async {
        await seed(tester, signedIn: false);
        await probe(
          tester,
          screen: 'Onboarding',
          home: const OnboardingPage(),
          scale: scale,
          brightness: brightness,
        );
        await probe(
          tester,
          screen: 'Login',
          home: const LoginPage(),
          scale: scale,
          brightness: brightness,
        );
        await probe(
          tester,
          screen: 'Child setup',
          home: const ChildSetupPage(),
          scale: scale,
          brightness: brightness,
        );
      });

      testWidgets('shell tabs and forms @$scale $brightness', (tester) async {
        await seed(tester);
        Future<void> tapText(String text, {bool last = false}) async {
          final all = find.text(text);
          if (all.evaluate().isEmpty) {
            findings.add('probe: "$text" not found at @${scale}x — skipped');
            return;
          }
          final f = last ? all.last : all.first;
          await tester.ensureVisible(f);
          await tester.tap(f, warnIfMissed: false);
          await tester.pumpAndSettle();
        }

        await probe(
          tester,
          screen: 'Home',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
        );
        await probe(
          tester,
          screen: 'Timeline',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () => tapText('Timeline'),
        );
        await probe(
          tester,
          screen: 'Timeline filter sheet',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () async {
            await tapText('Timeline');
            await tester.tap(find.byTooltip('Filter').first);
            await tester.pumpAndSettle();
          },
        );
        await probe(
          tester,
          screen: 'Performance',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () => tapText('Performance'),
        );
        await probe(
          tester,
          screen: 'More',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () => tapText('More'),
        );
        await probe(
          tester,
          screen: 'Worksheet detail',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () async {
            await tapText('Timeline');
            state.setFilter(const TimelineFilter(date: 'All'));
            await tester.pumpAndSettle();
            await tapText('Worksheet');
          },
        );
        await probe(
          tester,
          screen: 'Add worksheet',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () => tapText('Worksheet'),
        );
        await probe(
          tester,
          screen: 'Add classwork',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () => tapText('Classwork'),
        );
        await probe(
          tester,
          screen: 'Add exam',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () => tapText('Exam'),
        );
        await probe(
          tester,
          screen: 'Search',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () async {
            await tester.tap(find.byTooltip('Search').first);
            await tester.pumpAndSettle();
          },
        );
        await probe(
          tester,
          screen: 'Result detail',
          home: const MainShell(),
          scale: scale,
          brightness: brightness,
          drive: () async {
            await tapText('Performance');
            await tapText('Unit Test 1', last: true);
          },
        );
        for (final row in const [
          'Manage children',
          'Academic years',
          'Subjects',
          'Grade scale',
          'Notices',
          'Gemini AI',
          'Empty, loading & error states',
        ]) {
          await probe(
            tester,
            screen: 'More > $row',
            home: const MainShell(),
            scale: scale,
            brightness: brightness,
            drive: () async {
              await tapText('More');
              await tapText(row);
            },
          );
        }
      });
    }
  }
}

Future<void> _settle([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
