package com.matrixai.os.matrix_ai_os

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var deviceStatsChannel: DeviceStatsChannel? = null
    private var notificationChannel: MethodChannel? = null
    private var actionExecutorChannel: ActionExecutorChannel? = null
    private var localSlmChannel: LocalSlmChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 1. Register DeviceStats MethodChannel
        deviceStatsChannel = DeviceStatsChannel(applicationContext, messenger)

        // 2. Register Notification Streaming MethodChannel
        notificationChannel = MethodChannel(messenger, NOTIFICATION_CHANNEL_NAME)

        // 3. Register ActionExecutor MethodChannel
        actionExecutorChannel = ActionExecutorChannel(applicationContext, messenger)

        // 4. Register LocalSlm MethodChannel
        localSlmChannel = LocalSlmChannel(applicationContext, messenger)

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
        actionExecutorChannel?.cleanUp()
        actionExecutorChannel = null
        localSlmChannel?.cleanUp()
        localSlmChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        const val NOTIFICATION_CHANNEL_NAME = "com.matrixai.os/notifications"
    }
}
