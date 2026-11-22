package com.matrixai.os.matrix_ai_os

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private var pendingPickResult: MethodChannel.Result? = null

    private var deviceStatsChannel: DeviceStatsChannel? = null
    private var notificationChannel: MethodChannel? = null
    private var actionExecutorChannel: ActionExecutorChannel? = null
    private var localSlmChannel: LocalSlmChannel? = null
    private var wakeWordChannel: MethodChannel? = null

    private var pendingWakeWordPayload: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawableResource(android.R.color.black)
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
        actionExecutorChannel = ActionExecutorChannel(applicationContext, messenger).apply {
            pickerLauncher = { res -> launchDocumentPicker(res) }
        }

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
                    "isOverlayPermissionGranted" -> {
                        val hasOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Settings.canDrawOverlays(applicationContext)
                        } else {
                            true
                        }
                        result.success(hasOverlay)
                    }
                    "openOverlayPermissionSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                ).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to open overlay permission settings: ${e.message}")
                            result.error("INTENT_ERROR", e.message, null)
                        }
                    }
                    "setLanguage" -> {
                        val lang = call.argument<String>("language") ?: "en"
                        MatrixWakeWordService.currentLanguage = lang
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
            if (isAssist && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(this)) {
                val overlayIntent = Intent(this, MatrixOverlayService::class.java).apply {
                    putExtra(MatrixWakeWordService.EXTRA_TRIGGER_TYPE, "assist_intent")
                    putExtra(MatrixWakeWordService.EXTRA_LANGUAGE, MatrixWakeWordService.currentLanguage)
                }
                startService(overlayIntent)
                moveTaskToBack(true)
                return
            }

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

    fun launchDocumentPicker(result: MethodChannel.Result) {
        pendingPickResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "application/pdf"))
            }
            startActivityForResult(intent, REQUEST_PICK_DOCUMENT)
        } catch (e: Exception) {
            Log.e(TAG, "Error launching document picker: ${e.message}")
            pendingPickResult = null
            result.error("PICKER_ERROR", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_DOCUMENT) {
            val result = pendingPickResult
            pendingPickResult = null
            if (resultCode == RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: Exception) {}

                var displayName = "uploaded_document"
                var size = 0L
                try {
                    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                            if (nameIdx >= 0) displayName = cursor.getString(nameIdx) ?: displayName
                            if (sizeIdx >= 0) size = cursor.getLong(sizeIdx)
                        }
                    }
                } catch (_: Exception) {}

                val mimeType = contentResolver.getType(uri) ?: (
                    if (displayName.endsWith(".pdf", ignoreCase = true)) "application/pdf" else "image/jpeg"
                )

                val uploadDir = File(cacheDir, "vault_uploads").apply { mkdirs() }
                val cachedFile = File(uploadDir, displayName)
                try {
                    contentResolver.openInputStream(uri)?.use { input ->
                        cachedFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Error caching picked document: ${e.message}")
                }

                result?.success(mapOf(
                    "success" to true,
                    "uri" to uri.toString(),
                    "filePath" to cachedFile.absolutePath,
                    "fileName" to displayName,
                    "mimeType" to mimeType,
                    "fileSize" to size
                ))
            } else {
                result?.success(mapOf(
                    "success" to false,
                    "canceled" to true
                ))
            }
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
        const val REQUEST_PICK_DOCUMENT = 9911
    }
}
