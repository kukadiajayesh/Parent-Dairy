import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models.dart';
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

  // ── Notification capture (prompt 03) ────────────────────────────────────
  //
  // Device settings, not account data: which apps this phone watches, the
  // per-app rule, reminder offsets and the cost guards. The captured text
  // itself goes to Firestore, never here.

  static const _kNoticesEnabled = 'notices.enabled';
  static const _kNoticesEnabledAt = 'notices.enabledAt';
  static const _kNoticeDisclosureAt = 'notices.disclosure.at';
  static const _kNoticePackages = 'notices.packages';
  static const _kNoticeRules = 'notices.rules';
  static const _kNoticeChildMap = 'notices.childMap';
  static const _kNoticeOffsets = 'notices.offsets';
  static const _kNoticeRetentionDays = 'notices.retentionDays';
  static const _kNoticeAutoArmed = 'notices.autoArmed';
  static const _kNoticeAiDay = 'notices.ai.day';
  static const _kNoticeAiCount = 'notices.ai.count';
  static const _kNoticeBatteryHint = 'notices.batteryHintShown';
  static const _kNoticeInexactNoted = 'notices.inexactNoted';
  static const _kNoticeLastDrainAt = 'notices.lastDrainAt';

  bool get noticesEnabled => _prefs.getBool(_kNoticesEnabled) ?? false;
  Future<void> setNoticesEnabled(bool value) async {
    await _prefs.setBool(_kNoticesEnabled, value);
    if (value && _prefs.getInt(_kNoticesEnabledAt) == null) {
      await _prefs.setInt(_kNoticesEnabledAt, DateTime.now().millisecondsSinceEpoch);
    }
  }

  DateTime? get noticesEnabledAt => _millis(_kNoticesEnabledAt);

  /// When the §H disclosure was accepted. Null until the parent has read it.
  DateTime? get noticeDisclosureAt => _millis(_kNoticeDisclosureAt);
  Future<void> setNoticeDisclosureAccepted() =>
      _prefs.setInt(_kNoticeDisclosureAt, DateTime.now().millisecondsSinceEpoch);

  /// The opted-in package names, in the order the parent ticked them.
  List<String> get noticePackages => _prefs.getStringList(_kNoticePackages) ?? const [];
  Future<void> setNoticePackages(List<String> value) =>
      _prefs.setStringList(_kNoticePackages, value);

  Map<String, NoticeAppRule> get noticeRules => {
    for (final e in _jsonMap(_kNoticeRules).entries)
      e.key: NoticeAppRule.fromWire(e.value?.toString()),
  };
  Future<void> setNoticeRule(String packageName, NoticeAppRule rule) =>
      _setJsonMap(_kNoticeRules, {..._jsonMap(_kNoticeRules), packageName: rule.wire});

  /// package → childId, remembered the first time the parent picks a child
  /// for an app's notice (§F).
  Map<String, String> get noticeChildMap => {
    for (final e in _jsonMap(_kNoticeChildMap).entries) e.key: e.value.toString(),
  };
  Future<void> setNoticeChild(String packageName, String childId) =>
      _setJsonMap(_kNoticeChildMap, {..._jsonMap(_kNoticeChildMap), packageName: childId});

  /// Reminder offsets per kind, or null to use the defaults.
  Map<NoticeKind, List<int>>? get noticeOffsets {
    final raw = _jsonMap(_kNoticeOffsets);
    if (raw.isEmpty) return null;
    return {
      for (final e in raw.entries)
        NoticeKind.fromWire(e.key): [
          if (e.value is List)
            for (final v in e.value as List)
              if (v is num) v.toInt(),
        ],
    };
  }

  Future<void> setNoticeOffsets(NoticeKind kind, List<int> days) => _setJsonMap(
    _kNoticeOffsets,
    {..._jsonMap(_kNoticeOffsets), kind.wire: days},
  );

  int get noticeRetentionDays => _prefs.getInt(_kNoticeRetentionDays) ?? 180;
  Future<void> setNoticeRetentionDays(int days) => _prefs.setInt(_kNoticeRetentionDays, days);

  /// Timestamps of every auto-armed notice in the last seven days — the
  /// weekly cap (§D) counts these.
  List<DateTime> noticeAutoArmed(DateTime now) => [
    for (final s in _prefs.getStringList(_kNoticeAutoArmed) ?? const <String>[])
      if (DateTime.tryParse(s) case final d? when now.difference(d) < const Duration(days: 7)) d,
  ];

  Future<void> recordNoticeAutoArmed(DateTime now) => _prefs.setStringList(
    _kNoticeAutoArmed,
    [for (final d in noticeAutoArmed(now)) d.toIso8601String(), now.toIso8601String()],
  );

  /// Stage-2 cost guard: Gemini classification calls made today.
  int noticeAiCallsToday(DateTime now) {
    final day = _prefs.getString(_kNoticeAiDay);
    return day == _dayKey(now) ? (_prefs.getInt(_kNoticeAiCount) ?? 0) : 0;
  }

  Future<void> recordNoticeAiCall(DateTime now) async {
    final count = noticeAiCallsToday(now) + 1;
    await _prefs.setString(_kNoticeAiDay, _dayKey(now));
    await _prefs.setInt(_kNoticeAiCount, count);
  }

  bool get noticeBatteryHintShown => _prefs.getBool(_kNoticeBatteryHint) ?? false;
  Future<void> setNoticeBatteryHintShown() => _prefs.setBool(_kNoticeBatteryHint, true);

  bool get noticeInexactNoted => _prefs.getBool(_kNoticeInexactNoted) ?? false;
  Future<void> setNoticeInexactNoted() => _prefs.setBool(_kNoticeInexactNoted, true);

  DateTime? get noticeLastDrainAt => _millis(_kNoticeLastDrainAt);
  Future<void> setNoticeLastDrainAt(DateTime at) =>
      _prefs.setInt(_kNoticeLastDrainAt, at.millisecondsSinceEpoch);

  /// Everything notification capture keeps here. "Delete all" and the
  /// master switch going off call this.
  Future<void> clearNoticeScoped({bool keepSettings = false}) async {
    final keep = keepSettings
        ? {_kNoticePackages, _kNoticeRules, _kNoticeChildMap, _kNoticeOffsets, _kNoticeRetentionDays, _kNoticeDisclosureAt}
        : <String>{};
    for (final key in _prefs.getKeys().where((k) => k.startsWith('notices.') && !keep.contains(k))) {
      await _prefs.remove(key);
    }
  }

  DateTime? _millis(String key) {
    final ms = _prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Map<String, Object?> _jsonMap(String key) {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return const {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _setJsonMap(String key, Map<String, Object?> value) =>
      _prefs.setString(key, jsonEncode(value));

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
