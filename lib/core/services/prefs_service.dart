import 'package:shared_preferences/shared_preferences.dart';

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

  /// Clears per-account selections on sign-out. Theme and onboarding are device
  /// preferences and deliberately survive.
  Future<void> clearAccountScoped() async {
    await _prefs.remove(_kChildId);
    await _prefs.remove(_kYear);
    await _prefs.remove(_kLastSubject);
  }
}
