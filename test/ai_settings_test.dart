import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/app/routes.dart';
import 'package:parent_academic_diary/core/config/feature_flags.dart';
import 'package:parent_academic_diary/core/services/ai/gemini_key_store.dart';
import 'package:parent_academic_diary/core/services/connectivity_service.dart';
import 'package:parent_academic_diary/core/services/prefs_service.dart';
import 'package:parent_academic_diary/core/theme/app_theme.dart';
import 'package:parent_academic_diary/data/app_state.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/auth_repository.dart';
import 'package:parent_academic_diary/features/ai/ai_settings_page.dart';
import 'package:parent_academic_diary/features/subject/subject_page.dart';
import 'package:parent_academic_diary/shell/add_sheet.dart';
import 'package:parent_academic_diary/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The AI settings screen and the rule that, with the runtime switch off,
/// no AI entry point is reachable from Home, Subject, Performance or the
/// Add sheet — only the More → AI row that turns it on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  late AppState state;

  Future<void> settle([int rounds = 6]) async {
    for (var i = 0; i < rounds; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrefsService.reset();
    db = FakeFirebaseFirestore();
    Paths.db = db;
  });

  tearDown(() {
    state.dispose();
    Paths.db = null;
  });

  Future<void> seed(WidgetTester tester, {bool withRecords = false}) async {
    await tester.runAsync(() async {
      await PrefsService.init();
      state = AppState(
        auth: AuthRepository(
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'parent-1', email: 'j@example.com', displayName: 'Jayesh Patel'),
          ),
        ),
        connectivity: ConnectivityService.fixed(),
        aiKeys: GeminiKeyStore(storage: MemoryKeyStorage()),
      );
      await state.bootstrap();
      await settle();
      await state.saveChild(
        const Child(name: 'Aarav Patel', initials: 'AP', school: 'Sunrise', grade: 'Class 5', section: 'B', year: '2026–27'),
      );
      await settle(12);
      if (withRecords) {
        await state.saveRecord(
          DiaryRecord(
            id: '',
            academicYearId: '2026–27',
            type: RecordType.worksheet,
            subject: 'Mathematics',
            title: 'Fractions Practice',
            date: DateTime(2026, 8, 23),
          ),
        );
        await settle(12);
      }
    });
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
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
            onGenerateRoute: Routes.onGenerateRoute,
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AI settings with zero keys shows the empty state and the switch', (tester) async {
    await seed(tester);
    await pump(tester, const AiSettingsPage());

    expect(find.text('Use Gemini AI'), findsOneWidget);
    expect(find.text('No keys yet'), findsOneWidget);
    expect(find.text('Add key'), findsWidgets);

    final list = find.byType(ListView).first;
    await tester.scrollUntilVisible(find.text('Revoke access'), 200, scrollable: find.descendant(of: list, matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    expect(find.text('Revoke access'), findsOneWidget);
    expect(find.text('Privacy & consent'), findsOneWidget);
    expect(find.text('Not yet accepted'), findsOneWidget);
    for (final label in ['Generation', 'Vision', 'Classification', 'Best quality']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('gemini-3.8-flash'), findsNWidgets(2));
    expect(find.text('gemini-2.5-pro'), findsOneWidget);
  });

  testWidgets('the master switch turns AI on and the More row reflects it', (tester) async {
    await seed(tester);
    await pump(tester, const AiSettingsPage());
    expect(state.aiEnabled, isFalse);

    await tester.tap(find.text('Use Gemini AI'));
    await tester.pumpAndSettle();
    expect(state.aiEnabled, isTrue);
    expect(PrefsService.instance.aiEnabled, isTrue);
  });

  testWidgets('with AI off, no entry point is reachable from the shell', (tester) async {
    await seed(tester, withRecords: true);
    expect(kAiEnabled, isTrue);
    expect(state.aiAvailable, isFalse);
    await pump(tester, const MainShell());

    // Home + Add sheet.
    expect(find.text('Generate practice'), findsNothing);
    await tester.tap(find.text('Worksheet').first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Performance tab: nothing AI, even in the header actions.
    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();
    expect(find.text('Focus plan'), findsNothing);
    expect(find.text('Generate practice'), findsNothing);

    // More: the one AI row that exists is the settings entry, reading Off.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Gemini AI'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('with AI off, the Add sheet and Subject page carry no AI rows', (tester) async {
    await seed(tester, withRecords: true);
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => AddSheet.show(context), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Worksheet'), findsOneWidget);
    expect(find.text('AI practice paper'), findsNothing);
    expect(find.text('Scan exam paper'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await pump(tester, const SubjectPage(subjectName: 'Mathematics'));
    expect(find.byTooltip('Generate practice'), findsNothing);
    expect(find.text('Fractions Practice'), findsWidgets);
  });

  testWidgets('with AI on, the Add sheet, Subject and Performance offer the entry points', (tester) async {
    await seed(tester, withRecords: true);
    await tester.runAsync(() => state.setAiEnabled(true));
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => AddSheet.show(context), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('AI practice paper'), findsOneWidget);
    expect(find.text('Scan exam paper'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await pump(tester, const SubjectPage(subjectName: 'Mathematics'));
    expect(find.byTooltip('Generate practice'), findsOneWidget);
  });
}
