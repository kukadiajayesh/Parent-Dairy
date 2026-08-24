import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models.dart';
import 'prefs_service.dart';

/// Handles a push that arrives while the app is terminated. Must be a
/// top-level function — the Android engine looks it up by name.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nothing to do yet: the payload is informational and the timeline reloads
  // from Firestore on next open. The handler exists so FCM has a valid entry
  // point registered when server-sent reminders are switched on.
}

/// Worksheet and homework reminders (§24).
///
/// Due-date reminders are **local** notifications: the due date is already on
/// the device, so scheduling them locally means they fire with no server, no
/// backend job and no network. FCM is initialised alongside so that
/// server-driven pushes can be added later without touching call sites.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// One instance app-wide: scheduling happens wherever a record is saved,
  /// and every caller must share the same initialised plugin.
  static final NotificationService instance = NotificationService();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'worksheet_reminders';
  static const _channelName = 'Worksheet reminders';
  static const _channelDescription =
      'Reminders for worksheets that are due or overdue';

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Falls back to UTC. A reminder an hour off is better than none, and
      // better than a crash at startup.
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDescription,
              importance: Importance.defaultImportance,
            ),
          );

      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
      _ready = true;
    } catch (error, stack) {
      if (kDebugMode) debugPrint('Notification init failed: $error\n$stack');
    }
  }

  /// Asked for at the moment a reminder is first scheduled rather than at
  /// launch, so the prompt has visible context.
  Future<bool> requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();

      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Schedules the reminder for one worksheet, replacing any previous one.
  ///
  /// Fires at 07:00 on the due date — before the school run, when a parent can
  /// still act on it. Past dates are skipped rather than fired immediately.
  Future<void> scheduleWorksheetReminder(DiaryRecord record) async {
    if (!_ready) return;
    if (!PrefsService.instance.remindersEnabled) return;
    if (!record.isWorksheet) return;
    if (record.status == WorksheetStatus.completed) return;

    final due = record.dueDate;
    if (due == null) return;

    final when = tz.TZDateTime(tz.local, due.year, due.month, due.day, 7);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;

    try {
      await _plugin.zonedSchedule(
        id: _idFor(record.id),
        title: '${record.subject} worksheet due today',
        body: record.title,
        scheduledDate: when,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: record.id,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {
      // Exact-alarm permission can be refused on Android 13+; the timeline's
      // "Pending" section still surfaces the worksheet.
    }
  }

  Future<void> cancelWorksheetReminder(String recordId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _idFor(recordId));
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Re-arms every pending worksheet — after a reinstall, a restore on a new
  /// phone, or the parent switching reminders back on.
  Future<void> resyncAll(Iterable<DiaryRecord> records) async {
    if (!_ready) return;
    await cancelAll();
    if (!PrefsService.instance.remindersEnabled) return;
    for (final record in records) {
      await scheduleWorksheetReminder(record);
    }
  }

  /// Android notification ids are 32-bit; hash the document id into range.
  static int _idFor(String recordId) => recordId.hashCode & 0x7fffffff;
}
