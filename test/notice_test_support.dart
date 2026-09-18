import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:parent_academic_diary/core/services/connectivity_service.dart';
import 'package:parent_academic_diary/core/services/notice_capture_service.dart';
import 'package:parent_academic_diary/core/services/notification_service.dart';
import 'package:parent_academic_diary/core/services/prefs_service.dart';
import 'package:parent_academic_diary/data/analytics/notice_reminders.dart';
import 'package:parent_academic_diary/data/app_state.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared plumbing for the prompt 03 tests: a signed-in [AppState] over a
/// fake Firestore, a fake capture platform and an in-memory scheduler.

const schoolApp = 'com.campuscare.parent';

/// Sunday 20 September 2026, 18:30 — the same anchor as the corpus.
final fixedNow = DateTime(2026, 9, 20, 18, 30);

/// The Firestore fake delivers through real timers; each round needs time.
Future<void> settle([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Records what the app asked to schedule, without a platform plugin.
class FakeScheduler implements NoticeReminderScheduler {
  final Map<int, DateTime> scheduled = {};
  final List<String> armedShown = [];
  bool refuse = false;

  @override
  Future<List<int>> scheduleNoticeReminders(CapturedNotice notice, List<DateTime> times) async {
    if (refuse) return const [];
    final ids = <int>[];
    for (var i = 0; i < times.length; i++) {
      final id = NoticeReminders.notificationId(notice.id, i);
      scheduled[id] = times[i];
      ids.add(id);
    }
    return ids;
  }

  @override
  Future<void> cancelNoticeReminders(List<int> ids) async {
    for (final id in ids) {
      scheduled.remove(id);
    }
  }

  @override
  Future<void> showNoticeArmed(CapturedNotice notice) async => armedShown.add(notice.id);
}

RawNotice raw(
  String title,
  String body, {
  DateTime? postedAt,
  String package = schoolApp,
  String key = '',
}) => RawNotice(
  packageName: package,
  appLabel: 'Campus Care',
  title: title,
  body: body,
  postedAt: postedAt ?? fixedNow.subtract(const Duration(hours: 1)),
  key: key,
);

class NoticeHarness {
  NoticeHarness({
    this.enabled = true,
    this.supported = true,
    bool granted = true,
    List<String> packages = const [schoolApp],
    Map<String, Object> extraPrefs = const {},
    DateTime Function()? now,
  }) : platform = FakeNoticeCapturePlatform(granted: granted) {
    SharedPreferences.setMockInitialValues({
      if (enabled) 'notices.enabled': true,
      'notices.packages': packages,
      'notices.disclosure.at': fixedNow.millisecondsSinceEpoch,
      ...extraPrefs,
    });
    PrefsService.reset();
    db = FakeFirebaseFirestore();
    Paths.db = db;
    _now = now ?? () => fixedNow;
  }

  final bool enabled;
  final bool supported;
  final FakeNoticeCapturePlatform platform;
  final FakeScheduler scheduler = FakeScheduler();
  late final FakeFirebaseFirestore db;
  late final AppState state;
  late final DateTime Function() _now;

  Future<AppState> start({bool withChild = true, int children = 1}) async {
    await PrefsService.init();
    state = AppState(
      auth: AuthRepository(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'parent-1', email: 'j@example.com', displayName: 'Jayesh Patel'),
        ),
      ),
      connectivity: ConnectivityService.fixed(),
      noticeCapture: NoticeCaptureService(platform: platform, supported: supported),
      noticeScheduler: scheduler,
      now: _now,
    );
    await state.bootstrap();
    await settle();
    if (withChild) {
      for (var i = 0; i < children; i++) {
        await state.saveChild(
          Child(
            name: i == 0 ? 'Aarav Patel' : 'Diya Patel',
            initials: i == 0 ? 'AP' : 'DP',
            school: 'Sunrise',
            grade: i == 0 ? 'Class 5' : 'Class 2',
            section: 'B',
            year: '2026–27',
          ),
        );
      }
      await settle(12);
    }
    return state;
  }

  void dispose() {
    state.dispose();
    Paths.db = null;
  }
}
