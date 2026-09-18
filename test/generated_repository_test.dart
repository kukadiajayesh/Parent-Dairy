import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/errors/app_failure.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models_ai.dart';
import 'package:parent_academic_diary/data/repositories/generated_repository.dart';

const uid = 'parent-1';
const childId = 'child-1';

GeneratedDoc sample({String title = 'Fractions practice', GeneratedKind kind = GeneratedKind.paper}) =>
    GeneratedDoc(
      id: '',
      childId: childId,
      kind: kind,
      title: title,
      subject: 'Mathematics',
      payload: const {'title': 'x', 'sections': []},
    );

void main() {
  late FakeFirebaseFirestore db;
  const repo = GeneratedRepository();

  setUp(() {
    db = FakeFirebaseFirestore();
    Paths.db = db;
  });
  tearDown(() => Paths.db = null);

  test('save assigns an id, stamps the child and links later', () async {
    final saved = await repo.save(uid: uid, childId: childId, doc: sample());
    expect(saved.id, isNotEmpty);
    expect(saved.childId, childId);

    await repo.link(uid: uid, childId: childId, generatedId: saved.id, recordId: 'rec-9');
    final doc = await Paths.generated(uid, childId).doc(saved.id).get();
    expect(doc.data()!['recordId'], 'rec-9');
    expect(doc.data()!['payload'], isA<Map>());
  });

  test('watch lists live documents newest first and hides soft-deleted ones', () async {
    final a = await repo.save(uid: uid, childId: childId, doc: sample(title: 'A'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.save(uid: uid, childId: childId, doc: sample(title: 'B', kind: GeneratedKind.scannedPaper));
    await repo.softDelete(uid: uid, childId: childId, generatedId: a.id);

    final list = await repo.watch(uid: uid, childId: childId).first;
    expect(list.map((g) => g.title), ['B']);
    expect(list.single.kind, GeneratedKind.scannedPaper);
  });

  test('rejects an empty title or payload', () async {
    await expectLater(
      repo.save(uid: uid, childId: childId, doc: sample(title: ' ')),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.invalidFile)),
    );
    await expectLater(
      repo.save(
        uid: uid,
        childId: childId,
        doc: const GeneratedDoc(id: '', childId: childId, kind: GeneratedKind.paper, title: 'x', payload: {}),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect((await Paths.generated(uid, childId).get()).docs, isEmpty);
  });
}
