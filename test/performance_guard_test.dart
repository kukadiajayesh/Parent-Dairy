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
import 'package:parent_academic_diary/data/mappers.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/auth_repository.dart';
import 'package:parent_academic_diary/features/timeline/timeline_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression net for the timeline's list strategy (prompt 04, part 1).
///
/// A year of records is a few hundred documents. The timeline must only build
/// the cards that fit on screen plus the cache extent — a `SliverList.list`
/// builds every one of them to draw ten, which is what this guards against.
/// The state is fed through the real Firestore seam so the records arrive the
/// way they do on device, through `RecordRepository.watch`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  late AppState state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Paths.db = db;
  });

  tearDown(() {
    state.dispose();
    Paths.db = null;
  });

  /// One child, [count] records spread over a school year.
  Future<void> seed(WidgetTester tester, int count) async {
    await tester.runAsync(() async {
      await PrefsService.init();
      state = AppState(
        auth: AuthRepository(
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'parent-1', displayName: 'Jayesh'),
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

      // Written straight to the collection: `saveRecord` also enqueues an
      // upload and notifies per record, and 500 of those is a slow, noisy
      // fixture for a test about the list.
      final collection = Paths.records('parent-1', state.activeChild.id);
      final subjects = state.subjectNames;
      var batch = db.batch();
      for (var i = 0; i < count; i++) {
        final record = DiaryRecord(
          id: '',
          childId: state.activeChild.id,
          academicYearId: '2026–27',
          type: i.isEven ? RecordType.worksheet : RecordType.classwork,
          subject: subjects[i % subjects.length],
          title: 'Record $i',
          chapters: ['Chapter ${1 + i % 10}'],
          date: DateTime(2026, 4, 1).add(Duration(days: i % 300)),
        );
        batch.set(collection.doc('rec-$i'), Map$.recordToMap(record));
        if (i % 100 == 99) {
          await batch.commit();
          batch = db.batch();
        }
      }
      await batch.commit();
      await _settle(20);
    });
  }

  Future<void> pumpTimeline(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: AppTheme.light(),
          onGenerateRoute: Routes.onGenerateRoute,
          home: const TimelinePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('timeline with 500 records builds only the visible cards', (
    tester,
  ) async {
    await seed(tester, 500);
    // Every record is dated inside the year, so "This week" would hide most
    // of them; the guard needs the full list on the sliver.
    state.setFilter(const TimelineFilter(date: 'All', sortBy: 'Date'));
    await pumpTimeline(tester);

    expect(state.records.length, greaterThanOrEqualTo(400));

    final built = tester.widgetList(find.byType(TimelineCard)).length;
    expect(
      built,
      lessThan(30),
      reason:
          'the timeline built $built cards for one screen — it must be a '
          'builder sliver, not SliverList.list',
    );
  });

  testWidgets('scrolling the timeline keeps the live card count bounded', (
    tester,
  ) async {
    await seed(tester, 500);
    state.setFilter(const TimelineFilter(date: 'All', sortBy: 'Date'));
    await pumpTimeline(tester);

    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final built = tester.widgetList(find.byType(TimelineCard)).length;
    expect(built, lessThan(30));
  });
}

Future<void> _settle([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
