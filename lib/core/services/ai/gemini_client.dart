import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../errors/app_failure.dart';
import 'ai_models.dart';
import 'gemini_key_store.dart';

/// Lets a long call be abandoned from the progress UI. Cancelling closes the
/// HTTP client behind the in-flight request, so the socket is actually torn
/// down rather than left to finish in the background.
class CancellationToken {
  final Completer<void> _completer = Completer<void>();
  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw AppFailure.cancelled;
  }
}

// ── Request shape ─────────────────────────────────────────────────────────

sealed class GeminiPart {
  const GeminiPart();
  Map<String, Object?> toJson();
}

final class TextPart extends GeminiPart {
  const TextPart(this.text);
  final String text;
  @override
  Map<String, Object?> toJson() => {'text': text};
}

final class InlineDataPart extends GeminiPart {
  const InlineDataPart({required this.mimeType, required this.base64Data});
  final String mimeType;
  final String base64Data;
  @override
  Map<String, Object?> toJson() => {
    'inlineData': {'mimeType': mimeType, 'data': base64Data},
  };
}

final class FileDataPart extends GeminiPart {
  const FileDataPart({required this.mimeType, required this.fileUri});
  final String mimeType;
  final String fileUri;
  @override
  Map<String, Object?> toJson() => {
    'fileData': {'mimeType': mimeType, 'fileUri': fileUri},
  };
}

class GeminiRequest {
  const GeminiRequest({
    required this.model,
    required this.parts,
    this.systemInstruction,
    this.responseSchema,
    this.temperature = 0.4,
    this.maxOutputTokens,
    this.timeout = const Duration(seconds: 90),
  });

  final String model;
  final List<GeminiPart> parts;
  final String? systemInstruction;

  /// Structured output. Every production call sets one (prompt 02 §B.1);
  /// null is allowed only so `countTokens` can reuse the same shape.
  final Map<String, Object?>? responseSchema;
  final double temperature;
  final int? maxOutputTokens;

  /// 90s by default, 180s for vision batches.
  final Duration timeout;

  GeminiRequest copyWith({List<GeminiPart>? parts, String? model}) =>
      GeminiRequest(
        model: model ?? this.model,
        parts: parts ?? this.parts,
        systemInstruction: systemInstruction,
        responseSchema: responseSchema,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        timeout: timeout,
      );

  Map<String, Object?> toJson() => {
    'contents': [
      {
        'role': 'user',
        'parts': [for (final p in parts) p.toJson()],
      },
    ],
    if (systemInstruction != null)
      'systemInstruction': {
        'parts': [
          {'text': systemInstruction},
        ],
      },
    'generationConfig': {
      'temperature': temperature,
      if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
      if (responseSchema != null) ...{
        'responseMimeType': 'application/json',
        'responseSchema': responseSchema,
      },
    },
  };

  /// The same content without generation settings — what `countTokens` wants.
  Map<String, Object?> toCountJson() => {
    'contents': [
      {
        'role': 'user',
        'parts': [for (final p in parts) p.toJson()],
      },
    ],
    if (systemInstruction != null)
      'systemInstruction': {
        'parts': [
          {'text': systemInstruction},
        ],
      },
  };
}

class GeminiUsage {
  const GeminiUsage({this.promptTokens = 0, this.responseTokens = 0});
  final int promptTokens;
  final int responseTokens;
}

/// A parsed reply plus what it cost and which key paid for it.
class GeminiResult<T> {
  const GeminiResult({
    required this.value,
    required this.usage,
    required this.model,
    required this.keyLabel,
    required this.keyId,
    required this.duration,
  });

  final T value;
  final GeminiUsage usage;
  final String model;
  final String keyLabel;
  final String keyId;
  final Duration duration;
}

// ── Errors ────────────────────────────────────────────────────────────────

enum GeminiErrorKind {
  invalidKey,
  quota,
  unavailable,
  modelNotFound,
  blocked,
  recitation,
  maxTokens,
  malformed,
  badRequest,
  timeout,
  network,
  unknown,
}

/// A failure below the parent-facing layer. Carries the key's *label*,
/// never its secret — asserted by `gemini_client_test`.
class GeminiException implements Exception {
  const GeminiException(
    this.kind,
    this.message, {
    this.statusCode,
    this.keyLabel,
    this.model,
  });

  final GeminiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? keyLabel;
  final String? model;

  bool get isRetryableOnSameKey => kind == GeminiErrorKind.unavailable;

  AppFailure toFailure() => switch (kind) {
    GeminiErrorKind.invalidKey => AppFailure(
      FailureKind.permission,
      keyLabel == null
          ? 'That Gemini key is not valid. Check it in More → AI.'
          : 'The Gemini key "$keyLabel" was rejected by Google. Replace it in '
                'More → AI.',
      cause: this,
      canRetry: false,
    ),
    GeminiErrorKind.quota => AppFailure(
      FailureKind.quota,
      "Every Gemini key has hit today's limit. Add another key or try after "
      'midnight UTC.',
      cause: this,
      canRetry: false,
    ),
    GeminiErrorKind.unavailable => AppFailure(
      FailureKind.unknown,
      'Gemini is busy right now. Try again in a minute.',
      cause: this,
    ),
    GeminiErrorKind.modelNotFound => AppFailure(
      FailureKind.notFound,
      'That model is no longer available — pick another in More → AI → Models.',
      cause: this,
      canRetry: false,
    ),
    GeminiErrorKind.blocked => AppFailure(
      FailureKind.unknown,
      "Gemini declined this request as unsafe. Try different pages, or fewer "
      'of them.',
      cause: this,
      canRetry: false,
    ),
    GeminiErrorKind.recitation => AppFailure(
      FailureKind.unknown,
      'Gemini stopped because the answer would copy published material too '
      'closely. Try again with different chapters or pages.',
      cause: this,
    ),
    GeminiErrorKind.maxTokens => AppFailure(
      FailureKind.unknown,
      'The reply was too long to finish. Ask for fewer questions or fewer '
      'pages and try again.',
      cause: this,
    ),
    GeminiErrorKind.malformed => AppFailure(
      FailureKind.unknown,
      "Gemini returned something the app couldn't read. Try again.",
      cause: this,
    ),
    GeminiErrorKind.badRequest => AppFailure(
      FailureKind.invalidFile,
      message.isEmpty ? 'Gemini could not accept this request.' : message,
      cause: this,
      canRetry: false,
    ),
    GeminiErrorKind.timeout => AppFailure(
      FailureKind.unknown,
      'Gemini took too long to reply. Try fewer pages, or try again.',
      cause: this,
    ),
    GeminiErrorKind.network => AppFailure(
      FailureKind.offline,
      'No internet connection. Check your network and try again.',
      cause: this,
    ),
    GeminiErrorKind.unknown => AppFailure(
      FailureKind.unknown,
      message.isEmpty ? 'Something went wrong talking to Gemini.' : message,
      cause: this,
    ),
  };

  @override
  String toString() =>
      'GeminiException(${kind.name}${statusCode == null ? '' : ' $statusCode'}: '
      '$message)';
}

// ── Files API cache ───────────────────────────────────────────────────────

/// `attachmentId:keyId → (fileUri, expiresAt)`. Uploaded files live 48h on
/// Google's side; the cache keeps them for 47h so a second generation from
/// the same worksheets does not re-upload them. Keyed by the API key too,
/// because a file is only visible to the project that uploaded it.
class GeminiFileCache {
  GeminiFileCache(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const key = 'ai.files.v1';
  static const ttl = Duration(hours: 47);

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  Map<String, Object?> _read() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  String? lookup(String cacheKey, String keyId) {
    final entry = _read()['$cacheKey:$keyId'];
    if (entry is! Map) return null;
    final expires = DateTime.tryParse((entry['expiresAt'] ?? '').toString());
    if (expires == null || !_now().isBefore(expires)) return null;
    return entry['uri'] as String?;
  }

  Future<void> store(String cacheKey, String keyId, String uri) async {
    final all = _read();
    final now = _now();
    // Drop anything already expired while we are here.
    all.removeWhere((_, v) {
      if (v is! Map) return true;
      final expires = DateTime.tryParse((v['expiresAt'] ?? '').toString());
      return expires == null || !now.isBefore(expires);
    });
    all['$cacheKey:$keyId'] = {
      'uri': uri,
      'expiresAt': now.add(ttl).toIso8601String(),
    };
    await _prefs.setString(key, jsonEncode(all));
  }

  Future<void> clear() => _prefs.remove(key);
}

// ── Client ────────────────────────────────────────────────────────────────

/// A ~400-line REST client for `generativelanguage.googleapis.com/v1beta`.
///
/// Why not a package: the parent supplies their own key, so `firebase_ai`
/// (bills the Firebase project) is the wrong shape, and a raw client gives
/// direct control of retries, key rotation and cancellation.
// ignore_for_file: prefer_initializing_formals — public parameter names,
// private fields.
class GeminiClient {
  GeminiClient({
    required GeminiKeyStore keys,
    http.Client Function()? clientFactory,
    ValueListenable<bool>? offline,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    GeminiFileCache? fileCache,
    String baseUrl = 'https://generativelanguage.googleapis.com',
  }) : _keys = keys,
       _clientFactory = clientFactory ?? http.Client.new,
       _offline = offline,
       _now = now ?? DateTime.now,
       _delay = delay ?? ((d) => Future<void>.delayed(d)),
       _fileCache = fileCache,
       _baseUrl = baseUrl;

  final GeminiKeyStore _keys;
  final http.Client Function() _clientFactory;
  final ValueListenable<bool>? _offline;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final GeminiFileCache? _fileCache;
  final String _baseUrl;

  /// 250ms, 1s, 3s — with up to 30% jitter so two devices retrying a 503
  /// do not line up.
  static const backoff = [
    Duration(milliseconds: 250),
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];
  static const int maxAttemptsPerKey = 3;

  static const _modelsCacheKey = 'ai.models.v1';
  static const modelsCacheTtl = Duration(hours: 24);

  final math.Random _random = math.Random();

  GeminiKeyStore get keys => _keys;

  // ── key rotation ────────────────────────────────────────────────────────

  /// Runs [body] under the first healthy key, failing over on quota or an
  /// invalid key, so an upload and the generation that uses it share a key.
  Future<T> withKey<T>(
    Future<T> Function(GeminiKey key) body, {
    CancellationToken? cancel,
  }) async {
    _checkOffline();
    cancel?.throwIfCancelled();
    if (_keys.keys.isEmpty) {
      throw const AppFailure(
        FailureKind.permission,
        'Add a Gemini API key in More → AI to use this.',
        canRetry: false,
      );
    }

    final tried = <String>{};
    // The last reason a key was passed over. When nothing is left it
    // decides the message: a lone key that kept returning 503 is "busy",
    // not "out of quota".
    GeminiException? last;
    while (true) {
      final key = _keys.nextHealthy(exclude: tried);
      if (key == null) {
        if (last != null && last.kind != GeminiErrorKind.quota) {
          throw last.toFailure();
        }
        throw const GeminiException(GeminiErrorKind.quota, 'all keys exhausted')
            .toFailure();
      }
      tried.add(key.id);
      try {
        final result = await body(key);
        await _keys.markUsed(key.id);
        return result;
      } on GeminiException catch (error) {
        last = GeminiException(
          error.kind,
          error.message,
          statusCode: error.statusCode,
          keyLabel: key.label,
          model: error.model,
        );
        switch (error.kind) {
          case GeminiErrorKind.quota:
            await _keys.markExhausted(key.id, _keys.untilUtcMidnight());
            continue;
          case GeminiErrorKind.invalidKey:
            await _keys.markInvalid(key.id, error.message);
            continue;
          case GeminiErrorKind.unavailable:
            // Backoff on the same key already happened inside the request;
            // fall over to the next one.
            continue;
          default:
            throw last.toFailure();
        }
      }
    }
  }

  // ── generateContent ─────────────────────────────────────────────────────

  Future<GeminiResult<T>> generate<T>(
    GeminiRequest request, {
    required T Function(Map<String, Object?> json) parse,
    CancellationToken? cancel,
    GeminiKey? key,
  }) {
    if (key != null) return _generateWith(request, key, parse: parse, cancel: cancel);
    return withKey(
      (k) => _generateWith(request, k, parse: parse, cancel: cancel),
      cancel: cancel,
    );
  }

  Future<GeminiResult<T>> _generateWith<T>(
    GeminiRequest request,
    GeminiKey key, {
    required T Function(Map<String, Object?> json) parse,
    CancellationToken? cancel,
  }) async {
    final started = _now();
    final reply = await _post(
      '/v1beta/models/${request.model}:generateContent',
      request.toJson(),
      key: key,
      timeout: request.timeout,
      cancel: cancel,
      model: request.model,
    );

    var text = _textOf(reply, key, request.model);
    var usage = _usageOf(reply);
    Map<String, Object?>? json = _tryDecode(text);

    if (json == null) {
      // One repair pass, text only: the images are not resent, the broken
      // reply is. Cheaper than a full retry and usually enough.
      final repair = request.copyWith(
        parts: [
          TextPart(
            'Your previous reply was not valid JSON:\n\n$text\n\n'
            'Return only valid JSON matching this schema.',
          ),
        ],
      );
      final second = await _post(
        '/v1beta/models/${request.model}:generateContent',
        repair.toJson(),
        key: key,
        timeout: request.timeout,
        cancel: cancel,
        model: request.model,
      );
      text = _textOf(second, key, request.model);
      final u2 = _usageOf(second);
      usage = GeminiUsage(
        promptTokens: usage.promptTokens + u2.promptTokens,
        responseTokens: usage.responseTokens + u2.responseTokens,
      );
      json = _tryDecode(text);
      if (json == null) {
        throw GeminiException(
          GeminiErrorKind.malformed,
          'reply was not JSON after repair',
          keyLabel: key.label,
          model: request.model,
        );
      }
    }

    final T value;
    try {
      value = parse(json);
    } catch (error) {
      throw GeminiException(
        GeminiErrorKind.malformed,
        'reply did not match the expected shape: $error',
        keyLabel: key.label,
        model: request.model,
      );
    }
    return GeminiResult(
      value: value,
      usage: usage,
      model: request.model,
      keyLabel: key.label,
      keyId: key.id,
      duration: _now().difference(started),
    );
  }

  Future<int> countTokens(
    GeminiRequest request, {
    CancellationToken? cancel,
    GeminiKey? key,
  }) async {
    Future<int> run(GeminiKey k) async {
      final reply = await _post(
        '/v1beta/models/${request.model}:countTokens',
        request.toCountJson(),
        key: k,
        timeout: const Duration(seconds: 30),
        cancel: cancel,
        model: request.model,
      );
      return (reply['totalTokens'] as num?)?.toInt() ?? 0;
    }

    if (key != null) return run(key);
    return withKey(run, cancel: cancel);
  }

  // ── models.list ─────────────────────────────────────────────────────────

  /// Models the key can call. With [verify] set, the given secret is used
  /// directly and nothing is cached — that is the "Verify" action in the
  /// add-key sheet, which must succeed before a key is stored.
  Future<List<GeminiModel>> listModels({
    String? verify,
    bool forceRefresh = false,
    SharedPreferences? cache,
    CancellationToken? cancel,
  }) async {
    if (verify != null) {
      final reply = await _get(
        '/v1beta/models?pageSize=200',
        secret: verify,
        keyLabel: 'new key',
        cancel: cancel,
      );
      return _modelsOf(reply);
    }

    if (!forceRefresh && cache != null) {
      final cached = _cachedModels(cache);
      if (cached != null) return cached;
    }

    final models = await withKey(
      (k) async => _modelsOf(
        await _get(
          '/v1beta/models?pageSize=200',
          secret: k.secret,
          keyLabel: k.label,
          cancel: cancel,
        ),
      ),
      cancel: cancel,
    );
    if (cache != null) {
      await cache.setString(
        _modelsCacheKey,
        jsonEncode({
          'at': _now().toIso8601String(),
          'models': [for (final m in models) m.toJson()],
        }),
      );
    }
    return models;
  }

  List<GeminiModel>? _cachedModels(SharedPreferences cache) {
    try {
      final raw = cache.getString(_modelsCacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final at = DateTime.tryParse((decoded['at'] ?? '').toString());
      if (at == null || _now().difference(at) > modelsCacheTtl) return null;
      final list = decoded['models'];
      return [
        if (list is List)
          for (final e in list)
            if (e is Map) GeminiModel.fromJson(Map<String, Object?>.from(e)),
      ];
    } catch (_) {
      return null;
    }
  }

  List<GeminiModel> _modelsOf(Map<String, Object?> reply) {
    final list = reply['models'];
    return [
      if (list is List)
        for (final e in list)
          if (e is Map) GeminiModel.fromJson(Map<String, Object?>.from(e)),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  // ── Files API ───────────────────────────────────────────────────────────

  /// Uploads [file] with the resumable protocol and returns its `fileUri`.
  /// Waits for a PDF to finish server-side processing before returning, so
  /// the generate call that follows never sees a `PROCESSING` file.
  Future<String> uploadFile(
    File file, {
    required String mimeType,
    required GeminiKey key,
    String? cacheKey,
    String? displayName,
    CancellationToken? cancel,
  }) async {
    final cache = _fileCache;
    if (cacheKey != null && cache != null) {
      final hit = cache.lookup(cacheKey, key.id);
      if (hit != null) return hit;
    }

    final bytes = await file.readAsBytes();
    cancel?.throwIfCancelled();

    final start = await _send(
      http.Request('POST', Uri.parse('$_baseUrl/upload/v1beta/files'))
        ..headers.addAll({
          'x-goog-api-key': key.secret,
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'start',
          'X-Goog-Upload-Header-Content-Length': '${bytes.length}',
          'X-Goog-Upload-Header-Content-Type': mimeType,
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({
          'file': {'display_name': displayName ?? 'attachment'},
        }),
      keyLabel: key.label,
      timeout: const Duration(seconds: 60),
      cancel: cancel,
    );
    final uploadUrl =
        start.headers['x-goog-upload-url'] ?? start.headers['X-Goog-Upload-URL'];
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw GeminiException(
        GeminiErrorKind.unknown,
        'upload start returned no upload URL',
        keyLabel: key.label,
      );
    }

    final finish = await _send(
      http.Request('POST', Uri.parse(uploadUrl))
        ..headers.addAll({
          'x-goog-api-key': key.secret,
          'X-Goog-Upload-Offset': '0',
          'X-Goog-Upload-Command': 'upload, finalize',
          'Content-Length': '${bytes.length}',
        })
        ..bodyBytes = bytes,
      keyLabel: key.label,
      timeout: const Duration(minutes: 3),
      cancel: cancel,
    );
    final info = _fileOf(_decodeBody(finish, key.label));
    var uri = info.uri;
    var state = info.state;
    final name = info.name;

    // Small files are ACTIVE immediately; a PDF may need a few seconds.
    var polls = 0;
    while (state == 'PROCESSING' && polls < 30) {
      cancel?.throwIfCancelled();
      await _delay(const Duration(seconds: 1));
      polls++;
      final reply = await _get(
        '/v1beta/$name',
        secret: key.secret,
        keyLabel: key.label,
        cancel: cancel,
      );
      final again = _fileOf(reply);
      state = again.state;
      uri = again.uri.isEmpty ? uri : again.uri;
    }
    if (state == 'FAILED' || uri.isEmpty) {
      throw GeminiException(
        GeminiErrorKind.badRequest,
        'Gemini could not process that file.',
        keyLabel: key.label,
      );
    }
    if (cacheKey != null && cache != null) {
      await cache.store(cacheKey, key.id, uri);
    }
    return uri;
  }

  ({String name, String uri, String state}) _fileOf(Map<String, Object?> reply) {
    final file = reply['file'] is Map
        ? Map<String, Object?>.from(reply['file'] as Map)
        : reply;
    return (
      name: (file['name'] ?? '').toString(),
      uri: (file['uri'] ?? '').toString(),
      state: (file['state'] ?? 'ACTIVE').toString(),
    );
  }

  // ── HTTP plumbing ───────────────────────────────────────────────────────

  void _checkOffline() {
    if (_offline?.value ?? false) {
      throw const AppFailure(
        FailureKind.offline,
        'Generating needs an internet connection. Try again when you are '
        'back online.',
      );
    }
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body, {
    required GeminiKey key,
    required Duration timeout,
    required String model,
    CancellationToken? cancel,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final response = await _send(
          http.Request('POST', Uri.parse('$_baseUrl$path'))
            ..headers.addAll({
              'x-goog-api-key': key.secret,
              'Content-Type': 'application/json',
            })
            ..body = jsonEncode(body),
          keyLabel: key.label,
          timeout: timeout,
          cancel: cancel,
          model: model,
        );
        return _decodeBody(response, key.label);
      } on GeminiException catch (error) {
        if (!error.isRetryableOnSameKey || attempt >= maxAttemptsPerKey) {
          rethrow;
        }
        final base = backoff[attempt - 1];
        final jitter = (base.inMilliseconds * 0.3 * _random.nextDouble()).round();
        await _delay(base + Duration(milliseconds: jitter));
        cancel?.throwIfCancelled();
      }
    }
  }

  Future<Map<String, Object?>> _get(
    String path, {
    required String secret,
    required String keyLabel,
    CancellationToken? cancel,
  }) async {
    final response = await _send(
      http.Request('GET', Uri.parse('$_baseUrl$path'))
        ..headers['x-goog-api-key'] = secret,
      keyLabel: keyLabel,
      timeout: const Duration(seconds: 30),
      cancel: cancel,
    );
    return _decodeBody(response, keyLabel);
  }

  /// Sends one request on a fresh client, mapping every transport-level
  /// failure to a [GeminiException] and honouring [cancel] by closing the
  /// client mid-flight.
  Future<http.Response> _send(
    http.Request request, {
    required String keyLabel,
    required Duration timeout,
    CancellationToken? cancel,
    String? model,
  }) async {
    _checkOffline();
    cancel?.throwIfCancelled();
    final client = _clientFactory();
    var cancelled = false;
    void onCancel(_) {
      cancelled = true;
      client.close();
    }

    final cancelFuture = cancel?.whenCancelled.then(onCancel);
    try {
      final streamed = await client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed).timeout(timeout);
      if (cancelled) throw AppFailure.cancelled;
      _throwForStatus(
        response,
        keyLabel: keyLabel,
        model: model,
        secret: request.headers['x-goog-api-key'],
      );
      return response;
    } on TimeoutException {
      throw GeminiException(GeminiErrorKind.timeout, 'timed out', keyLabel: keyLabel);
    } on http.ClientException catch (error) {
      if (cancelled || (cancel?.isCancelled ?? false)) throw AppFailure.cancelled;
      throw GeminiException(GeminiErrorKind.network, error.message, keyLabel: keyLabel);
    } on SocketException catch (error) {
      if (cancelled) throw AppFailure.cancelled;
      throw GeminiException(GeminiErrorKind.network, error.message, keyLabel: keyLabel);
    } finally {
      cancelFuture?.ignore();
      client.close();
    }
  }

  void _throwForStatus(
    http.Response response, {
    required String keyLabel,
    String? model,
    String? secret,
  }) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;

    String status = '';
    String message = '';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        status = (error['status'] ?? '').toString();
        message = (error['message'] ?? '').toString();
      }
    } catch (_) {
      // Non-JSON error page; the status code alone decides.
    }
    // Google's error body is the one place the key could be echoed back;
    // it never rides along on an exception, a log line or a toast.
    if (secret != null && secret.isNotEmpty) {
      message = message.replaceAll(secret, '[key]');
    }

    final kind = switch (code) {
      429 => GeminiErrorKind.quota,
      _ when status == 'RESOURCE_EXHAUSTED' => GeminiErrorKind.quota,
      403 => GeminiErrorKind.invalidKey,
      401 => GeminiErrorKind.invalidKey,
      400 when _looksLikeBadKey(message, status) => GeminiErrorKind.invalidKey,
      404 => GeminiErrorKind.modelNotFound,
      500 || 502 || 503 || 504 => GeminiErrorKind.unavailable,
      _ when status == 'UNAVAILABLE' => GeminiErrorKind.unavailable,
      _ when code >= 400 && code < 500 => GeminiErrorKind.badRequest,
      _ => GeminiErrorKind.unknown,
    };
    throw GeminiException(
      kind,
      message.isEmpty ? 'HTTP $code' : message,
      statusCode: code,
      keyLabel: keyLabel,
      model: model,
    );
  }

  static bool _looksLikeBadKey(String message, String status) {
    final m = message.toLowerCase();
    return m.contains('api key') ||
        m.contains('api_key') ||
        status == 'PERMISSION_DENIED' ||
        status == 'UNAUTHENTICATED';
  }

  Map<String, Object?> _decodeBody(http.Response response, String keyLabel) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {
      // Fall through to the malformed error below.
    }
    throw GeminiException(
      GeminiErrorKind.malformed,
      'response body was not a JSON object',
      keyLabel: keyLabel,
    );
  }

  /// The candidate text, or the explained failure the reply encodes.
  String _textOf(Map<String, Object?> reply, GeminiKey key, String model) {
    final feedback = reply['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw GeminiException(
        GeminiErrorKind.blocked,
        'prompt blocked: ${feedback['blockReason']}',
        keyLabel: key.label,
        model: model,
      );
    }
    final candidates = reply['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw GeminiException(
        GeminiErrorKind.malformed,
        'no candidates in reply',
        keyLabel: key.label,
        model: model,
      );
    }
    final first = Map<String, Object?>.from(candidates.first as Map);
    final finish = (first['finishReason'] ?? '').toString();
    final content = first['content'];
    final parts = content is Map ? content['parts'] : null;
    final buffer = StringBuffer();
    if (parts is List) {
      for (final p in parts) {
        if (p is Map && p['text'] is String) buffer.write(p['text']);
      }
    }
    final text = buffer.toString();
    switch (finish) {
      case 'SAFETY':
        throw GeminiException(
          GeminiErrorKind.blocked,
          'reply blocked for safety',
          keyLabel: key.label,
          model: model,
        );
      case 'RECITATION':
        throw GeminiException(
          GeminiErrorKind.recitation,
          'reply stopped for recitation',
          keyLabel: key.label,
          model: model,
        );
      case 'MAX_TOKENS':
        // A truncated JSON body cannot be repaired by asking again; the
        // parent has to ask for less.
        throw GeminiException(
          GeminiErrorKind.maxTokens,
          'reply hit the output limit',
          keyLabel: key.label,
          model: model,
        );
    }
    return text;
  }

  GeminiUsage _usageOf(Map<String, Object?> reply) {
    final usage = reply['usageMetadata'];
    if (usage is! Map) return const GeminiUsage();
    return GeminiUsage(
      promptTokens: (usage['promptTokenCount'] as num?)?.toInt() ?? 0,
      responseTokens: (usage['candidatesTokenCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Decodes a reply, tolerating a ```json fence the model sometimes adds.
  static Map<String, Object?>? _tryDecode(String text) {
    var body = text.trim();
    if (body.startsWith('```')) {
      body = body.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      if (body.endsWith('```')) body = body.substring(0, body.length - 3);
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {
      // Try the widest {...} span — a stray sentence before the JSON.
      final start = body.indexOf('{');
      final end = body.lastIndexOf('}');
      if (start != -1 && end > start) {
        try {
          final decoded = jsonDecode(body.substring(start, end + 1));
          if (decoded is Map) return Map<String, Object?>.from(decoded);
        } catch (_) {}
      }
    }
    return null;
  }
}
