import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/analytics/notice_reminders.dart';
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

/// What the notice pipeline needs from the notification layer — a seam so
/// the auto-arm policy can be tested without a platform plugin.
abstract class NoticeReminderScheduler {
  /// Schedules one local notification per moment in [times] and returns the
  /// ids it used. Moments already past are skipped.
  Future<List<int>> scheduleNoticeReminders(CapturedNotice notice, List<DateTime> times);

  Future<void> cancelNoticeReminders(List<int> ids);

  /// "Reminder added from {app} — tap to review" (§D).
  Future<void> showNoticeArmed(CapturedNotice notice);
}

/// Worksheet and homework reminders (§24), and school-notice reminders
/// (prompt 03 §D) on their own channel.
///
/// Due-date reminders are **local** notifications: the due date is already on
/// the device, so scheduling them locally means they fire with no server, no
/// backend job and no network. FCM is initialised alongside so that
/// server-driven pushes can be added later without touching call sites.
class NotificationService implements NoticeReminderScheduler {
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

  /// A second channel so a school alert is distinguishable from a worksheet
  /// nag in the phone's notification settings.
  static const noticeChannelId = 'notice_reminders';
  static const _noticeChannelName = 'School notices';
  static const _noticeChannelDescription =
      'Reminders for exams, assignments and events read from your school app';

  /// Payload prefix for a tap on anything notice-related.
  static const noticePayloadPrefix = 'notice:';

  bool _ready = false;

  /// The payload of the notification the parent last tapped — a record id
  /// for a worksheet reminder, `notice:<id>` for a school notice. The app
  /// shell listens and navigates; consumed by setting it back to null.
  final ValueNotifier<String?> tapped = ValueNotifier<String?>(null);

  /// Whether Android will honour exact alarms. Null until checked; false
  /// means notice reminders may land up to an hour late (§F).
  bool? _exactAllowed;
  bool? get exactAlarmsAllowed => _exactAllowed;

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
        onDidReceiveNotificationResponse: (response) =>
            tapped.value = response.payload,
      );

      // A tap that launched the app from cold arrives here rather than
      // through the callback above.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        tapped.value = launch!.notificationResponse?.payload;
      }

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.defaultImportance,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          noticeChannelId,
          _noticeChannelName,
          description: _noticeChannelDescription,
          importance: Importance.high,
        ),
      );
      try {
        _exactAllowed = await android?.canScheduleExactNotifications();
      } catch (_) {
        _exactAllowed = null;
      }

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

  // ── School notices (prompt 03 §D) ───────────────────────────────────────

  /// Asks Android 13+ for the exact-alarm permission. Returns whether it
  /// ended up granted; a refusal is normal and the reminders still fire,
  /// just inexactly.
  Future<bool> requestExactAlarms() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return false;
      await android.requestExactAlarmsPermission();
      _exactAllowed = await android.canScheduleExactNotifications();
      return _exactAllowed ?? false;
    } catch (_) {
      return _exactAllowed ?? false;
    }
  }

  @override
  Future<List<int>> scheduleNoticeReminders(
    CapturedNotice notice,
    List<DateTime> times,
  ) async {
    if (!_ready) return const [];
    if (!PrefsService.instance.remindersEnabled) return const [];
    final extraction = notice.extraction;
    if (extraction == null) return const [];

    final ids = <int>[];
    final now = tz.TZDateTime.now(tz.local);
    for (var i = 0; i < times.length && i < NoticeReminders.maxPerNotice; i++) {
      final t = times[i];
      final when = tz.TZDateTime(tz.local, t.year, t.month, t.day, t.hour, t.minute);
      if (!when.isAfter(now)) continue;
      final id = NoticeReminders.notificationId(notice.id, i);
      final date = extraction.date!;
      final dayDiff = DateTime(date.year, date.month, date.day)
          .difference(DateTime(t.year, t.month, t.day))
          .inDays;
      final title = switch (dayDiff) {
        <= 0 => '${extraction.kind.label} today · ${notice.displayTitle}',
        1 => '${extraction.kind.label} tomorrow · ${notice.displayTitle}',
        _ => '${extraction.kind.label} in $dayDiff days · ${notice.displayTitle}',
      };
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: 'From ${notice.appLabel}. Tap to open the notice.',
          scheduledDate: when,
          // Exact when the parent granted it (07:00 sharp), inexact
          // otherwise — the OS may then deliver up to an hour late.
          androidScheduleMode: _exactAllowed == true
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: '$noticePayloadPrefix${notice.id}',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              noticeChannelId,
              _noticeChannelName,
              channelDescription: _noticeChannelDescription,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
        ids.add(id);
      } catch (_) {
        // One slot failing (exact alarm refused mid-way, say) must not lose
        // the others.
      }
    }
    return ids;
  }

  @override
  Future<void> cancelNoticeReminders(List<int> ids) async {
    if (!_ready) return;
    for (final id in ids) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }
  }

  @override
  Future<void> showNoticeArmed(CapturedNotice notice) async {
    if (!_ready) return;
    if (!PrefsService.instance.remindersEnabled) return;
    try {
      await _plugin.show(
        id: NoticeReminders.notificationId(notice.id, NoticeReminders.armedSlot),
        title: 'Reminder added from ${notice.appLabel}',
        body: '${notice.displayTitle} — tap to review',
        payload: '$noticePayloadPrefix${notice.id}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            noticeChannelId,
            _noticeChannelName,
            channelDescription: _noticeChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  /// Android notification ids are 32-bit; hash the document id into range.
  static int _idFor(String recordId) => recordId.hashCode & 0x7fffffff;
}
