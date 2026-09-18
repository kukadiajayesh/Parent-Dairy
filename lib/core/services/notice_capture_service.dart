import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../errors/app_failure.dart';
import '../util/sha1.dart';

/// One notification as the listener captured it, before extraction.
@immutable
class RawNotice {
  RawNotice({
    required this.packageName,
    required this.appLabel,
    required this.title,
    required this.body,
    required this.postedAt,
    this.key = '',
    this.category = '',
    this.truncated = false,
  }) : hash = hashFor(packageName: packageName, title: title, body: body, postedAt: postedAt);

  final String packageName;
  final String appLabel;
  final String title;
  final String body;
  final DateTime postedAt;
  final String key;
  final String category;
  final bool truncated;

  /// `sha1(packageName|title|body|yyyy-MM-dd)`, the same recipe as the
  /// Kotlin side. Always recomputed here — the native value is only a hint,
  /// the Dart one is what gets written.
  final String hash;

  static String hashFor({
    required String packageName,
    required String title,
    required String body,
    required DateTime postedAt,
  }) {
    final day =
        '${postedAt.year}-${postedAt.month.toString().padLeft(2, '0')}-${postedAt.day.toString().padLeft(2, '0')}';
    return sha1Hex('$packageName|$title|$body|$day');
  }

  factory RawNotice.fromMap(Map<Object?, Object?> m) => RawNotice(
    packageName: (m['packageName'] ?? '').toString(),
    appLabel: (m['appLabel'] ?? m['packageName'] ?? '').toString(),
    title: (m['title'] ?? '').toString(),
    body: (m['body'] ?? '').toString(),
    postedAt: DateTime.fromMillisecondsSinceEpoch((m['postedAt'] as num?)?.toInt() ?? 0),
    key: (m['key'] ?? '').toString(),
    category: (m['category'] ?? '').toString(),
    truncated: m['truncated'] == true,
  );
}

/// A launchable app on the phone, for the watched-apps picker.
@immutable
class InstalledApp {
  const InstalledApp({required this.packageName, required this.label, this.iconPng});

  final String packageName;
  final String label;

  /// 48dp PNG, or null when the icon could not be rasterised.
  final Uint8List? iconPng;

  /// Labels or packages that usually belong to a school app — the picker's
  /// "looks like your school app" hint (§E).
  bool get looksLikeSchoolApp => RegExp(
    r'campus|school|parent|edu|erp|teno|classdojo|toppr|byju|vidya|shiksha|scholar|student|academ|diary',
    caseSensitive: false,
  ).hasMatch('$label $packageName');

  factory InstalledApp.fromMap(Map<Object?, Object?> m) {
    final icon = m['iconPng'];
    Uint8List? bytes;
    if (icon is String && icon.isNotEmpty) {
      try {
        bytes = base64Decode(icon);
      } catch (_) {
        bytes = null;
      }
    } else if (icon is Uint8List) {
      bytes = icon;
    }
    return InstalledApp(
      packageName: (m['packageName'] ?? '').toString(),
      label: (m['label'] ?? m['packageName'] ?? '').toString(),
      iconPng: bytes,
    );
  }
}

/// The platform seam. The real one talks to `NotificationCapturePlugin.kt`;
/// tests and the design gallery use [FakeNoticeCapturePlatform].
abstract class NoticeCapturePlatform {
  Future<bool> isGranted();
  Future<bool> isListenerConnected();
  Future<DateTime?> lastCaptureAt();
  Future<void> openSettings();
  Future<List<InstalledApp>> installedApps();
  Future<void> setWatchedPackages(List<String> packages);
  Future<List<RawNotice>> drainBuffer();
  Future<int> bufferSize();
}

class MethodChannelNoticeCapture implements NoticeCapturePlatform {
  const MethodChannelNoticeCapture();

  static const channel = MethodChannel('com.parent.academic.diary/notifications');

  @override
  Future<bool> isGranted() async => await channel.invokeMethod<bool>('isGranted') ?? false;

  @override
  Future<bool> isListenerConnected() async =>
      await channel.invokeMethod<bool>('isListenerConnected') ?? false;

  @override
  Future<DateTime?> lastCaptureAt() async {
    final ms = await channel.invokeMethod<int>('lastCaptureAt') ?? 0;
    return ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> openSettings() => channel.invokeMethod<void>('openSettings');

  @override
  Future<List<InstalledApp>> installedApps() async {
    final list = await channel.invokeMethod<List<Object?>>('installedApps') ?? const [];
    return [for (final e in list) if (e is Map) InstalledApp.fromMap(e)];
  }

  @override
  Future<void> setWatchedPackages(List<String> packages) =>
      channel.invokeMethod<void>('setWatchedPackages', {'packages': packages});

  @override
  Future<List<RawNotice>> drainBuffer() async {
    final list = await channel.invokeMethod<List<Object?>>('drainBuffer') ?? const [];
    return [for (final e in list) if (e is Map) RawNotice.fromMap(e)];
  }

  @override
  Future<int> bufferSize() async => await channel.invokeMethod<int>('bufferSize') ?? 0;
}

/// An in-memory platform for tests and the states gallery. Mirrors the
/// native ring buffer's bound so the Dart tests can exercise overflow.
class FakeNoticeCapturePlatform implements NoticeCapturePlatform {
  FakeNoticeCapturePlatform({
    this.granted = true,
    this.connected = true,
    this.apps = const [],
  });

  bool granted;
  bool connected;
  final List<InstalledApp> apps;
  final List<RawNotice> buffer = [];
  List<String> watched = const [];
  DateTime? lastCapture;
  int openSettingsCalls = 0;

  /// Appends the way the Kotlin listener does: same key or hash replaces
  /// (keeping the longer body), oldest dropped past the capacity.
  void post(RawNotice notice) {
    final i = buffer.indexWhere(
      (b) => (notice.key.isNotEmpty && b.key == notice.key) || b.hash == notice.hash,
    );
    if (i >= 0) {
      if (notice.body.length >= buffer[i].body.length) buffer[i] = notice;
    } else {
      buffer.add(notice);
    }
    while (buffer.length > NoticeCaptureService.bufferCapacity) {
      buffer.removeAt(0);
    }
    lastCapture = notice.postedAt;
  }

  @override
  Future<bool> isGranted() async => granted;
  @override
  Future<bool> isListenerConnected() async => connected;
  @override
  Future<DateTime?> lastCaptureAt() async => lastCapture;
  @override
  Future<void> openSettings() async => openSettingsCalls++;
  @override
  Future<List<InstalledApp>> installedApps() async => apps;
  @override
  Future<void> setWatchedPackages(List<String> packages) async => watched = packages;
  @override
  Future<List<RawNotice>> drainBuffer() async {
    final out = List<RawNotice>.of(buffer);
    buffer.clear();
    return out;
  }

  @override
  Future<int> bufferSize() async => buffer.length;
}

/// The Dart face of notification capture (prompt 03 §B).
///
/// Android-only by construction: on any other platform [isSupported] is
/// false and nothing here touches a channel. Permission is re-checked on
/// every call to [refresh], because the OS or an OEM battery manager can
/// revoke it silently.
class NoticeCaptureService extends ChangeNotifier {
  NoticeCaptureService({NoticeCapturePlatform? platform, bool? supported})
    : _platform = platform ?? const MethodChannelNoticeCapture(),
      _supportedOverride = supported;

  /// Mirrors `NoticeBuffer.CAPACITY`.
  static const int bufferCapacity = 500;

  final NoticeCapturePlatform _platform;
  final bool? _supportedOverride;

  bool get isSupported =>
      _supportedOverride ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  bool _granted = false;
  bool _connected = false;
  bool _checked = false;
  DateTime? _lastCaptureAt;
  List<InstalledApp>? _apps;
  AppFailure? _lastError;

  /// Notification access granted in system settings.
  bool get isGranted => _granted;

  /// Granted *and* the service is alive. False with [isGranted] true means
  /// the OEM killed it (§F).
  bool get isListenerConnected => _connected;
  bool get hasChecked => _checked;
  DateTime? get lastCaptureAt => _lastCaptureAt;
  AppFailure? get lastError => _lastError;

  /// Re-reads the permission and the listener state. Cheap; called on
  /// start and every resume.
  Future<void> refresh() async {
    if (!isSupported) return;
    try {
      _granted = await _platform.isGranted();
      _connected = _granted && await _platform.isListenerConnected();
      _lastCaptureAt = await _platform.lastCaptureAt();
      _lastError = null;
    } on MissingPluginException {
      _granted = false;
      _connected = false;
    } catch (error) {
      _lastError = AppFailure.from(error);
    }
    _checked = true;
    notifyListeners();
  }

  Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await _platform.openSettings();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Cached for the session — listing apps and rasterising icons is slow.
  Future<List<InstalledApp>> installedApps({bool refresh = false}) async {
    if (!isSupported) return const [];
    if (_apps != null && !refresh) return _apps!;
    try {
      _apps = await _platform.installedApps();
      return _apps!;
    } on MissingPluginException {
      return const [];
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<void> setWatchedPackages(List<String> packages) async {
    if (!isSupported) return;
    try {
      await _platform.setWatchedPackages(packages);
    } on MissingPluginException {
      // Nothing to write to; a test host.
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<int> bufferSize() async {
    if (!isSupported) return 0;
    try {
      return await _platform.bufferSize();
    } catch (_) {
      return 0;
    }
  }

  /// Empties the native buffer and returns what was in it, de-duplicated
  /// within the batch (same hash → the longer body wins) and bounded to the
  /// newest [bufferCapacity] entries.
  ///
  /// Idempotent from the caller's point of view: the same hash can come
  /// back from two drains (a re-post after the buffer was cleared), so the
  /// caller checks each hash against stored notices before any write.
  Future<List<RawNotice>> drain() async {
    if (!isSupported) return const [];
    final List<RawNotice> raw;
    try {
      raw = await _platform.drainBuffer();
    } on MissingPluginException {
      return const [];
    } catch (error) {
      throw AppFailure.from(error);
    }
    return dedupe(raw);
  }

  /// The pure part of [drain], for tests.
  static List<RawNotice> dedupe(List<RawNotice> raw) {
    final byHash = <String, RawNotice>{};
    for (final n in raw) {
      if (n.packageName.isEmpty) continue;
      if (n.title.trim().isEmpty && n.body.trim().isEmpty) continue;
      final existing = byHash[n.hash];
      if (existing == null || n.body.length >= existing.body.length) byHash[n.hash] = n;
    }
    final out = byHash.values.toList()..sort((a, b) => a.postedAt.compareTo(b.postedAt));
    if (out.length > bufferCapacity) out.removeRange(0, out.length - bufferCapacity);
    return out;
  }
}
