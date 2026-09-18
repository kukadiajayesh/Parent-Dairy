import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../errors/app_failure.dart';

enum KeyStatus {
  active('active', 'Active'),
  invalid('invalid', 'Invalid'),
  exhausted('exhausted', 'Daily limit reached'),
  disabled('disabled', 'Off');

  const KeyStatus(this.wire, this.label);
  final String wire;
  final String label;

  static KeyStatus fromWire(String? value) => switch (value) {
    'invalid' => KeyStatus.invalid,
    'exhausted' => KeyStatus.exhausted,
    'disabled' => KeyStatus.disabled,
    _ => KeyStatus.active,
  };
}

/// One Google AI Studio key the parent pasted in.
///
/// [secret] is never rendered, never logged and never interpolated into an
/// error: [toString] shows the label and status only, and the client maps
/// every failure through [GeminiKeyStore] by *id*.
@immutable
class GeminiKey {
  const GeminiKey({
    required this.id,
    required this.label,
    required this.secret,
    this.status = KeyStatus.active,
    this.cooldownUntil,
    this.lastUsedAt,
    this.lastErrorAt,
    this.requestCount = 0,
    this.failureCount = 0,
    this.lastErrorMessage,
    this.monthStamp = '',
    this.monthRequests = 0,
  });

  final String id;
  final String label;
  final String secret;
  final KeyStatus status;

  /// Set when a 429 exhausted it; the key is healthy again once this passes.
  final DateTime? cooldownUntil;
  final DateTime? lastUsedAt;
  final DateTime? lastErrorAt;
  final int requestCount;
  final int failureCount;
  final String? lastErrorMessage;

  /// `2026-09` — which month [monthRequests] counts. Rolls over on use.
  final String monthStamp;
  final int monthRequests;

  /// `AIza••••••7f2c` — first 4 and last 4 only.
  String get masked {
    if (secret.length < 12) return '••••••••';
    return '${secret.substring(0, 4)}••••••${secret.substring(secret.length - 4)}';
  }

  /// Requests this calendar month, zero if the stamp is stale.
  int requestsThisMonth(DateTime now) =>
      monthStamp == stampFor(now) ? monthRequests : 0;

  static String stampFor(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}';

  /// Usable right now: active (or exhausted but past its cooldown).
  bool isHealthy(DateTime now) {
    if (status == KeyStatus.invalid || status == KeyStatus.disabled) {
      return false;
    }
    final until = cooldownUntil;
    return until == null || !now.isBefore(until);
  }

  /// What the status pill shows — an exhausted key whose cooldown has lapsed
  /// reads as active again without a write.
  KeyStatus effectiveStatus(DateTime now) =>
      status == KeyStatus.exhausted && isHealthy(now)
      ? KeyStatus.active
      : status;

  GeminiKey copyWith({
    String? label,
    String? secret,
    KeyStatus? status,
    DateTime? cooldownUntil,
    DateTime? lastUsedAt,
    DateTime? lastErrorAt,
    int? requestCount,
    int? failureCount,
    String? lastErrorMessage,
    String? monthStamp,
    int? monthRequests,
    bool clearCooldown = false,
    bool clearError = false,
  }) => GeminiKey(
    id: id,
    label: label ?? this.label,
    secret: secret ?? this.secret,
    status: status ?? this.status,
    cooldownUntil: clearCooldown ? null : (cooldownUntil ?? this.cooldownUntil),
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    lastErrorAt: clearError ? null : (lastErrorAt ?? this.lastErrorAt),
    requestCount: requestCount ?? this.requestCount,
    failureCount: failureCount ?? this.failureCount,
    lastErrorMessage: clearError
        ? null
        : (lastErrorMessage ?? this.lastErrorMessage),
    monthStamp: monthStamp ?? this.monthStamp,
    monthRequests: monthRequests ?? this.monthRequests,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'secret': secret,
    'status': status.wire,
    'cooldownUntil': cooldownUntil?.toIso8601String(),
    'lastUsedAt': lastUsedAt?.toIso8601String(),
    'lastErrorAt': lastErrorAt?.toIso8601String(),
    'requestCount': requestCount,
    'failureCount': failureCount,
    'lastErrorMessage': lastErrorMessage,
    'monthStamp': monthStamp,
    'monthRequests': monthRequests,
  };

  factory GeminiKey.fromJson(Map<String, Object?> m) => GeminiKey(
    id: (m['id'] ?? '').toString(),
    label: (m['label'] ?? 'Key').toString(),
    secret: (m['secret'] ?? '').toString(),
    status: KeyStatus.fromWire(m['status'] as String?),
    cooldownUntil: DateTime.tryParse((m['cooldownUntil'] ?? '').toString()),
    lastUsedAt: DateTime.tryParse((m['lastUsedAt'] ?? '').toString()),
    lastErrorAt: DateTime.tryParse((m['lastErrorAt'] ?? '').toString()),
    requestCount: (m['requestCount'] as num?)?.toInt() ?? 0,
    failureCount: (m['failureCount'] as num?)?.toInt() ?? 0,
    lastErrorMessage: m['lastErrorMessage'] as String?,
    monthStamp: (m['monthStamp'] ?? '').toString(),
    monthRequests: (m['monthRequests'] as num?)?.toInt() ?? 0,
  );

  @override
  String toString() => 'GeminiKey($label · ${status.wire})';
}

/// Where the key blob lives. The real one is the platform keystore; tests
/// use memory.
abstract class KeyStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Android Keystore / iOS Keychain via `flutter_secure_storage`. One blob
/// under one key so metadata and secret can never be read apart.
class SecureKeyStorage implements KeyStorage {
  SecureKeyStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'ai.keys.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete() => _storage.delete(key: key);
}

class MemoryKeyStorage implements KeyStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

/// The parent's Gemini keys, in priority order, with their health.
///
/// Rotation policy (prompt 02 §A): [nextHealthy] returns the first key in
/// parent order that is active and past its cooldown. A 429 puts a key on
/// cooldown until the next UTC midnight, when Google's free-tier daily quota
/// resets; an invalid key is skipped until the parent fixes it.
class GeminiKeyStore extends ChangeNotifier {
  GeminiKeyStore({KeyStorage? storage, DateTime Function()? now})
    : _storage = storage ?? SecureKeyStorage(),
      _now = now ?? DateTime.now;

  final KeyStorage _storage;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  List<GeminiKey> _keys = const [];
  bool _loaded = false;
  AppFailure? _loadError;

  List<GeminiKey> get keys => List.unmodifiable(_keys);
  bool get isLoaded => _loaded;
  bool get isEmpty => _keys.isEmpty;

  /// Non-null when the platform keystore could not be read — shown in
  /// settings rather than pretending the parent has no keys.
  AppFailure? get loadError => _loadError;

  int get healthyCount => _keys.where((k) => k.isHealthy(_now())).length;

  GeminiKey? byId(String id) => _keys.where((k) => k.id == id).firstOrNull;

  Future<void> load() async {
    try {
      final raw = await _storage.read();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        final list = decoded is Map ? decoded['keys'] : decoded;
        _keys = [
          if (list is List)
            for (final e in list)
              if (e is Map) GeminiKey.fromJson(Map<String, Object?>.from(e)),
        ];
      }
      _loadError = null;
    } catch (error) {
      // A keystore that refuses to open (a fresh device restore, a missing
      // platform channel in a test) must not look like "no keys".
      _loadError = AppFailure(
        FailureKind.unknown,
        'Saved keys could not be read from this phone\'s secure storage.',
        cause: error,
      );
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final blob = jsonEncode({
      'version': 1,
      'keys': [for (final k in _keys) k.toJson()],
    });
    await _storage.write(blob);
    notifyListeners();
  }

  /// Adds a key the caller has already verified against `models.list`.
  Future<GeminiKey> add({required String label, required String secret}) async {
    final key = GeminiKey(
      id: _uuid.v4(),
      label: label.trim().isEmpty ? 'Key ${_keys.length + 1}' : label.trim(),
      secret: secret.trim(),
    );
    _keys = [..._keys, key];
    await _persist();
    return key;
  }

  Future<void> rename(String id, String label) =>
      _update(id, (k) => k.copyWith(label: label.trim()));

  Future<void> remove(String id) async {
    _keys = _keys.where((k) => k.id != id).toList();
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) => _update(
    id,
    (k) => k.copyWith(
      status: enabled ? KeyStatus.active : KeyStatus.disabled,
      clearCooldown: enabled,
      clearError: enabled,
    ),
  );

  Future<void> reorder(List<String> orderedIds) async {
    final byId = {for (final k in _keys) k.id: k};
    _keys = [
      for (final id in orderedIds) ?byId.remove(id),
      ...byId.values,
    ];
    await _persist();
  }

  Future<void> markUsed(String id) {
    final now = _now();
    final stamp = GeminiKey.stampFor(now);
    return _update(
      id,
      (k) => k.copyWith(
        lastUsedAt: now,
        requestCount: k.requestCount + 1,
        monthStamp: stamp,
        monthRequests: k.monthStamp == stamp ? k.monthRequests + 1 : 1,
        // A successful call proves an "exhausted" key is back.
        status: k.status == KeyStatus.exhausted ? KeyStatus.active : k.status,
        clearCooldown: k.status == KeyStatus.exhausted,
      ),
    );
  }

  /// A 429: off the rotation until [cooldown] has elapsed.
  Future<void> markExhausted(String id, Duration cooldown) {
    final now = _now();
    return _update(
      id,
      (k) => k.copyWith(
        status: KeyStatus.exhausted,
        cooldownUntil: now.add(cooldown),
        lastErrorAt: now,
        failureCount: k.failureCount + 1,
        lastErrorMessage: 'Daily limit reached',
      ),
    );
  }

  Future<void> markInvalid(String id, String reason) {
    final now = _now();
    return _update(
      id,
      (k) => k.copyWith(
        status: KeyStatus.invalid,
        lastErrorAt: now,
        failureCount: k.failureCount + 1,
        lastErrorMessage: reason,
      ),
    );
  }

  /// Clears an invalid mark — after the parent replaced or fixed the key.
  Future<void> markActive(String id) => _update(
    id,
    (k) => k.copyWith(status: KeyStatus.active, clearCooldown: true, clearError: true),
  );

  /// The key to use next, or null when none is usable.
  ///
  /// First in parent order that is healthy. Two never-used keys tie on
  /// recency and the earlier one wins, so the parent's ordering is the
  /// priority and the rotation on 429 is what shares the daily load.
  GeminiKey? nextHealthy({Set<String> exclude = const {}}) {
    final now = _now();
    for (final key in _keys) {
      if (exclude.contains(key.id)) continue;
      if (key.isHealthy(now)) return key;
    }
    return null;
  }

  /// Until Google's free-tier daily quota resets.
  Duration untilUtcMidnight() {
    final now = _now().toUtc();
    final midnight = DateTime.utc(now.year, now.month, now.day + 1);
    return midnight.difference(now);
  }

  /// Wipes every key — "Revoke" in settings.
  Future<void> clear() async {
    _keys = const [];
    await _storage.delete();
    notifyListeners();
  }

  Future<void> _update(String id, GeminiKey Function(GeminiKey) change) async {
    var changed = false;
    _keys = [
      for (final k in _keys)
        if (k.id == id) ...[change(k)] else k,
    ];
    changed = _keys.any((k) => k.id == id);
    if (changed) await _persist();
  }
}
