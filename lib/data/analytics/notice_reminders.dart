import '../models.dart';

/// What the auto-arm policy (prompt 03 §D) decided for a fresh capture.
enum NoticeArmDecision {
  /// Schedule now, tell the parent, keep Undo for 24 hours.
  auto,

  /// Show in the inbox; one tap to confirm.
  inbox,

  /// Store only, visible under "All notices".
  store,
}

/// The reminder policy, pure Dart so every rule in §D is a unit test.
abstract final class NoticeReminders {
  /// Days before the event, per kind. `0` is "morning of".
  static const Map<NoticeKind, List<int>> defaultOffsets = {
    NoticeKind.exam: [7, 3, 1, 0],
    NoticeKind.assignment: [1, 0],
    NoticeKind.activity: [1, 0],
    NoticeKind.meeting: [1, 0],
    NoticeKind.holiday: [0],
    NoticeKind.fee: [3, 0],
    NoticeKind.announcement: [0],
    NoticeKind.unknown: [0],
  };

  /// The choices the settings screen offers per kind.
  static const List<int> offsetChoices = [14, 7, 3, 2, 1, 0];

  static const int maxPerNotice = 4;
  static const int weeklyAutoCap = 20;
  static const int morningHour = 7;

  static String offsetLabel(int days) => switch (days) {
    0 => 'Morning of',
    1 => '1 day before',
    _ => '$days days before',
  };

  /// The moments to fire for [extraction], newest last, already trimmed of
  /// anything in the past and capped at [maxPerNotice].
  ///
  /// Everything fires at 07:00 local — before the school run. The one
  /// exception: when the notice carries a time, the morning-of reminder
  /// fires an hour before it instead, since a 07:00 nudge for a 2 PM PTM is
  /// less useful than one at 1 PM and a nudge *at* 2 PM is too late.
  static List<DateTime> timesFor(
    NoticeExtraction extraction, {
    required DateTime now,
    Map<NoticeKind, List<int>>? offsets,
  }) {
    final date = extraction.date;
    if (date == null) return const [];
    final days = (offsets ?? defaultOffsets)[extraction.kind] ??
        defaultOffsets[extraction.kind] ??
        const [0];
    final out = <DateTime>[];
    for (final offset in days.toSet().toList()..sort((a, b) => b.compareTo(a))) {
      final day = DateTime(date.year, date.month, date.day).subtract(Duration(days: offset));
      var at = DateTime(day.year, day.month, day.day, morningHour);
      if (offset == 0 && !extraction.allDay) {
        final before = date.subtract(const Duration(hours: 1));
        at = DateTime(before.year, before.month, before.day, before.hour, before.minute);
      }
      if (at.isAfter(now)) out.add(at);
    }
    if (out.length > maxPerNotice) out.removeRange(0, out.length - maxPerNotice);
    return out;
  }

  /// §D: what to do with a freshly captured notice.
  static NoticeArmDecision decide(
    NoticeExtraction extraction, {
    required DateTime now,
    required int autoArmedThisWeek,
    int weeklyCap = weeklyAutoCap,
  }) {
    if (extraction.confidence < 0.5) return NoticeArmDecision.store;
    final date = extraction.date;
    if (date == null) return NoticeArmDecision.inbox;
    final today = DateTime(now.year, now.month, now.day);
    if (date.isBefore(today)) return NoticeArmDecision.inbox;
    if (extraction.isAmbiguous) return NoticeArmDecision.inbox;
    if (extraction.confidence < 0.8) return NoticeArmDecision.inbox;
    if (!extraction.kind.autoArms) return NoticeArmDecision.inbox;
    if (autoArmedThisWeek >= weeklyCap) return NoticeArmDecision.inbox;
    return NoticeArmDecision.auto;
  }

  /// Stage-2 validation (§C): a model-supplied date is discarded — not
  /// trusted — when it is in the past or more than a year out.
  static bool acceptableDate(DateTime? date, {required DateTime postedAt}) {
    if (date == null) return false;
    final floor = DateTime(postedAt.year, postedAt.month, postedAt.day).subtract(const Duration(days: 1));
    final ceiling = postedAt.add(const Duration(days: 366));
    return !date.isBefore(floor) && !date.isAfter(ceiling);
  }

  /// Notification ids for a notice: the document id hashed into 28 bits,
  /// with three low bits for the slot. Slot 7 is the "reminder added"
  /// notification the auto-arm policy posts.
  static int notificationId(String noticeId, int slot) =>
      ((noticeId.hashCode & 0x0FFFFFFF) << 3) | (slot & 0x7);

  static const int armedSlot = 7;
}
