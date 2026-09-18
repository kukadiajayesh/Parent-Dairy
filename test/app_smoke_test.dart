import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/app/routes.dart';
import 'package:parent_academic_diary/core/config/feature_flags.dart';
import 'package:parent_academic_diary/core/services/connectivity_service.dart';
import 'package:parent_academic_diary/core/services/prefs_service.dart';
import 'package:parent_academic_diary/core/theme/app_theme.dart';
import 'package:parent_academic_diary/core/widgets/image_slot.dart';
import 'package:parent_academic_diary/core/widgets/layout.dart';
import 'package:parent_academic_diary/data/app_state.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/auth_repository.dart';
import 'package:parent_academic_diary/features/performance/performance_page.dart';
import 'package:parent_academic_diary/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real screens against fake Firebase, so widget errors surface here
/// rather than as a red screen on device.
///
/// The app's own entry point cannot be pumped any more — it calls
/// `Firebase.initializeApp` — so the shell is mounted directly over a signed-in
/// [AppState] backed by an in-memory Firestore.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Paths.db = db;
  });

  /// Builds a signed-in state with one child and two records.
  ///
  /// Runs inside [WidgetTester.runAsync] because `testWidgets` fakes the clock:
  /// the Firestore streams need real elapsed time to deliver, and a plain
  /// `await Future.delayed` in a widget test never completes.
  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      await PrefsService.init();

      state = AppState(
        auth: AuthRepository(
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(
              uid: 'parent-1',
              email: 'jayesh@example.com',
              displayName: 'Jayesh Patel',
            ),
          ),
        ),
        connectivity: ConnectivityService.fixed(),
      );
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

      await state.saveRecord(
        DiaryRecord(
          id: '',
          academicYearId: '2026–27',
          type: RecordType.worksheet,
          subject: 'Mathematics',
          title: 'Fractions Practice',
          date: DateTime(2026, 8, 23),
          dueDate: DateTime(2026, 8, 28),
        ),
      );
      await state.saveRecord(
        DiaryRecord(
          id: '',
          academicYearId: '2026–27',
          type: RecordType.classwork,
          subject: 'English',
          title: 'Chapter 4 Questions',
          date: DateTime(2026, 8, 23),
        ),
      );
      await _settle(12);
    });
  }

  tearDown(() {
    state.dispose();
    Paths.db = null;
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await seed(tester);
    // 1080 physical at DPR 2.625 is 411.4dp — the design's 412dp target and a
    // real phone width. A more generous surface hides horizontal overflows:
    // at the 432dp this used to use, the dashboard skeleton's 190 + 12 + 190
    // strip fit exactly and the bug was invisible.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.themeMode,
            onGenerateRoute: Routes.onGenerateRoute,
            home: const MainShell(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home renders the signed-in parent and their records', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.textContaining('Jayesh'), findsWidgets);
    expect(find.text('QUICK ACTIONS'), findsOneWidget);
    expect(find.text('Fractions Practice'), findsWidgets);
  });

  testWidgets('bottom navigation carries the Performance tab', (tester) async {
    await pumpShell(tester);

    expect(kShowExamMarks, isTrue);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('home shows the marks surfaces', (tester) async {
    await pumpShell(tester);

    expect(find.text('Worksheet'), findsOneWidget);
    expect(find.text('Classwork'), findsOneWidget);
    expect(find.text('Marks'), findsOneWidget);
    expect(find.text('LATEST MARKS'), findsOneWidget);
    // No result yet: the block says so rather than showing a blank card.
    expect(find.text('No marks yet'), findsOneWidget);
  });

  testWidgets(
    'home screen offers quick actions for worksheet, classwork, exam, marks '
    'and image',
    (tester) async {
      await pumpShell(tester);

      expect(find.text('Worksheet'), findsWidgets);
      expect(find.text('Classwork'), findsWidgets);
      expect(find.text('Exam'), findsWidgets);
      expect(find.text('Marks'), findsWidgets);
      expect(find.text('Add from Image'), findsOneWidget);
    },
  );

  testWidgets('performance tab shows its empty state before any marks', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();

    expect(find.text('No marks yet'), findsOneWidget);
    expect(find.text('Add Marks'), findsOneWidget);
    expect(find.text('All years'), findsOneWidget);
  });

  testWidgets(
    'performance tab renders the weak-subject card in both themes at phone '
    'width',
    (tester) async {
      await seed(tester);
      await tester.runAsync(() async {
        // Three results: Mathematics sits around 45%, Science around 88%.
        for (final (label, day, maths, science) in const [
          ('Unit Test 1', 10, 48.0, 86.0),
          ('Unit Test 2', 20, 45.0, 88.0),
          ('Term 1', 30, 42.0, 90.0),
        ]) {
          await state.saveResult(
            ExamResult(
              id: '',
              childId: '',
              academicYearId: '',
              examLabel: label,
              date: DateTime(2026, 7, day),
              scores: [
                SubjectScore(subject: 'Mathematics', marks: maths, maxMarks: 100),
                SubjectScore(subject: 'English', marks: 70, maxMarks: 100),
                SubjectScore(subject: 'Science', marks: science, maxMarks: 100),
              ],
            ),
          );
        }
        await _settle(14);
      });

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      for (final brightness in Brightness.values) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        await tester.pumpWidget(
          AppScope(
            state: state,
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) => MaterialApp(
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: state.themeMode,
                onGenerateRoute: Routes.onGenerateRoute,
                home: const MainShell(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Home: the "Latest marks" block names the newest card and flags
        // the weak subject.
        expect(find.text('Term 1'), findsOneWidget, reason: '$brightness');
        expect(find.textContaining('Mathematics · 45%'), findsOneWidget);

        await tester.tap(find.text('Performance'));
        await tester.pumpAndSettle();

        expect(find.text('NEEDS ATTENTION'), findsOneWidget);
        expect(find.byType(WeakSubjectCard), findsOneWidget);
        expect(find.text('Averaging 45% — below a passing mark'), findsOneWidget);
        expect(find.text('Needs attention'), findsOneWidget);
        expect(find.text('View subject'), findsOneWidget);
        // Prompt 02 wires this; until then it must not be offered.
        expect(find.text('Generate practice'), findsNothing);
        expect(find.text('RESULTS · 3'), findsOneWidget);

        // Result detail is reachable from the list. The tab holds a second,
        // horizontal Scrollable (the scope chips), so name the outer one.
        final page = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Unit Test 2'),
          200,
          scrollable: page,
        );
        // A sliver child can exist in the cache extent while still sitting
        // below the viewport, where a tap would miss it.
        await tester.ensureVisible(find.text('Unit Test 2'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Unit Test 2'));
        await tester.pumpAndSettle();
        expect(find.text('Entered by you'), findsOneWidget);
        expect(find.text('45 / 100'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // And the subject page from the weak card, with its Marks tab.
        await tester.scrollUntilVisible(
          find.text('View subject'),
          -200,
          scrollable: page,
        );
        await tester.ensureVisible(find.text('View subject'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('View subject'));
        await tester.pumpAndSettle();
        expect(find.text('Marks'), findsOneWidget);
        // Five tab chips overflow the strip under the test font; scroll the
        // chip into view before tapping it.
        await tester.ensureVisible(find.text('Marks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Marks'));
        await tester.pumpAndSettle();
        expect(find.text('MARKS · MATHEMATICS'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('adding marks from the quick action lands on Performance', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('Marks').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Marks'), findsOneWidget);

    await tester.tap(find.text('Unit Test 1'));
    await tester.pumpAndSettle();

    // Each subject row is a card whose first two fields are marks and max.
    // 30% against a 90% sibling is what makes Mathematics weak under §E; a
    // lone 45% would only be "watch". Rows below the fold are not built
    // until scrolled to, so each is brought into view first.
    Future<void> enterRow(String subject, String marks, String max) async {
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text(subject), 200, scrollable: list);
      await tester.ensureVisible(find.text(subject));
      await tester.pumpAndSettle();
      final card = find.ancestor(
        of: find.text(subject),
        matching: find.byType(AppCard),
      );
      final fields = find.descendant(of: card, matching: find.byType(TextField));
      await tester.enterText(fields.at(0), marks);
      await tester.enterText(fields.at(1), max);
      await tester.pumpAndSettle();
    }

    await enterRow('Mathematics', '30', '100');
    // On the row and, with one row scored, as the footer's overall too.
    expect(find.text('30%'), findsNWidgets(2), reason: 'live percent');
    // Scrolling to English's row can un-build Mathematics's, now off-screen
    // in the lazy list — the footer is the one figure guaranteed to still be
    // there.
    await enterRow('English', '90', '100');
    expect(find.text('60%'), findsOneWidget, reason: 'live overall in footer');

    // The save button lives in the sticky footer, so it is always on screen.
    await tester.tap(find.text('Save Marks'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => _settle(12));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();
    expect(find.text('RESULTS · 1'), findsOneWidget);
    expect(find.byType(WeakSubjectCard), findsOneWidget);
  });

  testWidgets('saving a worksheet puts it on the timeline', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Worksheet').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Worksheet'), findsOneWidget);

    // There is no free-text title anymore — the chosen chapter(s) (1–10)
    // stand in for it, toggled inline as chips like the subject row above.
    await tester.tap(find.text('Chapter 7'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Worksheet'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => _settle(12));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    // The section heading stays hidden in chapter sort, but each card still
    // carries its own chapter line so the item remains identifiable.
    expect(find.text('CHAPTER 7'), findsNothing);
    expect(find.text('Chapter 7'), findsWidgets);
    expect(find.text('Worksheet'), findsWidgets);
  });

  testWidgets('saving a classwork puts it on the timeline', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Classwork').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Classwork'), findsOneWidget);

    // Chapter selection replaces the free-text title field, inline as chips.
    await tester.tap(find.text('Chapter 8'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Classwork'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => _settle(12));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.text('CHAPTER 8'), findsNothing);
    expect(find.text('Chapter 8'), findsWidgets);
    expect(find.text('Classwork'), findsWidgets);
  });

  testWidgets('a new worksheet defaults to today, not a sample date', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('Worksheet').first);
    await tester.pumpAndSettle();

    // §37: the date field is pre-filled with today so the common case needs no
    // interaction at all.
    final today = DateTime.now();
    expect(
      find.textContaining('${today.day}'),
      findsWidgets,
      reason: "today's date should already be in the form",
    );
  });

  testWidgets('timeline filter sheet offers exam and marks', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Filter timeline'), findsOneWidget);
    // The timeline behind the sheet also labels its cards, so these are
    // "at least one".
    expect(find.text('Worksheet'), findsWidgets);
    expect(find.text('Classwork'), findsWidgets);
    expect(find.text('Exam'), findsWidgets);
    expect(find.text('Marks'), findsWidgets);

    // Marks is a results filter: with none saved, the timeline says so
    // rather than showing classwork under the wrong chip.
    await tester.tap(find.text('Marks').last);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(state.filter.type, 'Marks');
    expect(find.text('No marks yet'), findsOneWidget);
  });

  testWidgets(
    'timeline filter sheet allows subject filter and chapter sorting',
    (tester) async {
      await pumpShell(tester);

      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();

      // Select subject "Mathematics"
      await tester.tap(find.text('Mathematics').last);
      await tester.pumpAndSettle();

      // Select sort by "Chapter"
      await tester.tap(find.text('Chapter').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Check that state filter has been updated
      expect(state.filter.subject, 'Mathematics');
      expect(state.filter.sortBy, 'Chapter');
    },
  );

  testWidgets('more screen shows the Google account and hides removed rows', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Jayesh Patel'), findsOneWidget);
    expect(find.text('jayesh@example.com'), findsWidgets);
    expect(find.text('Manage children'), findsOneWidget);
    expect(find.text('Academic years'), findsOneWidget);
    expect(find.text('Subjects'), findsOneWidget);
    expect(find.text('Grade scale'), findsOneWidget);
    expect(find.text('CBSE 9-point'), findsOneWidget);

    // Theme, Notifications and Backup & sync have no settings row anymore —
    // theme follows the system and reminders are simply always on.
    expect(find.text('Theme'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Backup & sync'), findsNothing);
    expect(find.text('Privacy'), findsNothing);
    expect(find.text('Terms'), findsNothing);
    expect(find.text('Help & support'), findsNothing);
  });

  testWidgets('worksheet detail marks completed and back again', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('Fractions Practice').first);
    await tester.pumpAndSettle();

    expect(find.text('Mark completed'), findsOneWidget);
    await tester.tap(find.text('Mark completed'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => _settle(12));
    await tester.pumpAndSettle();
    expect(find.text('Mark pending'), findsOneWidget);

    // The confirmation toast floats over the sticky footer; without letting it
    // expire, the next tap lands on the toast's action instead of the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark pending'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => _settle(12));
    await tester.pumpAndSettle();
    expect(find.text('Mark completed'), findsOneWidget);
  });

  testWidgets('deleting a record removes it and offers an undo', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('Fractions Practice').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() => _settle(12));
    await tester.pumpAndSettle();

    expect(find.text('Record deleted'), findsOneWidget);
    // Soft delete (§30) makes Undo a restore rather than a re-create.
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('browse surfaces show the attachment, not a placeholder', (
    tester,
  ) async {
    // Regression: the detail screens, forms, picker and viewer were wired to
    // render real attachments, but the timeline card and the list/subject
    // thumbnails still built a bare ImageSlot. Every browsing surface showed a
    // dashed "Photo" placeholder even for records whose upload had completed,
    // which reads on device exactly like a broken sync.
    final png = File('${Directory.systemTemp.path}/diary_test_page.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
          'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
        ),
      );
    addTearDown(() {
      if (png.existsSync()) png.deleteSync();
    });

    await seed(tester);
    await tester.runAsync(() async {
      await state.saveRecord(
        DiaryRecord(
          id: '',
          academicYearId: '2026–27',
          type: RecordType.worksheet,
          subject: 'Mathematics',
          title: 'Has a photo',
          date: DateTime(2026, 8, 23),
          attachments: [
            Attachment(
              id: 'att-1',
              name: 'page-1.png',
              meta: 'Page 1',
              localPath: png.path,
              sync: SyncState.synced,
            ),
          ],
        ),
      );
      await _settle(14);
    });

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => MaterialApp(
            theme: AppTheme.light(),
            onGenerateRoute: Routes.onGenerateRoute,
            home: const MainShell(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The timeline filters against the real clock, and this fixture is dated
    // in the design's sample week.
    state.setFilter(const TimelineFilter(date: 'All'));
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();

    final slots = tester
        .widgetList<ImageSlot>(find.byType(ImageSlot))
        .where((slot) => slot.image != null);
    expect(
      slots,
      isNotEmpty,
      reason: 'the timeline card must render the attachment it has',
    );
  });

  testWidgets('the loading skeletons fit a real phone width', (tester) async {
    await pumpShell(tester);

    // The "settings destinations all build" test opens this page but only ever
    // lays out its first tab, so a horizontal overflow in the Loading tab went
    // unnoticed until it appeared on a device. Switching tabs is what actually
    // builds the skeletons; any overflow raises and fails the test.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Empty, loading & error states'),
      200,
    );
    // The More page grew a "School notices" group (prompt 03); the row can
    // sit in the cache extent below the viewport, where a tap misses it.
    await tester.ensureVisible(find.text('Empty, loading & error states'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty, loading & error states'));
    await tester.pumpAndSettle();

    // The skeletons shimmer on a repeating animation, so pumpAndSettle would
    // wait for something that never finishes. Fixed pumps still lay everything
    // out, which is all an overflow needs to surface.
    Future<void> settleTab() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.tap(find.text('Loading'));
    await settleTab();

    // Every skeleton variant, not just the default one.
    for (final kind in const ['Dashboard', 'Timeline', 'Subject', 'Lists']) {
      final chip = find.text(kind);
      if (chip.evaluate().isEmpty) continue;
      await tester.tap(chip.first);
      await settleTab();
    }

    await tester.tap(find.text('Errors'));
    await settleTab();
    await tester.tap(find.text('Empty'));
    await settleTab();
  });

  testWidgets('settings destinations all build', (tester) async {
    await pumpShell(tester);

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

Future<void> _settle([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
