import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/services/connectivity_service.dart';
import 'package:parent_academic_diary/core/services/prefs_service.dart';
import 'package:parent_academic_diary/core/theme/subject_hue.dart';
import 'package:parent_academic_diary/data/app_state.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/auth_repository.dart';
import 'package:parent_academic_diary/data/repositories/subject_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets the Firestore streams deliver before asserting.
///
/// A microtask yield is not enough: the fake delivers snapshots through real
/// timers, so each round has to give the event loop actual time.
Future<void> settle([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  late AppState state;

  Future<AppState> signedInState({bool offline = false}) async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: 'parent-1',
        email: 'jayesh@example.com',
        displayName: 'Jayesh Patel',
      ),
    );
    final s = AppState(
      auth: AuthRepository(auth: auth),
      connectivity: ConnectivityService.fixed(offline: offline),
    );
    await s.bootstrap();
    await settle();
    return s;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsService.init();
    db = FakeFirebaseFirestore();
    Paths.db = db;
  });

  tearDown(() {
    state.dispose();
    Paths.db = null;
  });

  group('auth gating', () {
    test('a signed-out parent resolves to signedOut', () async {
      state = AppState(
        auth: AuthRepository(auth: MockFirebaseAuth()),
        connectivity: ConnectivityService.fixed(),
      );
      await state.bootstrap();
      await settle();

      expect(state.authStatus, AuthStatus.signedOut);
      expect(state.isSignedIn, isFalse);
      expect(state.children, isEmpty);
    });

    test('a signed-in parent with no child needs setup', () async {
      state = await signedInState();
      expect(state.authStatus, AuthStatus.needsChild);
      expect(state.hasChildren, isFalse);
    });

    test('exposes the Google profile for the More screen', () async {
      state = await signedInState();
      expect(state.parentName, 'Jayesh');
      expect(state.parentFullName, 'Jayesh Patel');
      expect(state.parentEmail, 'jayesh@example.com');
      expect(state.parentInitials, 'JP');
    });

    test('activeChild is safe to read before any child exists', () async {
      state = await signedInState();
      // The shell builds a frame before the stream arrives; this must not throw.
      expect(state.activeChild.name, isNotEmpty);
    });
  });

  group('first child', () {
    test('seeds subjects and the academic year, and becomes ready', () async {
      state = await signedInState();

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
      await settle(12);

      expect(state.authStatus, AuthStatus.ready);
      expect(state.activeChild.name, 'Aarav Patel');
      expect(
        state.subjectNames,
        SubjectRepository.defaults.map((s) => s.name).toList(),
      );
      expect(state.years.single.label, '2026–27');
      expect(state.activeYear, '2026–27');
    });

    test('remembers the selection for the next launch (§37)', () async {
      state = await signedInState();
      await state.saveChild(
        const Child(
          name: 'Aarav',
          initials: 'AA',
          school: 'S',
          grade: 'Class 5',
          section: 'B',
          year: '2026–27',
        ),
      );
      await settle(12);

      expect(PrefsService.instance.childId, state.activeChild.id);
      expect(PrefsService.instance.year, '2026–27');
    });
  });

  group('records', () {
    setUp(() async {
      state = await signedInState();
      await state.saveChild(
        const Child(
          name: 'Aarav',
          initials: 'AA',
          school: 'S',
          grade: 'Class 5',
          section: 'B',
          year: '2026–27',
        ),
      );
      await settle(12);
    });

    DiaryRecord draft({
      String title = 'Fractions Practice',
      String subject = 'Mathematics',
      RecordType type = RecordType.worksheet,
      DateTime? date,
      DateTime? dueDate,
    }) => DiaryRecord(
      id: '',
      academicYearId: '2026–27',
      type: type,
      subject: subject,
      title: title,
      date: date ?? DateTime(2026, 8, 23),
      dueDate: dueDate,
    );

    test('a saved worksheet appears on the timeline', () async {
      await state.saveRecord(draft());
      await settle(10);

      expect(state.records, hasLength(1));
      expect(state.worksheets.single.title, 'Fractions Practice');
      expect(state.classwork, isEmpty);
      expect(state.records.single.childId, state.activeChild.id);
    });

    test('remembers the subject as the next suggestion (§11)', () async {
      await state.saveRecord(draft(subject: 'Science'));
      await settle(10);
      expect(state.suggestedSubject, 'Science');
    });

    test('pending worksheets sort by the date they are due', () async {
      await state.saveRecord(
        draft(title: 'Later', dueDate: DateTime(2026, 9, 10)),
      );
      await state.saveRecord(
        draft(title: 'Sooner', dueDate: DateTime(2026, 8, 25)),
      );
      await settle(10);

      expect(state.pendingWorksheets.map((r) => r.title), ['Sooner', 'Later']);
    });

    test('completing a worksheet drops it from the pending list', () async {
      await state.saveRecord(draft(dueDate: DateTime(2026, 8, 28)));
      await settle(10);
      final id = state.records.single.id;

      await state.markCompleted(id);
      await settle(10);

      expect(state.pendingWorksheets, isEmpty);
      expect(state.recordById(id)!.status, WorksheetStatus.completed);
      expect(state.recordById(id)!.completedDate, isNotNull);
    });

    test('delete then restore round-trips (§30)', () async {
      await state.saveRecord(draft());
      await settle(10);
      final id = state.records.single.id;

      await state.deleteRecord(id);
      await settle(10);
      expect(state.records, isEmpty);

      await state.restoreRecord(id);
      await settle(10);
      expect(state.records.single.id, id);
    });

    test('search finds an old record outside the active year', () async {
      await state.saveRecord(draft(title: 'Fractions Practice'));
      await settle(10);
      expect(await state.search('fractions'), hasLength(1));

      // Starting a new year must not disturb the old one (§6).
      await state.addYear(
        const AcademicYear(
          label: '2027–28',
          span: 'Apr 2027 – Mar 2028',
          records: 0,
        ),
        makeActive: true,
      );
      await settle(12);

      expect(state.activeYear, '2027–28');
      expect(state.records, isEmpty, reason: 'the year switch scopes the list');
      expect(await state.search('fractions'), isEmpty);
      expect(await state.search('fractions', allYears: true), hasLength(1));

      // And switching back brings the history straight back.
      state.selectYear('2026–27');
      await settle(12);
      expect(state.records, hasLength(1));
    });

    test('selecting a year that no longer exists falls back safely', () async {
      state.selectYear('1999–00');
      await settle(12);
      expect(state.activeYear, '2026–27');
    });

    test('groupBySubject keeps subject order and drops empty groups', () async {
      await state.saveRecord(draft(subject: 'English', title: 'Ch 4'));
      await state.saveRecord(draft(subject: 'Mathematics', title: 'Fractions'));
      await settle(10);

      final groups = state.groupBySubject(state.worksheets, 'worksheet');
      expect(groups.map((g) => g.subject.name), ['Mathematics', 'English']);
      expect(groups.first.count, '1 worksheet');
    });
  });

  group('subjects', () {
    setUp(() async {
      state = await signedInState();
      await state.saveChild(
        const Child(
          name: 'Aarav',
          initials: 'AA',
          school: 'S',
          grade: 'Class 5',
          section: 'B',
          year: '2026–27',
        ),
      );
      await settle(12);
    });

    test('adding one appends it to the list', () async {
      await state.addSubject(
        const Subject(
          name: 'Social Science',
          abbr: 'SS',
          hue: SubjectHue.steel,
          order: 0,
        ),
      );
      await settle(10);
      expect(state.subjectNames, contains('Social Science'));
    });

    test('removing hides it but old records keep their colour', () async {
      await state.removeSubject('Hindi');
      await settle(10);

      expect(state.subjectNames, isNot(contains('Hindi')));
      // A record already filed under Hindi still resolves to a usable Subject.
      expect(state.subjectByName('Hindi').name, 'Hindi');
      expect(state.subjectByName('Hindi').hue, SubjectHue.stone);
    });
  });

  group('offline banner', () {
    test('shows while offline and stays dismissed until the network moves',
        () async {
      state = await signedInState(offline: true);

      expect(state.isOffline, isTrue);
      expect(state.showOfflineBanner, isTrue);

      state.dismissOfflineBanner();
      expect(state.showOfflineBanner, isFalse);
      expect(state.isOffline, isTrue, reason: 'dismissing is not going online');
    });

    test('reports a sync label the More screen can show', () async {
      state = await signedInState(offline: true);
      expect(state.syncLabel, 'Offline');
    });
  });

  group('theme', () {
    test('persists across launches', () async {
      state = await signedInState();
      expect(state.isDark, isFalse);

      state.toggleTheme();
      expect(state.isDark, isTrue);
      expect(PrefsService.instance.isDark, isTrue);
    });
  });
}
