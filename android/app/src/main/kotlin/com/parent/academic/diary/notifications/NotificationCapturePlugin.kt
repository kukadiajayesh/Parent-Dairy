package com.parent.academic.diary.notifications

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Base64
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * `com.parent.academic.diary/notifications` — the Dart side's only way to
 * reach [DiaryNotificationListener]'s buffer and the system permission.
 */
class NotificationCapturePlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.parent.academic.diary/notifications"

        /** 48dp icons: enough for a list row, small enough to ship base64 over the channel. */
        private const val ICON_DP = 48

        fun register(messenger: BinaryMessenger, context: Context): MethodChannel {
            val channel = MethodChannel(messenger, CHANNEL)
            channel.setMethodCallHandler(NotificationCapturePlugin(context.applicationContext))
            return channel
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(true)
                "isGranted" -> result.success(isGranted())
                "isListenerConnected" -> result.success(NoticeBuffer.isListenerConnected(context))
                "lastCaptureAt" -> result.success(NoticeBuffer.lastCaptureAt(context))
                "openSettings" -> {
                    openSettings()
                    result.success(null)
                }
                "installedApps" -> installedApps(result)
                "setWatchedPackages" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    NoticeBuffer.setWatchedPackages(context, packages)
                    result.success(null)
                }
                "drainBuffer" -> result.success(NoticeBuffer.drain(context))
                "bufferSize" -> result.success(NoticeBuffer.size(context))
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("notice_capture", e.message, null)
        }
    }

    private fun isGranted(): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    private fun openSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        // Android 11+ can deep-link to our own row; older versions show the list.
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            val component = ComponentName(context, DiaryNotificationListener::class.java)
            val detail = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (detail.resolveActivity(context.packageManager) != null) {
                context.startActivity(detail)
                return
            }
        }
        context.startActivity(intent)
    }

    /**
     * Launchable apps only, sorted by label, each with a 48dp PNG icon. Runs
     * off the main thread: `getInstalledApplications` plus rasterising every
     * icon takes seconds on a loaded phone, and the Dart side caches the
     * answer for the session.
     */
    private fun installedApps(result: MethodChannel.Result) {
        executor.execute {
            val out: List<Map<String, Any?>> = try {
                val pm = context.packageManager
                val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                val activities = pm.queryIntentActivities(launcher, 0)
                val seen = HashSet<String>()
                val apps = ArrayList<Map<String, Any?>>()
                for (info in activities) {
                    val pkg = info.activityInfo.packageName
                    if (pkg == context.packageName || !seen.add(pkg)) continue
                    val label = info.loadLabel(pm).toString()
                    val icon = try {
                        iconPng(info.loadIcon(pm))
                    } catch (_: Exception) {
                        null
                    }
                    apps.add(mapOf("packageName" to pkg, "label" to label, "iconPng" to icon))
                }
                apps.sortBy { (it["label"] as String).lowercase() }
                apps
            } catch (_: Exception) {
                emptyList()
            }
            mainHandler.post { result.success(out) }
        }
    }

    private fun iconPng(drawable: Drawable): String {
        val px = (ICON_DP * context.resources.displayMetrics.density).toInt().coerceAtLeast(1)
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, px, px, true)
        } else {
            val b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(b)
            drawable.setBounds(0, 0, px, px)
            drawable.draw(canvas)
            b
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}
