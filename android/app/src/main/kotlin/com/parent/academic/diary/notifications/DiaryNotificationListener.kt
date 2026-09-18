package com.parent.academic.diary.notifications

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/**
 * Captures notifications from the apps the parent opted into (prompt 03 §A).
 *
 * This service is started by the system and lives in the app process with
 * **no Flutter engine**. Nothing here may touch Firestore, Firebase Auth or
 * a method channel: every capture is appended to [NoticeBuffer] and the Dart
 * side drains it on the next app start or resume.
 */
class DiaryNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        NoticeBuffer.setListenerConnected(this, true)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        // Lets Dart tell "permission granted but the OEM killed the service"
        // apart from "not granted".
        NoticeBuffer.setListenerConnected(this, false)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        try {
            capture(n)
        } catch (_: Exception) {
            // A malformed notification from a third-party app must never
            // crash a system-bound service; the notice is simply not captured.
        }
    }

    private fun capture(sbn: StatusBarNotification) {
        // 1. The cheapest check first: a package the parent did not tick.
        if (sbn.packageName !in NoticeBuffer.watchedPackages(this)) return

        val notification = sbn.notification ?: return
        val flags = notification.flags

        // 2. Ongoing (music, downloads), group summaries (duplicate of the
        //    children), local-only, media sessions and progress bars carry no
        //    school notice.
        if (flags and Notification.FLAG_ONGOING_EVENT != 0) return
        if (flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (flags and Notification.FLAG_LOCAL_ONLY != 0) return
        if (notification.category == Notification.CATEGORY_TRANSPORT) return
        if (notification.category == Notification.CATEGORY_PROGRESS) return
        val extras = notification.extras ?: return
        if (extras.containsKey(Notification.EXTRA_MEDIA_SESSION)) return
        if (extras.getInt(Notification.EXTRA_PROGRESS_MAX, 0) > 0) return

        // 3. Text. Big text wins over the collapsed text; text lines (inbox
        //    style) are joined; sub and info text are appended when present.
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.mapNotNull { it?.toString()?.trim() }
            ?.filter { it.isNotEmpty() }
            ?.joinToString("\n")
            .orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim().orEmpty()
        val infoText = extras.getCharSequence(Notification.EXTRA_INFO_TEXT)?.toString()?.trim().orEmpty()

        val main = when {
            bigText.isNotEmpty() -> bigText
            lines.isNotEmpty() -> lines
            else -> text
        }
        val body = listOf(main, subText, infoText)
            .filter { it.isNotEmpty() }
            .distinct()
            .joinToString("\n")

        if (title.isEmpty() && body.isEmpty()) return

        val truncated = body.length > NoticeBuffer.MAX_BODY
        val storedBody = if (truncated) body.substring(0, NoticeBuffer.MAX_BODY) else body

        // 4./5. Hash on the stored text so an update that only lengthens a
        //       body past the cap still dedupes.
        val hash = NoticeBuffer.hashFor(sbn.packageName, title, storedBody, sbn.postTime)

        val entry = JSONObject()
            .put("packageName", sbn.packageName)
            .put("appLabel", appLabel(sbn.packageName))
            .put("title", title)
            .put("body", storedBody)
            .put("postedAt", sbn.postTime)
            .put("key", sbn.key ?: "")
            .put("category", notification.category ?: "")
            .put("hash", hash)
            .put("truncated", truncated)
        NoticeBuffer.append(this, entry)
    }

    private fun appLabel(packageName: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        packageName
    }
}
