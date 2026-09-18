import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_academic_diary/core/errors/app_failure.dart';
import 'package:parent_academic_diary/core/services/ai/gemini_client.dart';
import 'package:parent_academic_diary/core/services/ai/gemini_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const secret = 'AIzaSyD-secret-secret-secret-7f2c';

http.Response ok(Map<String, Object?> body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> candidate(String text, {String finish = 'STOP', Map<String, Object?>? usage}) => {
  'candidates': [
    {
      'content': {
        'parts': [
          {'text': text},
        ],
      },
      'finishReason': finish,
    },
  ],
  'usageMetadata': usage ?? {'promptTokenCount': 100, 'candidatesTokenCount': 20},
};

http.Response apiError(int code, String status, String message) =>
    ok({'error': {'code': code, 'status': status, 'message': message}}, status: code);

final request = GeminiRequest(
  model: 'gemini-test',
  parts: const [TextPart('hi')],
  responseSchema: const {'type': 'OBJECT'},
  timeout: const Duration(seconds: 2),
);

void main() {
  late GeminiKeyStore keys;
  late DateTime now;
  late List<Duration> delays;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 9, 19, 10);
    keys = GeminiKeyStore(storage: MemoryKeyStorage(), now: () => now);
    await keys.load();
    await keys.add(label: 'Personal', secret: secret);
    delays = [];
  });

  GeminiClient client(
    Future<http.Response> Function(http.Request) handler, {
    ValueListenable<bool>? offline,
    GeminiFileCache? fileCache,
  }) => GeminiClient(
    keys: keys,
    clientFactory: () => MockClient(handler),
    now: () => now,
    delay: (d) async => delays.add(d),
    offline: offline,
    fileCache: fileCache,
  );

  test('parses a schema-conforming reply and reports usage', () async {
    final c = client((req) async {
      expect(req.headers['x-goog-api-key'], secret);
      expect(req.url.path, '/v1beta/models/gemini-test:generateContent');
      final body = jsonDecode(req.body) as Map;
      expect((body['generationConfig'] as Map)['responseMimeType'], 'application/json');
      return ok(candidate('{"answer": 42}'));
    });
    final result = await c.generate(request, parse: (j) => j['answer'] as int);
    expect(result.value, 42);
    expect(result.usage.promptTokens, 100);
    expect(result.keyLabel, 'Personal');
    expect(keys.keys.single.requestCount, 1);
  });

  test('repairs malformed JSON once, then fails with a readable message', () async {
    var calls = 0;
    final c = client((req) async {
      calls++;
      if (calls == 1) return ok(candidate('Sure! Here it is: {"answer": '));
      final body = jsonDecode(req.body) as Map;
      final text = (((body['contents'] as List).first as Map)['parts'] as List).first as Map;
      expect(text['text'], contains('Return only valid JSON'));
      return ok(candidate('```json\n{"answer": 7}\n```'));
    });
    final result = await c.generate(request, parse: (j) => j['answer'] as int);
    expect(result.value, 7);
    expect(calls, 2);
    // Both calls are billed.
    expect(result.usage.promptTokens, 200);

    final broken = client((_) async => ok(candidate('nope')));
    await expectLater(
      broken.generate(request, parse: (j) => j),
      throwsA(
        isA<AppFailure>().having((f) => f.message, 'message', contains("couldn't read")),
      ),
    );
  });

  test('SAFETY, RECITATION and MAX_TOKENS are distinct, explained failures', () async {
    Future<AppFailure> failureFor(Map<String, Object?> body) async {
      try {
        await client((_) async => ok(body)).generate(request, parse: (j) => j);
        fail('expected a failure');
      } on AppFailure catch (f) {
        return f;
      }
    }

    final safety = await failureFor(candidate('', finish: 'SAFETY'));
    expect(safety.message, contains('unsafe'));
    expect(safety.canRetry, isFalse);

    final blocked = await failureFor({'promptFeedback': {'blockReason': 'SAFETY'}});
    expect(blocked.message, contains('unsafe'));

    final recitation = await failureFor(candidate('{}', finish: 'RECITATION'));
    expect(recitation.message, contains('published material'));

    final max = await failureFor(candidate('{"a":', finish: 'MAX_TOKENS'));
    expect(max.message, contains('fewer questions'));
  });

  test('a timeout is reported as such, not as a crash', () async {
    final c = client((_) => Completer<http.Response>().future);
    await expectLater(
      c.generate(
        request.copyWith().let((r) => GeminiRequest(
          model: r.model,
          parts: r.parts,
          responseSchema: r.responseSchema,
          timeout: const Duration(milliseconds: 20),
        )),
        parse: (j) => j,
      ),
      throwsA(isA<AppFailure>().having((f) => f.message, 'message', contains('too long'))),
    );
  });

  test('cancellation aborts and surfaces as a cancellation', () async {
    final token = CancellationToken();
    final c = client((_) async {
      token.cancel();
      throw http.ClientException('Connection closed');
    });
    await expectLater(
      c.generate(request, parse: (j) => j, cancel: token),
      throwsA(isA<AppFailure>().having((f) => f.isCancellation, 'cancelled', isTrue)),
    );
    // An already-cancelled token never sends.
    var sent = 0;
    final c2 = client((_) async {
      sent++;
      return ok(candidate('{}'));
    });
    await expectLater(
      c2.generate(request, parse: (j) => j, cancel: token),
      throwsA(isA<AppFailure>().having((f) => f.isCancellation, 'cancelled', isTrue)),
    );
    expect(sent, 0);
  });

  test('503 backs off 250ms / 1s / 3s on the same key, then fails over', () async {
    await keys.add(label: 'Work', secret: 'AIza-work-key-work-key-work-key');
    final seen = <String>[];
    final c = client((req) async {
      seen.add(req.headers['x-goog-api-key']!);
      if (req.headers['x-goog-api-key'] == secret) {
        return apiError(503, 'UNAVAILABLE', 'overloaded');
      }
      return ok(candidate('{"answer": 1}'));
    });
    final result = await c.generate(request, parse: (j) => j['answer'] as int);
    expect(result.value, 1);
    expect(result.keyLabel, 'Work');
    expect(seen.where((s) => s == secret).length, 3);
    expect(delays.length, 2);
    expect(delays[0], greaterThanOrEqualTo(const Duration(milliseconds: 250)));
    expect(delays[0], lessThan(const Duration(milliseconds: 400)));
    expect(delays[1], greaterThanOrEqualTo(const Duration(seconds: 1)));
  });

  test('429 exhausts the key until UTC midnight and fails over', () async {
    await keys.add(label: 'Work', secret: 'AIza-work-key-work-key-work-key');
    final c = client((req) async {
      if (req.headers['x-goog-api-key'] == secret) {
        return apiError(429, 'RESOURCE_EXHAUSTED', 'quota');
      }
      return ok(candidate('{"answer": 1}'));
    });
    final result = await c.generate(request, parse: (j) => j['answer'] as int);
    expect(result.keyLabel, 'Work');
    final personal = keys.keys.firstWhere((k) => k.label == 'Personal');
    expect(personal.status, KeyStatus.exhausted);
    expect(personal.cooldownUntil, DateTime.utc(2026, 9, 20));
  });

  test('every key exhausted → FailureKind.quota with the midnight message', () async {
    final c = client((_) async => apiError(429, 'RESOURCE_EXHAUSTED', 'quota'));
    await expectLater(
      c.generate(request, parse: (j) => j),
      throwsA(
        isA<AppFailure>()
            .having((f) => f.kind, 'kind', FailureKind.quota)
            .having((f) => f.message, 'message', contains('midnight UTC')),
      ),
    );
  });

  test('an invalid key is marked, skipped, and named in the error', () async {
    final c = client((_) async => apiError(400, 'INVALID_ARGUMENT', 'API key not valid. Please pass a valid API key.'));
    await expectLater(
      c.generate(request, parse: (j) => j),
      throwsA(
        isA<AppFailure>()
            .having((f) => f.kind, 'kind', FailureKind.permission)
            .having((f) => f.message, 'message', contains('"Personal"'))
            .having((f) => f.message, 'message', isNot(contains(secret))),
      ),
    );
    expect(keys.keys.single.status, KeyStatus.invalid);
    // Nothing healthy left: the next call does not even try the network.
    var sent = 0;
    final c2 = client((_) async {
      sent++;
      return ok(candidate('{}'));
    });
    await expectLater(c2.generate(request, parse: (j) => j), throwsA(isA<AppFailure>()));
    expect(sent, 0);
  });

  test('a 404 model is "no longer available"', () async {
    final c = client((_) async => apiError(404, 'NOT_FOUND', 'models/gemini-test is not found'));
    await expectLater(
      c.generate(request, parse: (j) => j),
      throwsA(isA<AppFailure>().having((f) => f.message, 'message', contains('no longer available'))),
    );
  });

  test('offline short-circuits before any request', () async {
    var sent = 0;
    final c = client((_) async {
      sent++;
      return ok(candidate('{}'));
    }, offline: ValueNotifier(true));
    await expectLater(
      c.generate(request, parse: (j) => j),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.offline)),
    );
    expect(sent, 0);
  });

  test('no keys at all is a clear permission failure', () async {
    await keys.clear();
    final c = client((_) async => ok(candidate('{}')));
    await expectLater(
      c.generate(request, parse: (j) => j),
      throwsA(isA<AppFailure>().having((f) => f.message, 'message', contains('More → AI'))),
    );
  });

  test('a GeminiException never carries the key', () async {
    final c = client((_) async => apiError(500, 'INTERNAL', 'boom $secret'));
    try {
      await c.generate(request, parse: (j) => j);
      fail('expected failure');
    } on AppFailure catch (f) {
      final cause = f.cause;
      expect(cause, isA<GeminiException>());
      // The message echoes Google's body verbatim, which is the one place a
      // secret could leak back in — so the toString still must not.
      expect((cause! as GeminiException).keyLabel, 'Personal');
      expect(cause.toString(), isNot(contains('secret-secret')));
    }
  });

  group('files API', () {
    test('resumable upload, then cache hit inside 47h and miss after', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = GeminiFileCache(prefs, now: () => now);
      final file = File('${Directory.systemTemp.path}/gemini_test_${DateTime.now().microsecondsSinceEpoch}.pdf');
      await file.writeAsBytes(utf8.encode('%PDF-1.4 fake'));
      addTearDown(() => file.delete());

      var uploads = 0;
      final c = client((req) async {
        if (req.url.path == '/upload/v1beta/files') {
          uploads++;
          expect(req.headers['X-Goog-Upload-Command'], 'start');
          expect(req.headers['X-Goog-Upload-Header-Content-Type'], 'application/pdf');
          return http.Response('{}', 200, headers: {'x-goog-upload-url': 'https://upload.test/session'});
        }
        if (req.url.host == 'upload.test') {
          expect(req.headers['X-Goog-Upload-Command'], 'upload, finalize');
          return ok({
            'file': {'name': 'files/abc', 'uri': 'https://files/abc', 'state': 'PROCESSING'},
          });
        }
        if (req.url.path == '/v1beta/files/abc') {
          return ok({'name': 'files/abc', 'uri': 'https://files/abc', 'state': 'ACTIVE'});
        }
        fail('unexpected ${req.url}');
      }, fileCache: cache);
      final key = keys.keys.single;

      final uri = await c.uploadFile(file, mimeType: 'application/pdf', key: key, cacheKey: 'att-1');
      expect(uri, 'https://files/abc');
      expect(uploads, 1);

      now = now.add(const Duration(hours: 46));
      expect(await c.uploadFile(file, mimeType: 'application/pdf', key: key, cacheKey: 'att-1'), uri);
      expect(uploads, 1);

      now = now.add(const Duration(hours: 2));
      await c.uploadFile(file, mimeType: 'application/pdf', key: key, cacheKey: 'att-1');
      expect(uploads, 2);

      // A different key never sees another key's upload.
      expect(cache.lookup('att-1', 'other-key'), isNull);
    });
  });

  test('countTokens reads totalTokens', () async {
    final c = client((req) async {
      expect(req.url.path, endsWith(':countTokens'));
      return ok({'totalTokens': 1234});
    });
    expect(await c.countTokens(request), 1234);
  });

  test('listModels verifies a pasted key without touching the store', () async {
    final c = client((req) async {
      expect(req.headers['x-goog-api-key'], 'AIza-new');
      return ok({
        'models': [
          {'name': 'models/gemini-3.8-flash', 'displayName': 'Flash', 'supportedGenerationMethods': ['generateContent']},
          {'name': 'models/embedding-1', 'displayName': 'Embed', 'supportedGenerationMethods': ['embedContent']},
        ],
      });
    });
    final models = await c.listModels(verify: 'AIza-new');
    expect(models.map((m) => m.id), ['embedding-1', 'gemini-3.8-flash']);
    expect(models.where((m) => m.supportsGenerate).single.id, 'gemini-3.8-flash');
    expect(keys.keys.single.requestCount, 0);
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
