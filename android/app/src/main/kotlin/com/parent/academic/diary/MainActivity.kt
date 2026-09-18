package com.parent.academic.diary

import com.parent.academic.diary.notifications.NotificationCapturePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Prompt 03: the notification-capture channel. Registered here rather
        // than as a pub plugin because it is this app's own feature.
        NotificationCapturePlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)
    }
}
