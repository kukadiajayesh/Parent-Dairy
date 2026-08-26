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
import 'package:parent_academic_diary/data/app_state.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/auth_repository.dart';
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

  testWidgets('home renders the signed-in parent and their records',
      (tester) async {
    await pumpShell(tester);

    expect(find.textContaining('Jayesh'), findsWidgets);
    expect(find.text('QUICK ACTIONS'), findsOneWidget);
    expect(find.text('Fractions Practice'), findsWidgets);
  });

  testWidgets('bottom navigation has no Performance tab', (tester) async {
    await pumpShell(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Performance'), findsNothing);
    expect(kShowExamMarks, isFalse);
  });

  testWidgets('home hides every marks surface', (tester) async {
    await pumpShell(tester);

    expect(find.text('Worksheet'), findsOneWidget);
    expect(find.text('Classwork'), findsOneWidget);
    expect(find.text('Marks'), findsNothing);
    expect(find.text('LATEST MARKS'), findsNothing);
  });

  testWidgets('home screen offers quick actions for worksheet, classwork, exam and image', (tester) async {
    await pumpShell(tester);

    expect(find.text('Worksheet'), findsWidgets);
    expect(find.text('Classwork'), findsWidgets);
    expect(find.text('Exam'), findsWidgets);
    expect(find.text('Add from Image'), findsOneWidget);
    expect(find.text('Marks'), findsNothing);
  });

  testWidgets('saving a worksheet puts it on the timeline', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Worksheet').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Worksheet'), findsOneWidget);

    // There is no free-text title anymore — the chosen chapter(s) (1–10)
    // stand in for it. Chapters are picked as chips, confirmed with "Done".
    await tester.tap(find.text('Select chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Worksheet'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => _settle(12));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chapter 7'), findsWidgets);
  });

  testWidgets('saving a classwork puts it on the timeline', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Classwork').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Classwork'), findsOneWidget);

    // Chapter selection replaces free-text title field
    await tester.tap(find.text('Select chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 8'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Classwork'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => _settle(12));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chapter 8'), findsWidgets);
  });

  testWidgets('a new worksheet defaults to today, not a sample date',
      (tester) async {
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

  testWidgets('timeline filter sheet includes exam but excludes marks',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Filter timeline'), findsOneWidget);
    // The timeline behind the sheet also labels its cards, so these are
    // "at least one" — the assertion that matters is the Marks absence.
    expect(find.text('Worksheet'), findsWidgets);
    expect(find.text('Classwork'), findsWidgets);
    expect(find.text('Exam'), findsWidgets);
    expect(find.text('Marks'), findsNothing);
  });

  testWidgets('timeline filter sheet allows subject filter and chapter sorting',
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
  });

  testWidgets('more screen shows the Google account and hides removed rows',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Jayesh Patel'), findsOneWidget);
    expect(find.text('jayesh@example.com'), findsWidgets);
    expect(find.text('Manage children'), findsOneWidget);
    expect(find.text('Academic years'), findsOneWidget);
    expect(find.text('Subjects'), findsOneWidget);

    // Theme, Notifications and Backup & sync have no settings row anymore —
    // theme follows the system and reminders are simply always on.
    expect(find.text('Theme'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Backup & sync'), findsNothing);
    expect(find.text('Privacy'), findsNothing);
    expect(find.text('Terms'), findsNothing);
    expect(find.text('Help & support'), findsNothing);
  });

  testWidgets('worksheet detail marks completed and back again',
      (tester) async {
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

  testWidgets('deleting a record removes it and offers an undo',
      (tester) async {
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

  testWidgets('browse surfaces show the attachment, not a placeholder',
      (tester) async {
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
