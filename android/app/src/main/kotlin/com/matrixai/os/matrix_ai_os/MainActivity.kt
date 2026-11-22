package com.matrixai.os.matrix_ai_os

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var deviceStatsChannel: DeviceStatsChannel? = null
    private var notificationChannel: MethodChannel? = null
    private var actionExecutorChannel: ActionExecutorChannel? = null
    private var localSlmChannel: LocalSlmChannel? = null
    private var wakeWordChannel: MethodChannel? = null

    private var pendingWakeWordPayload: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAssistantOrWakeWordIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAssistantOrWakeWordIntent(intent)
    }

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

        // 5. Register WakeWord & Default Assistant MethodChannel
        setupWakeWordChannel(messenger)

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

    private fun setupWakeWordChannel(messenger: io.flutter.plugin.common.BinaryMessenger) {
        wakeWordChannel = MethodChannel(messenger, WAKE_WORD_CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startWakeWordService" -> {
                        val hasMic = ContextCompat.checkSelfPermission(
                            applicationContext,
                            android.Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!hasMic) {
                            result.error(
                                "PERMISSION_DENIED",
                                "Microphone permission is required to listen for 'Hey Matrix'",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val intent = Intent(applicationContext, MatrixWakeWordService::class.java).apply {
                            action = MatrixWakeWordService.ACTION_START
                        }
                        ContextCompat.startForegroundService(applicationContext, intent)
                        result.success(true)
                    }
                    "stopWakeWordService" -> {
                        val intent = Intent(applicationContext, MatrixWakeWordService::class.java).apply {
                            action = MatrixWakeWordService.ACTION_STOP
                        }
                        applicationContext.stopService(intent)
                        result.success(true)
                    }
                    "isWakeWordRunning" -> {
                        result.success(MatrixWakeWordService.isRunning)
                    }
                    "openDefaultAssistantSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_VOICE_INPUT_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            if (intent.resolveActivity(packageManager) != null) {
                                startActivity(intent)
                                result.success(true)
                            } else {
                                val fallback = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                if (fallback.resolveActivity(packageManager) != null) {
                                    startActivity(fallback)
                                    result.success(true)
                                } else {
                                    startActivity(Intent(Settings.ACTION_SETTINGS).apply {
                                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                    })
                                    result.success(true)
                                }
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to open assistant settings: ${e.message}")
                            result.error("INTENT_ERROR", e.message, null)
                        }
                    }
                    "onFlutterVoiceStarted" -> {
                        MatrixWakeWordService.serviceInstance?.pauseListening()
                        result.success(true)
                    }
                    "onFlutterVoiceStopped" -> {
                        MatrixWakeWordService.serviceInstance?.resumeListening()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Deliver any pending cold-boot assistant triggers
        pendingWakeWordPayload?.let { payload ->
            runOnUiThread {
                wakeWordChannel?.invokeMethod("onWakeWordDetected", payload)
            }
            pendingWakeWordPayload = null
        }
    }

    private fun handleAssistantOrWakeWordIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action
        val isWakeWord = intent.getBooleanExtra(MatrixWakeWordService.EXTRA_WAKE_WORD_TRIGGERED, false) ||
            action == MatrixWakeWordService.ACTION_WAKE_WORD_TRIGGERED
        val isAssist = action == Intent.ACTION_ASSIST || action == Intent.ACTION_VOICE_COMMAND

        if (isWakeWord || isAssist) {
            wakeScreenAndDismissKeyguard()

            val triggerType = when {
                action == Intent.ACTION_ASSIST -> "assist_intent"
                action == Intent.ACTION_VOICE_COMMAND -> "voice_command"
                else -> "wake_word"
            }
            val initialQuery = intent.getStringExtra(MatrixWakeWordService.EXTRA_INITIAL_QUERY)

            val payload = mapOf(
                "trigger" to triggerType,
                "initialQuery" to initialQuery
            )

            if (wakeWordChannel != null) {
                runOnUiThread {
                    wakeWordChannel?.invokeMethod("onWakeWordDetected", payload)
                }
            } else {
                pendingWakeWordPayload = payload
            }
        }
    }

    private fun wakeScreenAndDismissKeyguard() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
                val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                keyguardManager?.requestDismissKeyguard(this, null)
            } else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Keyguard/Screen-on configuration failed: ${e.message}")
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
        wakeWordChannel?.setMethodCallHandler(null)
        wakeWordChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        private const val TAG = "MainActivity"
        const val NOTIFICATION_CHANNEL_NAME = "com.matrixai.os/notifications"
        const val WAKE_WORD_CHANNEL_NAME = "com.matrixai.os/wake_word"
    }
}
