import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/errors/app_failure.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/mappers.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/notice_repository.dart';

const uid = 'parent-1';

CapturedNotice sample({
  String id = '',
  String hash = 'abc123',
  DateTime? postedAt,
  NoticeStatus status = NoticeStatus.needsReview,
}) => CapturedNotice(
  id: id,
  packageName: 'com.campuscare.parent',
  appLabel: 'Campus Care',
  title: 'Unit Test 2 — Science — 24 Nov',
  body: 'Syllabus: Ch 5 to 8.',
  postedAt: postedAt ?? DateTime(2026, 9, 20, 17),
  sourceHash: hash,
  status: status,
  extraction: NoticeExtraction(
    kind: NoticeKind.exam,
    title: 'Science Unit Test 2',
    subject: 'Science',
    eventAt: DateTime(2026, 11, 24),
    confidence: 0.9,
    matchedPhrases: const ['unit test', '24 Nov'],
    alternateDates: [DateTime(2026, 11, 26)],
  ),
  reminderIds: const [11, 12],
);

void main() {
  late FakeFirebaseFirestore db;
  const repo = NoticeRepository();

  setUp(() {
    db = FakeFirebaseFirestore();
    Paths.db = db;
  });

  tearDown(() => Paths.db = null);

  test('a new notice is written under its hash and round-trips every field', () async {
    final saved = await repo.save(uid: uid, notice: sample());
    expect(saved.id, 'abc123');

    final loaded = (await repo.watch(uid).first).single;
    expect(loaded.id, 'abc123');
    expect(loaded.sourceHash, 'abc123');
    expect(loaded.appLabel, 'Campus Care');
    expect(loaded.title, 'Unit Test 2 — Science — 24 Nov');
    expect(loaded.status, NoticeStatus.needsReview);
    expect(loaded.reminderIds, [11, 12]);
    final e = loaded.extraction!;
    expect(e.kind, NoticeKind.exam);
    expect(e.title, 'Science Unit Test 2');
    expect(e.subject, 'Science');
    expect(e.eventAt, DateTime(2026, 11, 24));
    expect(e.dueAt, isNull);
    expect(e.allDay, isTrue);
    expect(e.confidence, 0.9);
    expect(e.source, 'rules');
    expect(e.matchedPhrases, ['unit test', '24 Nov']);
    expect(e.alternateDates, [DateTime(2026, 11, 26)]);
  });

  test('saving the same hash twice is one document', () async {
    await repo.save(uid: uid, notice: sample());
    await repo.save(uid: uid, notice: sample(id: 'abc123', status: NoticeStatus.confirmed));
    final docs = (await Paths.notices(uid).get()).docs;
    expect(docs.length, 1);
    expect(docs.single.data()['status'], 'confirmed');
  });

  test('watch is newest posted first and skips soft-deleted', () async {
    await repo.save(uid: uid, notice: sample(hash: 'old', postedAt: DateTime(2026, 9, 1)));
    await repo.save(uid: uid, notice: sample(hash: 'new', postedAt: DateTime(2026, 9, 20)));
    await repo.save(uid: uid, notice: sample(hash: 'gone', postedAt: DateTime(2026, 9, 10)));
    await repo.softDelete(uid: uid, noticeId: 'gone');

    final list = await repo.watch(uid).first;
    expect(list.map((n) => n.id), ['new', 'old']);
    expect(await repo.knownHashes(uid), {'new', 'old'});
    expect((await Paths.notices(uid).doc('gone').get()).exists, isTrue);
  });

  test('retention purge really deletes only the old ones', () async {
    await repo.save(uid: uid, notice: sample(hash: 'ancient', postedAt: DateTime(2026, 1, 1)));
    await repo.save(uid: uid, notice: sample(hash: 'recent', postedAt: DateTime(2026, 9, 19)));
    final removed = await repo.purgeOlderThan(uid: uid, before: DateTime(2026, 3, 24));
    expect(removed, 1);
    final docs = (await Paths.notices(uid).get()).docs;
    expect(docs.map((d) => d.id), ['recent']);
  });

  test('deleteAll removes everything, deleted or not', () async {
    await repo.save(uid: uid, notice: sample(hash: 'a'));
    await repo.save(uid: uid, notice: sample(hash: 'b'));
    await repo.softDelete(uid: uid, noticeId: 'a');
    expect(await repo.deleteAll(uid), 2);
    expect((await Paths.notices(uid).get()).docs, isEmpty);
  });

  test('rejects a notice with no text or no source', () async {
    await expectLater(
      repo.save(uid: uid, notice: sample().copyWith(title: '', body: ' ')),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.invalidFile)),
    );
    await expectLater(
      repo.save(uid: uid, notice: sample().copyWith(packageName: '')),
      throwsA(isA<AppFailure>()),
    );
  });

  test('the mapper caps the body at 4000 and reads a partial document', () async {
    final long = sample().copyWith(body: 'x' * 5000);
    final map = Map$.noticeToMap(long);
    expect((map['body'] as String).length, 4000);
    expect(map['truncated'], isTrue);

    await Paths.notices(uid).doc('partial').set({'packageName': 'p', 'body': 'hello'});
    final loaded = Map$.noticeFrom(await Paths.notices(uid).doc('partial').get());
    expect(loaded.id, 'partial');
    expect(loaded.sourceHash, 'partial');
    expect(loaded.status, NoticeStatus.needsReview);
    expect(loaded.extraction, isNull);
    expect(loaded.kind, NoticeKind.unknown);
    expect(loaded.displayTitle, 'hello');
  });
}
