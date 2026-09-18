import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/feature_flags.dart';
import 'ai/ai_models.dart';

/// The handful of choices §37 says the app must remember between launches, so
/// a parent capturing a worksheet never re-picks the same child, year and
/// subject every time.
class PrefsService {
  PrefsService._(this._prefs);

  final SharedPreferences _prefs;

  static PrefsService? _instance;
  static PrefsService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('PrefsService.init() must run before first use');
    }
    return i;
  }

  /// Safe to call more than once; later calls are no-ops.
  static Future<PrefsService> init() async =>
      _instance ??= PrefsService._(await SharedPreferences.getInstance());

  /// Drops the singleton so a test that swapped the mock values gets a
  /// fresh instance instead of the previous test's preferences.
  @visibleForTesting
  static void reset() => _instance = null;

  static const _kDark = 'theme.dark';
  static const _kChildId = 'selection.childId';
  static const _kYear = 'selection.year';
  static const _kLastSubject = 'selection.lastSubject';
  static const _kOnboarded = 'onboarding.complete';
  static const _kReminders = 'notifications.enabled';

  bool get isDark => _prefs.getBool(_kDark) ?? false;
  Future<void> setDark(bool value) => _prefs.setBool(_kDark, value);

  String? get childId => _prefs.getString(_kChildId);
  Future<void> setChildId(String value) => _prefs.setString(_kChildId, value);

  String? get year => _prefs.getString(_kYear);
  Future<void> setYear(String value) => _prefs.setString(_kYear, value);

  /// Suggested first, per §11's "last-used subject as a suggestion".
  String? get lastSubject => _prefs.getString(_kLastSubject);
  Future<void> setLastSubject(String value) =>
      _prefs.setString(_kLastSubject, value);

  bool get hasOnboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded(bool value) => _prefs.setBool(_kOnboarded, value);

  bool get remindersEnabled => _prefs.getBool(_kReminders) ?? true;
  Future<void> setRemindersEnabled(bool value) =>
      _prefs.setBool(_kReminders, value);

  // ── AI (prompt 02) ───────────────────────────────────────────────────────
  //
  // The API keys themselves are NOT here — they live in the platform's secure
  // storage (`GeminiKeyStore`). These are the switches around them.

  static const _kAiEnabled = 'ai.enabled';
  static const _kAiConsentVersion = 'ai.consent.version';
  static const _kAiConsentAt = 'ai.consent.at';
  static const _kAiModelPrefix = 'ai.model.';

  /// The parent's runtime opt-in. Default off: nothing leaves the device
  /// until they flip it and accept the consent screen.
  bool get aiEnabled => _prefs.getBool(_kAiEnabled) ?? false;
  Future<void> setAiEnabled(bool value) => _prefs.setBool(_kAiEnabled, value);

  /// True when the accepted consent version is the current one. A bump in
  /// [kAiConsentVersion] re-asks.
  bool get aiConsented =>
      (_prefs.getInt(_kAiConsentVersion) ?? 0) >= kAiConsentVersion;
  DateTime? get aiConsentedAt {
    final ms = _prefs.getInt(_kAiConsentAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setAiConsented(bool value) async {
    if (value) {
      await _prefs.setInt(_kAiConsentVersion, kAiConsentVersion);
      await _prefs.setInt(_kAiConsentAt, DateTime.now().millisecondsSinceEpoch);
    } else {
      await _prefs.remove(_kAiConsentVersion);
      await _prefs.remove(_kAiConsentAt);
    }
  }

  /// The model chosen for a task, or the task's fallback default.
  String aiModelFor(AiTask task) =>
      _prefs.getString('$_kAiModelPrefix${task.name}') ?? task.defaultModel;
  Future<void> setAiModelFor(AiTask task, String? model) => model == null
      ? _prefs.remove('$_kAiModelPrefix${task.name}')
      : _prefs.setString('$_kAiModelPrefix${task.name}', model);

  /// The raw store, for the AI helpers that keep their own small JSON blobs
  /// (activity log, model list cache, uploaded-file cache) under their own
  /// `ai.*` keys. Nothing else should reach for this.
  SharedPreferences get raw => _prefs;

  /// Everything the AI layer keeps in preferences. Called by "Revoke" so the
  /// wipe is one operation the settings screen cannot half-do.
  Future<void> clearAiScoped() async {
    for (final key in _prefs.getKeys().where((k) => k.startsWith('ai.'))) {
      await _prefs.remove(key);
    }
  }

  /// Clears per-account selections on sign-out. Theme and onboarding are device
  /// preferences and deliberately survive.
  Future<void> clearAccountScoped() async {
    await _prefs.remove(_kChildId);
    await _prefs.remove(_kYear);
    await _prefs.remove(_kLastSubject);
  }
}
