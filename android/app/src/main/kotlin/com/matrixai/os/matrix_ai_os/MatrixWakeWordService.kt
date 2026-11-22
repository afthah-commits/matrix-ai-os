package com.matrixai.os.matrix_ai_os

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Locale

/**
 * Lightweight, battery-aware foreground service that continuously listens
 * for the "Hey Matrix" wake phrase using Android's native SpeechRecognizer.
 *
 * Runs with zero bundled neural models to keep APK size strictly minimal.
 */
class MatrixWakeWordService : Service() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var backoffDelayMs: Long = BASE_DELAY_MS
    private var lastTriggerTimestamp: Long = 0L

    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
        createNotificationChannel()
        startForegroundWithMicrophone()
        isRunning = true
        isPaused = false
        Log.i(TAG, "MatrixWakeWordService started")
        mainHandler.post { initAndStartListening() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(TAG, "Stopping MatrixWakeWordService by request")
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_PAUSE -> {
                Log.i(TAG, "Pausing wake-word listener (mic yielded to foreground)")
                pauseListening()
            }
            ACTION_RESUME -> {
                Log.i(TAG, "Resuming wake-word listener")
                resumeListening()
            }
            else -> {
                if (!isPaused && isRunning) {
                    mainHandler.post { safeStartListening() }
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isRunning = false
        isPaused = false
        serviceInstance = null
        mainHandler.removeCallbacksAndMessages(null)
        destroySpeechRecognizer()
        Log.i(TAG, "MatrixWakeWordService destroyed")
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Matrix Voice Assistant",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Hands-free wake-word detection for Matrix AI"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundWithMicrophone() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Matrix AI OS")
            .setContentText("Listening hands-free for 'Hey Matrix'...")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun initAndStartListening() {
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "RECORD_AUDIO permission not granted; stopping wake-word service")
            stopSelf()
            return
        }

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.e(TAG, "SpeechRecognizer is unavailable on this device")
            stopSelf()
            return
        }

        initSpeechRecognizer()
        safeStartListening()
    }

    private fun initSpeechRecognizer() {
        destroySpeechRecognizer()
        try {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {}
                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}

                    override fun onError(error: Int) {
                        handleSpeechError(error)
                    }

                    override fun onResults(results: Bundle?) {
                        handleSpeechResults(results)
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        handlePartialResults(partialResults)
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to instantiate SpeechRecognizer: ${e.message}")
            scheduleRestart(MAX_BACKOFF_MS)
        }
    }

    private fun safeStartListening() {
        if (!isRunning || isPaused) return
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            speechRecognizer?.startListening(intent)
        } catch (e: Exception) {
            Log.w(TAG, "safeStartListening failed: ${e.message}")
            scheduleRestart(2000L)
        }
    }

    private fun handlePartialResults(bundle: Bundle?) {
        val matches = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (!matches.isNullOrEmpty()) {
            for (text in matches) {
                val (found, remainder) = evaluateWakePhrase(text)
                if (found) {
                    onWakeWordDetected(remainder)
                    return
                }
            }
        }
    }

    private fun handleSpeechResults(bundle: Bundle?) {
        val matches = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        var detected = false
        if (!matches.isNullOrEmpty()) {
            for (text in matches) {
                val (found, remainder) = evaluateWakePhrase(text)
                if (found) {
                    detected = true
                    onWakeWordDetected(remainder)
                    break
                }
            }
        }

        if (!detected && isRunning && !isPaused) {
            backoffDelayMs = BASE_DELAY_MS
            scheduleRestart(100L)
        }
    }

    private fun handleSpeechError(error: Int) {
        if (!isRunning || isPaused) return
        when (error) {
            SpeechRecognizer.ERROR_NO_MATCH,
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                backoffDelayMs = BASE_DELAY_MS
                scheduleRestart(150L)
            }
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
            SpeechRecognizer.ERROR_AUDIO,
            SpeechRecognizer.ERROR_SERVER,
            SpeechRecognizer.ERROR_NETWORK,
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
            SpeechRecognizer.ERROR_CLIENT -> {
                val delay = backoffDelayMs
                backoffDelayMs = (backoffDelayMs * 2).coerceAtMost(MAX_BACKOFF_MS)
                Log.w(TAG, "SpeechRecognizer error ($error), backing off ${delay}ms")
                scheduleRestart(delay)
            }
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                Log.e(TAG, "Permissions revoked. Stopping service.")
                stopSelf()
            }
            else -> {
                scheduleRestart(1000L)
            }
        }
    }

    private fun onWakeWordDetected(query: String?) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastTriggerTimestamp < COOLDOWN_MS) {
            return
        }
        lastTriggerTimestamp = now
        Log.i(TAG, "Wake-word triggered! Initial query: $query")

        // Yield microphone to the foreground activity
        pauseListening()

        // Haptic pulse
        triggerVibration()

        // Wake screen if currently sleeping
        wakeScreenDisplay()

        // Bring app to the foreground
        launchMainActivity(query)
    }

    private fun triggerVibration() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                manager?.defaultVibrator?.vibrate(
                    VibrationEffect.createOneShot(120, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(
                        VibrationEffect.createOneShot(120, VibrationEffect.DEFAULT_AMPLITUDE)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(120)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Vibration feedback error: ${e.message}")
        }
    }

    private fun wakeScreenDisplay() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager?.isInteractive == false) {
                @Suppress("DEPRECATION")
                val wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                    "matrix:wake_word_lock"
                )
                wakeLock.acquire(3000L)
            }
        } catch (e: Exception) {
            Log.w(TAG, "WakeLock acquisition error: ${e.message}")
        }
    }

    private fun launchMainActivity(query: String?) {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                action = ACTION_WAKE_WORD_TRIGGERED
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                putExtra(EXTRA_WAKE_WORD_TRIGGERED, true)
                putExtra(EXTRA_TRIGGER_TYPE, "wake_word")
                putExtra(EXTRA_INITIAL_QUERY, query)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch MainActivity: ${e.message}")
        }
    }

    private fun scheduleRestart(delayMs: Long) {
        if (!isRunning || isPaused) return
        mainHandler.removeCallbacks(restartRunnable)
        mainHandler.postDelayed(restartRunnable, delayMs)
    }

    private val restartRunnable = Runnable {
        if (isRunning && !isPaused) {
            safeStartListening()
        }
    }

    fun pauseListening() {
        isPaused = true
        mainHandler.removeCallbacks(restartRunnable)
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "Error pausing recognizer: ${e.message}")
        }
    }

    fun resumeListening() {
        if (!isRunning) return
        isPaused = false
        backoffDelayMs = BASE_DELAY_MS
        scheduleRestart(300L)
    }

    private fun destroySpeechRecognizer() {
        try {
            speechRecognizer?.destroy()
        } catch (e: Exception) {
            Log.w(TAG, "Error destroying speechRecognizer: ${e.message}")
        } finally {
            speechRecognizer = null
        }
    }

    companion object {
        private const val TAG = "MatrixWakeWordService"
        const val CHANNEL_ID = "matrix_wake_word_channel"
        const val NOTIFICATION_ID = 2001
        const val EXTRA_WAKE_WORD_TRIGGERED = "EXTRA_WAKE_WORD_TRIGGERED"
        const val EXTRA_INITIAL_QUERY = "EXTRA_INITIAL_QUERY"
        const val EXTRA_TRIGGER_TYPE = "EXTRA_TRIGGER_TYPE"
        const val ACTION_START = "com.matrixai.os.action.START_WAKE_WORD"
        const val ACTION_STOP = "com.matrixai.os.action.STOP_WAKE_WORD"
        const val ACTION_PAUSE = "com.matrixai.os.action.PAUSE_WAKE_WORD"
        const val ACTION_RESUME = "com.matrixai.os.action.RESUME_WAKE_WORD"
        const val ACTION_WAKE_WORD_TRIGGERED = "com.matrixai.os.action.WAKE_WORD_TRIGGERED"

        private const val BASE_DELAY_MS = 300L
        private const val MAX_BACKOFF_MS = 6000L
        private const val COOLDOWN_MS = 3000L

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isPaused: Boolean = false
            private set

        var serviceInstance: MatrixWakeWordService? = null

        private val WAKE_PATTERNS = listOf(
            Regex("""\bhey\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bhi\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bhello\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bok\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bokay\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bmatrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bhey\s+metrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bmetrix\b""", RegexOption.IGNORE_CASE)
        )

        /**
         * Checks if the transcribed phrase contains one of the wake patterns.
         * Returns (found, remainingQueryText).
         */
        fun evaluateWakePhrase(text: String): Pair<Boolean, String?> {
            val trimmed = text.trim()
            for (pattern in WAKE_PATTERNS) {
                val match = pattern.find(trimmed)
                if (match != null) {
                    val endIndex = match.range.last + 1
                    val remainder = trimmed.substring(endIndex).trim().trim(',', '.', '?', '!')
                    val query = if (remainder.isNotBlank()) remainder else null
                    return Pair(true, query)
                }
            }
            return Pair(false, null)
        }
    }
}
