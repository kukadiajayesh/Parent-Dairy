import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/services/ai/gemini_key_store.dart';

void main() {
  late MemoryKeyStorage storage;
  late DateTime now;
  late GeminiKeyStore store;

  setUp(() async {
    storage = MemoryKeyStorage();
    now = DateTime.utc(2026, 9, 19, 10, 30);
    store = GeminiKeyStore(storage: storage, now: () => now);
    await store.load();
  });

  group('rotation', () {
    test('returns keys in parent order, skipping unhealthy ones', () async {
      final a = await store.add(label: 'A', secret: 'AIza-aaaaaaaaaaaaaaaaaaaa');
      final b = await store.add(label: 'B', secret: 'AIza-bbbbbbbbbbbbbbbbbbbb');
      final c = await store.add(label: 'C', secret: 'AIza-cccccccccccccccccccc');

      expect(store.nextHealthy()!.id, a.id);
      await store.setEnabled(a.id, false);
      expect(store.nextHealthy()!.id, b.id);
      await store.markInvalid(b.id, 'API key not valid');
      expect(store.nextHealthy()!.id, c.id);
      expect(store.nextHealthy(exclude: {c.id}), isNull);
    });

    test('reorder changes priority', () async {
      final a = await store.add(label: 'A', secret: 'AIza-aaaaaaaaaaaaaaaaaaaa');
      final b = await store.add(label: 'B', secret: 'AIza-bbbbbbbbbbbbbbbbbbbb');
      await store.reorder([b.id, a.id]);
      expect(store.keys.map((k) => k.label), ['B', 'A']);
      expect(store.nextHealthy()!.id, b.id);
    });

    test('a 429 cools the key down until the next UTC midnight', () async {
      final a = await store.add(label: 'A', secret: 'AIza-aaaaaaaaaaaaaaaaaaaa');
      final b = await store.add(label: 'B', secret: 'AIza-bbbbbbbbbbbbbbbbbbbb');

      expect(store.untilUtcMidnight(), const Duration(hours: 13, minutes: 30));
      await store.markExhausted(a.id, store.untilUtcMidnight());

      expect(store.byId(a.id)!.status, KeyStatus.exhausted);
      expect(store.byId(a.id)!.cooldownUntil, DateTime.utc(2026, 9, 20));
      expect(store.nextHealthy()!.id, b.id);

      // One minute before midnight: still cooling.
      now = DateTime.utc(2026, 9, 19, 23, 59);
      expect(store.nextHealthy()!.id, b.id);
      // Midnight: back in rotation, first in order again.
      now = DateTime.utc(2026, 9, 20);
      expect(store.nextHealthy()!.id, a.id);
      expect(store.byId(a.id)!.effectiveStatus(now), KeyStatus.active);
    });

    test('all keys exhausted leaves nothing healthy', () async {
      final a = await store.add(label: 'A', secret: 'AIza-aaaaaaaaaaaaaaaaaaaa');
      await store.markExhausted(a.id, store.untilUtcMidnight());
      expect(store.nextHealthy(), isNull);
      expect(store.healthyCount, 0);
    });

    test('markUsed counts requests per month and clears exhaustion', () async {
      final a = await store.add(label: 'A', secret: 'AIza-aaaaaaaaaaaaaaaaaaaa');
      await store.markUsed(a.id);
      await store.markUsed(a.id);
      expect(store.byId(a.id)!.requestsThisMonth(now), 2);
      expect(store.byId(a.id)!.requestCount, 2);

      now = DateTime.utc(2026, 10, 1);
      expect(store.byId(a.id)!.requestsThisMonth(now), 0);
      await store.markUsed(a.id);
      expect(store.byId(a.id)!.requestsThisMonth(now), 1);
      expect(store.byId(a.id)!.requestCount, 3);
    });
  });

  group('storage', () {
    test('persists as one blob and reloads', () async {
      await store.add(label: 'Personal', secret: 'AIza-aaaaaaaaaaaaaaaaaaaa');
      expect(storage.value, contains('AIza-aaaaaaaaaaaaaaaaaaaa'));

      final reloaded = GeminiKeyStore(storage: storage, now: () => now);
      await reloaded.load();
      expect(reloaded.keys.single.label, 'Personal');
      expect(reloaded.keys.single.secret, 'AIza-aaaaaaaaaaaaaaaaaaaa');
    });

    test('a garbage blob reports a load error rather than "no keys"', () async {
      storage.value = '{not json';
      final broken = GeminiKeyStore(storage: storage, now: () => now);
      await broken.load();
      expect(broken.loadError, isNotNull);
      expect(broken.isLoaded, isTrue);
    });

    test('clear wipes the blob', () async {
      await store.add(label: 'A', secret: 'AIza-aaaaaaaaaaaaaaaaaaaa');
      await store.clear();
      expect(store.keys, isEmpty);
      expect(storage.value, isNull);
    });
  });

  group('secrecy', () {
    test('the secret never appears in toString or the masked form', () async {
      final key = await store.add(label: 'Work', secret: 'AIzaSyD-1234567890abcdef7f2c');
      expect(key.toString(), isNot(contains('AIzaSyD-1234567890abcdef7f2c')));
      expect(key.toString(), contains('Work'));
      expect(key.masked, 'AIza••••••7f2c');
      expect(key.masked, isNot(contains('1234567890')));
      expect(store.toString(), isNot(contains('AIzaSyD')));
    });
  });
}
