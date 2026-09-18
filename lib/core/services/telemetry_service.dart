import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';

/// Crash reporting and product analytics (§40).
///
/// Analytics carries **counts and types only** — never a title, note, subject,
/// child name, school or file name. §40 is explicit that academic content stays
/// out of events, and the safest way to honour that is to give the call sites
/// no parameter to put it in.
abstract final class Telemetry {
  static FirebaseAnalytics? _analytics;
  static FirebaseCrashlytics? _crashlytics;

  /// Off in debug so local runs don't pollute production dashboards.
  static bool get _enabled => !kDebugMode;

  static Future<void> init() async {
    _analytics = FirebaseAnalytics.instance;
    _crashlytics = FirebaseCrashlytics.instance;
    await _crashlytics?.setCrashlyticsCollectionEnabled(_enabled);
    await _analytics?.setAnalyticsCollectionEnabled(_enabled);

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _crashlytics?.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      recordError(error, stack);
      return true;
    };
  }

  /// Ties a crash to an account without shipping an email address.
  static Future<void> setUser(String? uid) async {
    await _crashlytics?.setUserIdentifier(uid ?? '');
    if (uid == null) {
      await _analytics?.setUserId();
    } else {
      await _analytics?.setUserId(id: uid);
    }
  }

  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) async {
    if (error is AppFailure) {
      // A parent going offline or backing out of a picker is normal operation,
      // not a defect — reporting it would bury the real crashes.
      if (error.kind == FailureKind.offline || error.isCancellation) return;
      await _crashlytics?.recordError(
        error.cause ?? error,
        stack,
        reason: context ?? error.kind.name,
        fatal: fatal,
      );
      return;
    }
    await _crashlytics?.recordError(error, stack, reason: context, fatal: fatal);
  }

  static Future<void> log(String message) async =>
      _crashlytics?.log(message);

  // ── events (§40) ────────────────────────────────────────────────────────
  static Future<void> _event(String name, [Map<String, Object>? params]) async {
    if (!_enabled) return;
    await _analytics?.logEvent(name: name, parameters: params);
  }

  static Future<void> recordCreated({
    required String type,
    required int attachmentCount,
    required bool fromShare,
  }) => _event('record_created', {
    'record_type': type,
    'attachment_count': attachmentCount,
    'from_share': fromShare ? 1 : 0,
  });

  static Future<void> recordDeleted(String type) =>
      _event('record_deleted', {'record_type': type});

  static Future<void> worksheetCompleted() => _event('worksheet_completed');

  /// Counts only: how many subject rows and how the card got here. Never the
  /// marks, the subjects or the exam name.
  static Future<void> resultCreated({
    required int subjectCount,
    required String source,
  }) => _event('result_created', {
    'subject_count': subjectCount,
    'source': source,
  });

  static Future<void> resultDeleted() => _event('result_deleted');

  static Future<void> imageSharedToApp(int count) =>
      _event('image_shared_to_app', {'image_count': count});

  static Future<void> childCreated(int totalChildren) =>
      _event('child_created', {'child_count': totalChildren});

  static Future<void> subjectCreated() => _event('subject_created');

  static Future<void> yearCreated() => _event('year_created');

  static Future<void> searchPerformed({required bool allYears}) =>
      _event('search_performed', {'all_years': allYears ? 1 : 0});

  static Future<void> uploadFailed(String reason) =>
      _event('upload_failed', {'reason': reason});

  // ── AI (prompt 02) — feature and model names only, never key, prompt or
  // reply content, never token *contents*.
  static Future<void> aiRequested(String feature, String model) =>
      _event('ai_requested', {'feature': feature, 'model': model});

  static Future<void> aiSucceeded(String feature, int tokens) =>
      _event('ai_succeeded', {'feature': feature, 'tokens': tokens});

  static Future<void> aiFailed(String feature, String kind) =>
      _event('ai_failed', {'feature': feature, 'kind': kind});

  static Future<void> signIn() => _event('login', {'method': 'google'});

  static Future<void> signOut() => _event('sign_out');
}
