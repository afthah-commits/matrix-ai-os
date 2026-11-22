package com.matrixai.os.matrix_ai_os

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var deviceStatsChannel: DeviceStatsChannel? = null
    private var notificationChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 1. Register DeviceStats MethodChannel
        deviceStatsChannel = DeviceStatsChannel(applicationContext, messenger)

        // 2. Register Notification Streaming MethodChannel
        notificationChannel = MethodChannel(messenger, NOTIFICATION_CHANNEL_NAME)

        // Forward live background notifications to Flutter if engine is running
        MatrixNotificationListener.listenerCallback = { notificationData ->
            runOnUiThread {
                try {
                    notificationChannel?.invokeMethod("onNotificationReceived", notificationData)
                } catch (_: Exception) {}
            }
            true
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MatrixNotificationListener.listenerCallback = null
        deviceStatsChannel?.cleanUp()
        deviceStatsChannel = null
        notificationChannel?.setMethodCallHandler(null)
        notificationChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        const val NOTIFICATION_CHANNEL_NAME = "com.matrixai.os/notifications"
    }
}
