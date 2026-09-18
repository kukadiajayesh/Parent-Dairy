// ignore_for_file: invalid_use_of_visible_for_testing_member
// Not a regression test — a numbers generator for docs/audit/performance.md.
// It lives outside `test/` so `flutter test` does not run it; invoke with:
//   flutter test tool/perf_bench_test.dart
// The numbers are from the test VM in debug mode, so they are only useful
// as before/after ratios on the same machine, never as device timings.
// ignore_for_file: avoid_print

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
import 'package:parent_academic_diary/shell/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  AppState? state;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Paths.db = db;
  });

  tearDown(() {
    state?.dispose();
    state = null;
    Paths.db = null;
  });

  Future<void> seed(WidgetTester tester, int count) async {
    await tester.runAsync(() async {
      await PrefsService.init();
      final s = AppState(
        auth: AuthRepository(
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'parent-1', displayName: 'Jayesh'),
          ),
        ),
        connectivity: ConnectivityService.fixed(),
      );
      state = s;
      await s.bootstrap();
      await _settle();
      await state!.saveChild(
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
      final collection = Paths.records('parent-1', state!.activeChild.id);
      final subjects = state!.subjectNames;
      var batch = db.batch();
      for (var i = 0; i < count; i++) {
        final record = DiaryRecord(
          id: '',
          childId: state!.activeChild.id,
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

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        state: state!,
        child: ListenableBuilder(
          listenable: state!,
          builder: (context, _) => MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state!.themeMode,
            onGenerateRoute: Routes.onGenerateRoute,
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('timeline: first build, scroll frames, rebuild on a tick', (
    tester,
  ) async {
    await seed(tester, 500);
    state!.setFilter(const TimelineFilter(date: 'All', sortBy: 'Date'));

    final first = Stopwatch()..start();
    await pump(tester, const TimelinePage());
    first.stop();
    final cards = tester.widgetList(find.byType(TimelineCard)).length;
    print('records in state: ${state!.records.length}');
    print('first build + settle: ${first.elapsedMilliseconds} ms, '
        'TimelineCard built: $cards');

    // Scroll end to end in 600px steps, timing each pump as the closest thing
    // the VM has to a frame.
    final frames = <int>[];
    for (var i = 0; i < 40; i++) {
      final sw = Stopwatch()..start();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump();
      sw.stop();
      frames.add(sw.elapsedMicroseconds);
    }
    frames.sort();
    print('scroll pump p50: ${frames[frames.length ~/ 2] / 1000} ms, '
        'p95: ${frames[(frames.length * 0.95).floor()] / 1000} ms, '
        'max: ${frames.last / 1000} ms');

    // A notify that touches nothing the timeline shows — the upload queue and
    // the connectivity ticker do this constantly on device.
    final tick = Stopwatch()..start();
    state!.dismissOfflineBanner();
    await tester.pump();
    tick.stop();
    print('rebuild after an unrelated notify: ${tick.elapsedMicroseconds / 1000} ms');
  });

  testWidgets('home: rebuild on a tick', (tester) async {
    await seed(tester, 400);
    await pump(tester, const MainShell());
    final tick = Stopwatch()..start();
    state!.dismissOfflineBanner();
    await tester.pump();
    tick.stop();
    print('home rebuild after an unrelated notify: '
        '${tick.elapsedMicroseconds / 1000} ms');
  });

  testWidgets('groupBySubject / recordsByDateDesc over 400 records', (
    tester,
  ) async {
    await seed(tester, 400);
    final records = state!.records;
    print('records: ${records.length}, subjects: ${state!.subjectNames.length}');

    final group = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      state!.groupBySubject(state!.worksheets, 'worksheet');
    }
    group.stop();
    print('groupBySubject ×100: ${group.elapsedMilliseconds} ms '
        '(${group.elapsedMicroseconds / 100} µs per call)');

    final sort = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      state!.recordsByDateDesc;
    }
    sort.stop();
    print('recordsByDateDesc ×100: ${sort.elapsedMilliseconds} ms '
        '(${sort.elapsedMicroseconds / 100} µs per call)');

    final pending = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      state!.pendingWorksheets;
    }
    pending.stop();
    print('pendingWorksheets ×100: ${pending.elapsedMilliseconds} ms');
  });

  test('mapping 400 documents', () {
    final docs = <Map<String, dynamic>>[];
    for (var i = 0; i < 400; i++) {
      docs.add(
        Map$.recordToMap(
          DiaryRecord(
            id: 'rec-$i',
            type: RecordType.worksheet,
            subject: 'Mathematics',
            title: 'Record $i',
            date: DateTime(2026, 4, 1).add(Duration(days: i % 300)),
            attachments: const [
              Attachment(id: 'a', name: 'p.jpg', meta: 'Page 1'),
              Attachment(id: 'b', name: 'q.jpg', meta: 'Page 2'),
            ],
          ),
        )..['updatedAt'] = null,
      );
    }
    final fake = FakeFirebaseFirestore();
    final col = fake.collection('bench');
    Future<void> run() async {
      for (var i = 0; i < docs.length; i++) {
        await col.doc('rec-$i').set(docs[i]);
      }
      final snap = await col.get();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        snap.docs.map(Map$.recordFrom).toList();
      }
      sw.stop();
      print('recordFrom × 400 docs: ${sw.elapsedMicroseconds / 10 / 1000} ms '
          'per snapshot');
    }

    return run();
  });
}

Future<void> _settle([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
