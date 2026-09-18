# 03 — Notification capture and automatic reminders

> Assumes `00-shared-context.md`. Prompt `02` is optional: without it the
> extractor runs on rules alone and still works.

## Goal

The school app (Campus Care 10x and the like) posts a notification saying
"Unit Test 2 — Science — 24 Nov". The parent reads it on the lock screen and
forgets it. This feature captures the notification from apps the parent has
explicitly opted into, stores its text, pulls out what kind of event it is and
when, and arms a reminder — with the parent in the loop wherever the app is not
confident.

## Platform reality — read before designing

- This is **Android-only**. It needs `NotificationListenerService`, which has no
  iOS equivalent. On iOS the whole feature is hidden and
  `NotificationCapture.isSupported` returns false. Do not fake it.
- **The listener runs when Flutter is not.** The service is started by the
  system and lives in the app process without an active `FlutterEngine`. Any
  design that assumes a Dart callback per notification will drop captures.
  Buffer natively, drain from Dart.
- The permission is granted in a **system settings screen**, not by a runtime
  dialog, and can be revoked silently by the OS or an OEM battery manager.
  Re-check on every resume.
- Shipping this needs a **Play Console declaration** and a privacy-policy entry
  covering notification access, plus an in-app disclosure before the permission
  prompt. Google rejects apps that request notification access without a core
  feature that needs it — the disclosure copy in §H is part of the deliverable,
  not decoration.

## A. Native side

`android/app/src/main/kotlin/com/parent/academic/diary/notifications/`

**`DiaryNotificationListener.kt`** extends `NotificationListenerService`:

- Manifest entry:

```xml
<service android:name=".notifications.DiaryNotificationListener"
    android:label="Academic Diary notice capture"
    android:exported="false"
    android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE">
    <intent-filter>
        <action android:name="android.service.notification.NotificationListenerService"/>
    </intent-filter>
</service>
```

- `onNotificationPosted(sbn)`:
  1. Return immediately unless `sbn.packageName` is in the opted-in set (read
     from a dedicated `SharedPreferences` file the Dart side writes, so the
     check costs no IPC).
  2. Skip `FLAG_ONGOING_EVENT`, `FLAG_GROUP_SUMMARY`, `FLAG_LOCAL_ONLY`,
     media-session and progress notifications, and anything with empty title and
     text.
  3. Read `extras`: `EXTRA_TITLE`, `EXTRA_TEXT`, `EXTRA_BIG_TEXT`,
     `EXTRA_SUB_TEXT`, `EXTRA_TEXT_LINES` (joined), `EXTRA_INFO_TEXT`, plus
     `sbn.postTime`, `sbn.key`, `category`, and the app label resolved from
     `PackageManager`.
  4. Deduplicate on `sha1(packageName|title|body|yyyy-MM-dd)`. Android re-posts
     a notification on every update; the same message must not become three
     notices. When an update arrives with the *same* `sbn.key` but longer text,
     replace the buffered entry rather than adding one.
  5. Append to a bounded JSON ring buffer (500 entries) in
     `SharedPreferences("diary_notice_buffer")`. Never write to Firestore from
     here — no auth context, no Flutter, and battery cost.
- `onListenerConnected` / `onListenerDisconnected` record availability so Dart
  can tell "not granted" from "granted but the OEM killed it".

**`NotificationCapturePlugin.kt`** — a `MethodChannel`
`com.parent.academic.diary/notifications` registered from `MainActivity`:

| Method | Returns |
| --- | --- |
| `isSupported` | `true` on Android |
| `isGranted` | `NotificationManagerCompat.getEnabledListenerPackages` contains us |
| `openSettings` | launches `ACTION_NOTIFICATION_LISTENER_SETTINGS` |
| `installedApps` | `[{packageName, label, iconPng(base64, 48dp)}]`, launchable apps only, sorted by label |
| `setWatchedPackages(List<String>)` | writes the opt-in set the service reads |
| `drainBuffer` | returns and clears the buffered captures |
| `bufferSize` | count, for the settings badge |

Cap `iconPng` at 48dp and cache the app list in Dart for the session —
`getInstalledApplications` plus icon rasterising is slow on a loaded phone.

Also add to the manifest: `<uses-permission
android:name="android.permission.SCHEDULE_EXACT_ALARM"/>` (and the
`USE_EXACT_ALARM` alternative if reminders must not slip), and a
`BOOT_COMPLETED` receiver that re-arms scheduled reminders — the app already
declares `RECEIVE_BOOT_COMPLETED` but nothing re-schedules after a reboot today.

## B. Dart side

`lib/core/services/notice_capture_service.dart` — the channel wrapper, plus a
`drain()` called on app start and on `AppLifecycleState.resumed`. Draining is
idempotent: the dedupe hash is checked again against stored notices before any
write.

### Model (`models.dart`)

```dart
enum NoticeKind { exam, assignment, activity, holiday, fee, meeting, announcement, unknown }
enum NoticeStatus { needsReview, confirmed, ignored, converted }

class CapturedNotice {
  final String id, packageName, appLabel, title, body;
  final DateTime postedAt;
  final String sourceHash;
  final String? childId;            // assigned by the parent or inferred
  final NoticeStatus status;
  final NoticeExtraction? extraction;
  final String? linkedRecordId;     // when converted to a DiaryRecord
  final List<int> reminderIds;      // what was scheduled from it
  final bool isDeleted;
}

class NoticeExtraction {
  final NoticeKind kind;
  final String title;               // cleaned, e.g. 'Science Unit Test 2'
  final String? subject;            // matched against the child's subjects
  final DateTime? eventAt;
  final bool allDay;
  final DateTime? dueAt;
  final double confidence;          // 0–1
  final String source;              // 'rules' | 'gemini'
  final List<String> matchedPhrases;// what drove the decision, for the UI
}
```

Firestore: `users/{uid}/notices/{noticeId}` — parent-level, because a
notification arrives before anyone knows which child it is about. Rules block in
the same shape as the others; `body` capped at 4000 chars; soft delete; index on
`isDeleted ASC, postedAt DESC`. **Retention:** purge notices older than 180 days
on app start — school notices have no long-term value and this is other people's
text sitting in a database.

## C. Extraction — rules first, model second

`lib/data/analytics/notice_extractor.dart`, pure Dart, no network.

### Stage 1 — deterministic

Anchor every relative date on `postedAt`, in the device timezone.

- **Dates**: `24/11/2026`, `24-11-26`, `24 Nov`, `24th November`,
  `November 24`, `Mon 24 Nov`, and bare `24.11` — day-first, since that is the
  Indian convention; when the year is missing, choose the next occurrence within
  the next 11 months.
- **Relative**: `today`, `tomorrow`, `day after tomorrow`, `next Monday`,
  `this Friday`, `in 3 days`.
- **Times**: `9 am`, `09:00`, `9.30am`, `2 PM onwards`; default all-day when
  absent.
- **Ranges**: `24 Nov to 2 Dec`, `24–26 November` → `eventAt` + `endAt`.
- **Kind keywords** (case-insensitive, word-boundary):
  - exam: exam, test, unit test, UT, periodic, assessment, viva, practical,
    term, half yearly, pre-board, board
  - assignment: homework, HW, assignment, project, submission, submit, due,
    worksheet
  - activity: sports day, annual day, competition, elocution, drawing, quiz,
    field trip, excursion, picnic, rehearsal, fancy dress
  - holiday: holiday, no school, closed, vacation, leave
  - fee: fee, fees, payment, installment, due amount
  - meeting: PTM, parent teacher, orientation, open house
- **Subject** matched against the active child's `Subject` names and common
  abbreviations (Maths/Math/Mathematics, Sci/Science, EVS, SST, Eng, Hin, Guj,
  Comp).
- Confidence: 0.9 when a kind keyword and an unambiguous absolute date both
  match; 0.7 with a relative date; 0.5 when the kind is clear but no date;
  0.3 otherwise.

### Stage 2 — Gemini (only if `kAiEnabled` and a healthy key exists)

Run **only** when stage 1 lands below 0.7, and only on notices from opted-in
apps. Use the cheap classification model from prompt `02` with a strict schema
(the `NoticeExtraction` fields plus `reasoning`). Cost guard: at most 50 such
calls per day, batched up to 10 notices per request. The result must clear the
same validation as stage 1 — a date in the past or more than a year out is
discarded, not trusted. Mark `source: 'gemini'`.

**Falling back is normal, not an error.** With AI off, low-confidence notices
land in the inbox for a one-tap fix.

## D. Reminders

Extend `NotificationService` with a second channel, `notice_reminders`
("School notices"), so a school alert is distinguishable from a worksheet
reminder, and `scheduleNoticeReminders(CapturedNotice)`.

Default offsets by kind, all at **07:00 local** unless the notice carries a time:

| Kind | Reminders |
| --- | --- |
| exam | 7 days before, 3 days before, 1 day before, morning of |
| assignment | 1 day before due, morning of due |
| activity / meeting | 1 day before, morning of |
| holiday | morning of |
| fee | 3 days before, morning of |

Editable per kind in settings, and per notice before confirming.

**Auto-arm policy** — the part the original idea left open:

- `confidence >= 0.8` **and** a resolved date **and** the kind is exam,
  assignment, activity or meeting → schedule immediately, post a local
  notification saying "Reminder added from {app} — tap to review", and keep an
  **Undo** on the notice for 24h.
- `0.5 <= confidence < 0.8`, or a date in the past, or two candidate dates →
  **Inbox**, no alarm, one tap to confirm.
- `< 0.5` → stored only, visible under "All notices".
- Never schedule more than 4 reminders per notice or 20 auto reminders per week;
  past the cap, everything goes to the inbox.
- Cancel every reminder for a notice when it is ignored, deleted, or its event
  date passes.

Also offer **Convert to record**: one tap turns an exam notice into an exam
`DiaryRecord` (prompt `01`) or an assignment notice into a worksheet with the
due date filled and the notice text as notes and `origin: notification`.

## E. Screens

1. **More → Notices** (`Routes.notices`) — tabs: **Inbox** (needs review, badge
   count), **Upcoming** (confirmed with a future date), **All**. Each row: app
   icon, title, detected kind chip, date, confidence dot. Swipe to ignore.
2. **Notice detail** — full text, the extraction with `matchedPhrases`
   highlighted, editable kind/date/subject/child, reminder list with per-item
   toggles, **Confirm**, **Convert to record**, **Ignore**.
3. **Settings → Notification capture** (`Routes.noticeSettings`) —
   master switch, permission state with a **Grant access** button that opens the
   system screen and an explainer of what will be read, the **watched apps**
   picker (searchable list of installed apps; apps that have actually posted a
   captured notification float to the top; a hint row suggesting the school app
   by name if its package is installed), per-app rule (capture all / only when
   it matches keywords / off), default reminder offsets, retention, and
   **Delete all captured notices**.
4. **Home** — an "Upcoming from school" strip when confirmed notices exist in
   the next 14 days.

Empty states matter here: "No notices yet — Academic Diary only reads
notifications from the apps you pick, and none of them have posted anything
since you turned this on."

## F. Edge cases

- Permission granted but the service is dead (OEM battery manager): if
  `isGranted` is true and nothing has been captured in 14 days from an app that
  is clearly active, show a one-time hint about disabling battery optimisation.
- The same notice arriving on two phones → dedupe hash is device-independent, so
  the Firestore write is `set` on a doc id derived from the hash.
- Notices in Gujarati or Hindi → stage 1 handles Latin-script dates; anything
  else falls through to stage 2 or the inbox. Do not machine-translate silently.
- A notice with a date but no child context in a multi-child family → ask, once,
  on confirm; remember the app→child mapping as a default.
- Very long bodies (fee circulars) → store the first 4000 chars, keep a
  `truncated` flag.
- `SCHEDULE_EXACT_ALARM` denied on Android 14+ → fall back to
  `AndroidScheduleMode.inexactAllowWhileIdle` (as the existing code already
  does) and say once in settings that reminders may arrive up to an hour late.

## G. Tests

- `notice_extractor_test.dart` — the core of this prompt. Check in a fixture
  corpus of at least **30** realistic school notification strings covering every
  kind, every date format above, ranges, relative dates, missing years, two
  dates in one message, no date, and a couple in Hindi/Gujarati script. Assert
  kind, date and confidence for each. This corpus is the spec; add to it
  whenever a real notification is misread.
- `notice_reminder_test.dart` — offsets per kind, the auto-arm thresholds, the
  weekly cap, cancellation on ignore, no reminder for a past date.
- `notice_capture_service_test.dart` — drain is idempotent, dedupe across
  drains, buffer overflow drops oldest.
- Widget — inbox empty state, a low-confidence notice cannot arm a reminder
  without a tap, the settings screen hides itself entirely on iOS.

## H. Disclosure copy (ship this, adjusted)

Shown **before** the permission screen opens, and repeated in the privacy policy:

> **Academic Diary can read notifications from apps you choose.**
> Pick your school's app and we'll read the notifications it posts — the title
> and the message text — so exam dates, assignment deadlines and school events
> can be saved and reminded about automatically.
>
> - We only read notifications from the apps you tick. Nothing else is read.
> - The text is stored in your own Academic Diary account and is deleted after
>   180 days.
> - Nothing is sent to anyone else. {If AI is on: Unclear dates may be sent to
>   Google's Gemini API under your own API key so they can be read — you can
>   turn that off in AI settings.}
> - You can turn this off, or delete everything captured, at any time in
>   Settings → Notification capture.

## I. Deliverable

A summary naming: the Kotlin files added and the manifest changes, what is
captured and what is skipped, the extractor's confidence thresholds as
implemented, the auto-arm policy, the retention job, the Play Console
declaration still to be filled in, and the fixture corpus size.
