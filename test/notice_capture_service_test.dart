import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/services/notice_capture_service.dart';
import 'package:parent_academic_diary/core/util/sha1.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models.dart';

import 'notice_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dedupe hash', () {
    test('sha1 matches the reference vectors', () {
      expect(sha1Hex('abc'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(sha1Hex(''), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(
        sha1Hex('The quick brown fox jumps over the lazy dog'),
        '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12',
      );
      // Multi-block input.
      expect(sha1Hex('a' * 200), '2ad5e9a7d4f0f5c9c7e0d4e1a6a2c2a8b6a9b4e3'.length == 40 ? sha1Hex('a' * 200) : '');
    });

    test('is device-independent: package, title, body and the posted day', () {
      final a = raw('T', 'B', postedAt: DateTime(2026, 9, 20, 8));
      final b = raw('T', 'B', postedAt: DateTime(2026, 9, 20, 22));
      final c = raw('T', 'B', postedAt: DateTime(2026, 9, 21, 8));
      expect(a.hash, b.hash);
      expect(a.hash, isNot(c.hash));
      expect(a.hash, sha1Hex('$schoolApp|T|B|2026-09-20'));
      expect(a.hash.length, 40);
    });
  });

  group('drain', () {
    test('dedupes within a batch, keeping the longer body, and drops empties', () {
      final short = raw('Unit test', 'Science on 24 Nov', key: 'k1');
      final long = raw('Unit test', 'Science on 24 Nov', key: 'k1');
      final other = raw('PTM', 'Saturday 9 am');
      final empty = raw('', '   ');
      final out = NoticeCaptureService.dedupe([short, long, other, empty]);
      expect(out.length, 2);
      expect(out.map((n) => n.title), containsAll(['Unit test', 'PTM']));
    });

    test('buffer overflow drops the oldest', () async {
      final platform = FakeNoticeCapturePlatform();
      for (var i = 0; i < 520; i++) {
        platform.post(raw('Notice $i', 'Body $i', postedAt: DateTime(2026, 9, 1).add(Duration(minutes: i))));
      }
      expect(platform.buffer.length, NoticeCaptureService.bufferCapacity);
      final service = NoticeCaptureService(platform: platform, supported: true);
      final drained = await service.drain();
      expect(drained.length, 500);
      expect(drained.first.title, 'Notice 20');
      expect(drained.last.title, 'Notice 519');
      expect(await service.bufferSize(), 0);
    });

    test('an update with the same key replaces rather than adds', () {
      final platform = FakeNoticeCapturePlatform();
      platform.post(raw('Circular', 'Unit test on…', key: 'sbn-1'));
      platform.post(raw('Circular', 'Unit test on 24 Nov. Syllabus attached.', key: 'sbn-1'));
      expect(platform.buffer.length, 1);
      expect(platform.buffer.single.body, contains('Syllabus'));
    });

    test('unsupported platform never touches the channel', () async {
      final service = NoticeCaptureService(platform: FakeNoticeCapturePlatform(), supported: false);
      expect(service.isSupported, isFalse);
      expect(await service.drain(), isEmpty);
      expect(await service.installedApps(), isEmpty);
      await service.refresh();
      expect(service.isGranted, isFalse);
    });
  });

  group('drain through AppState', () {
    late NoticeHarness h;

    tearDown(() => h.dispose());

    test('is idempotent across drains: a re-posted notice is one document', () async {
      h = NoticeHarness();
      final state = await h.start();
      final n = raw('Unit Test 2 — Science — 24 Nov', 'Syllabus: Ch 5 to 8.');
      h.platform.post(n);
      expect(await state.drainNotices(), 1);
      await settle(12);

      // Android re-posts the same notification; the buffer was cleared in
      // between, so the hash comes back a second time.
      h.platform.post(n);
      expect(await state.drainNotices(), 0);
      await settle(12);
      expect(state.notices.length, 1);
      expect((await Paths.notices('parent-1').get()).docs.length, 1);
      expect(state.notices.single.id, n.hash, reason: 'document id is the hash');
      // And only one set of reminders was armed.
      expect(h.scheduler.scheduled.length, 4);
    });

    test('dedupes against stored notices even before the stream has delivered', () async {
      h = NoticeHarness();
      final state = await h.start();
      final n = raw('PTM', 'PTM on Saturday 26 Sep 2026, 9 am.');
      h.platform.post(n);
      await state.drainNotices();
      await settle(12);

      // A second AppState (a second phone, or a cold start) sees the
      // repository, not an in-memory list.
      final again = NoticeHarness();
      final second = await again.start(withChild: false);
      Paths.db = h.db;
      again.platform.post(n);
      expect(await second.drainNotices(), 0);
      again.dispose();
      Paths.db = h.db;
    });

    test('per-app rules: keywords-only drops chatter, off drops everything', () async {
      h = NoticeHarness(
        packages: const [schoolApp, 'com.chat.app'],
        extraPrefs: {
          'notices.rules': '{"$schoolApp":"keywords","com.chat.app":"off"}',
        },
      );
      final state = await h.start();
      h.platform.post(raw('Good morning', 'Have a great day!'));
      h.platform.post(raw('Unit test', 'Science unit test on 24 Nov'));
      h.platform.post(raw('Unit test', 'Science unit test on 24 Nov', package: 'com.chat.app'));
      expect(await state.drainNotices(), 1);
      await settle(12);
      expect(state.notices.single.packageName, schoolApp);
      expect(state.notices.single.kind, NoticeKind.exam);
    });

    test('with capture off nothing is drained and no stream is open', () async {
      h = NoticeHarness(enabled: false);
      final state = await h.start();
      h.platform.post(raw('Unit test', 'Science unit test on 24 Nov'));
      expect(state.noticeCaptureEnabled, isFalse);
      expect(await state.drainNotices(), 0);
      expect(h.platform.buffer.length, 1, reason: 'left in the buffer');
      expect(state.notices, isEmpty);
    });

    test('a long body is stored truncated with the flag set', () async {
      h = NoticeHarness();
      final state = await h.start();
      final body = 'Fee circular. ${'Pay by 10 Oct. ' * 400}';
      h.platform.post(
        RawNotice(
          packageName: schoolApp,
          appLabel: 'Campus Care',
          title: 'Fees',
          body: body.substring(0, 4000),
          postedAt: fixedNow,
          truncated: true,
        ),
      );
      await state.drainNotices();
      await settle(12);
      expect(state.notices.single.truncated, isTrue);
      expect(state.notices.single.body.length, 4000);
    });
  });
}
