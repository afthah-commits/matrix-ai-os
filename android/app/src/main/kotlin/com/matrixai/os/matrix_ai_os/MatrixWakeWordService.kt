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
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
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
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/**
 * High-efficiency, zero-click native background wake-word service for Matrix AI OS.
 *
 * Architecture:
 * 1. Zero-Click VAD Energy Gate:
 *    - In silent room / background: Uses lightweight AudioRecord (16kHz mono PCM, tiny 2KB buffer).
 *    - SpeechRecognizer is 100% OFF during silence.
 *    - Absolutely ZERO audio focus requests, zero repeated click-click sounds, and near-zero battery drain.
 *
 * 2. On-Demand Single-Pass SpeechRecognizer:
 *    - Only when RMS voice energy exceeds threshold (human voice detected), AudioRecord pauses,
 *      and a single 3-second SpeechRecognizer pass evaluates "Hey Matrix" / "മാട്രിക്സ്".
 *    - Once evaluated (success, timeout, or no match), SpeechRecognizer immediately stops
 *      and the service seamlessly returns to silent AudioRecord VAD monitoring.
 *
 * 3. Siri-Style Floating Pop-Up:
 *    - On wake-word match, launches MatrixOverlayService floating pop-up without switching apps.
 */
class MatrixWakeWordService : Service() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var audioManager: AudioManager? = null
    private var isMutedForRecognition: Boolean = false
    private var lastTriggerTimestamp: Long = 0L

    // VAD AudioRecord Energy Gate State
    private var audioRecord: AudioRecord? = null
    private var vadThread: Thread? = null
    private val vadRunning = AtomicBoolean(false)
    private val isRecognizing = AtomicBoolean(false)
    private var consecutiveVoiceFrames: Int = 0

    private val recognitionTimeoutRunnable = Runnable {
        Log.d(TAG, "Speech recognition pass reached timeout (3.5s). Returning to silent VAD.")
        finishSpeechRecognitionPass()
    }

    override fun onCreate() {
        super.onCreate()
        serviceInstance = this
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        createNotificationChannel()
        startForegroundWithMicrophone()
        isRunning = true
        isPaused = false
        Log.i(TAG, "MatrixWakeWordService started (Zero-Click VAD Energy Gate Mode)")
        mainHandler.post { initServiceEngines() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(TAG, "Stopping MatrixWakeWordService by request")
                restoreAudioStreams()
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
                intent?.getStringExtra(EXTRA_LANGUAGE)?.let {
                    currentLanguage = it
                }
                if (!isPaused && isRunning && !isRecognizing.get() && !vadRunning.get()) {
                    mainHandler.post { startVadEnergyGate() }
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
        stopVadEnergyGate()
        destroySpeechRecognizer()
        restoreAudioStreams()
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
                description = "Silent hands-free wake-word detection for Matrix AI"
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

    private fun initServiceEngines() {
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
        startVadEnergyGate()
    }

    /**
     * Initializes the SpeechRecognizer instance for single-pass recognition.
     */
    private fun initSpeechRecognizer() {
        destroySpeechRecognizer()
        try {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        mainHandler.postDelayed({ restoreAudioStreams() }, 100L)
                    }

                    override fun onBeginningOfSpeech() {
                        Log.d(TAG, "SpeechRecognizer: Beginning of human speech detected")
                    }

                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}

                    override fun onError(error: Int) {
                        Log.d(TAG, "SpeechRecognizer single pass ended (code: $error). Returning to silent VAD.")
                        finishSpeechRecognitionPass()
                    }

                    override fun onResults(results: Bundle?) {
                        handleSpeechResults(results)
                        finishSpeechRecognitionPass()
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        handlePartialResults(partialResults)
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to instantiate SpeechRecognizer: ${e.message}")
            restoreAudioStreams()
            isRecognizing.set(false)
            mainHandler.postDelayed({ startVadEnergyGate() }, 2000L)
        }
    }

    /**
     * Starts the lightweight AudioRecord Voice Activity Detection (VAD) energy gate.
     * SpeechRecognizer stays completely OFF while this gate runs.
     */
    private fun startVadEnergyGate() {
        if (!isRunning || isPaused || isRecognizing.get()) return

        stopVadEnergyGate()

        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "RECORD_AUDIO permission revoked; stopping service")
            stopSelf()
            return
        }

        try {
            val minBuf = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            val bufSize = minBuf.coerceAtLeast(BUFFER_SIZE_SHORTS * 2)

            var record: AudioRecord? = null
            try {
                record = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufSize
                )
            } catch (e: Exception) {
                Log.w(TAG, "AudioSource.VOICE_RECOGNITION unavailable: ${e.message}")
            }

            if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
                record?.release()
                record = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufSize
                )
            }

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord state not initialized")
                record.release()
                mainHandler.postDelayed({ startVadEnergyGate() }, 2000L)
                return
            }

            audioRecord = record
            record.startRecording()
            vadRunning.set(true)
            consecutiveVoiceFrames = 0

            Log.i(TAG, "VAD Energy Gate active (Listening silently, SpeechRecognizer is 100% OFF)")

            vadThread = Thread({
                val buffer = ShortArray(BUFFER_SIZE_SHORTS)
                while (vadRunning.get() && isRunning && !isPaused) {
                    val rec = audioRecord ?: break
                    val read = rec.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        var sumSq = 0.0
                        for (i in 0 until read) {
                            val sample = buffer[i].toDouble()
                            sumSq += sample * sample
                        }
                        val rms = sqrt(sumSq / read)

                        if (rms >= VAD_RMS_THRESHOLD) {
                            consecutiveVoiceFrames++
                            if (consecutiveVoiceFrames >= VAD_CONSECUTIVE_FRAMES) {
                                consecutiveVoiceFrames = 0
                                Log.i(TAG, "Voice energy detected (RMS: ${rms.toInt()} >= $VAD_RMS_THRESHOLD). Activating single SpeechRecognizer pass!")
                                mainHandler.post { triggerSpeechRecognitionPass() }
                                break
                            }
                        } else {
                            consecutiveVoiceFrames = 0
                        }
                    } else {
                        try {
                            Thread.sleep(40L)
                        } catch (_: InterruptedException) {
                            break
                        }
                    }
                }
            }, "Matrix-VAD-Thread").apply {
                priority = Thread.NORM_PRIORITY
                start()
            }
        } catch (e: Exception) {
            Log.e(TAG, "startVadEnergyGate error: ${e.message}")
            mainHandler.postDelayed({ startVadEnergyGate() }, 2000L)
        }
    }

    /**
     * Stops the AudioRecord VAD gate and releases the hardware microphone.
     */
    private fun stopVadEnergyGate() {
        vadRunning.set(false)
        try {
            vadThread?.interrupt()
            vadThread = null
        } catch (_: Exception) {}

        try {
            audioRecord?.let {
                if (it.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    it.stop()
                }
                it.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "stopVadEnergyGate error: ${e.message}")
        } finally {
            audioRecord = null
        }
    }

    /**
     * Activated strictly when Voice Activity Detection detects human speech energy.
     */
    private fun triggerSpeechRecognitionPass() {
        if (!isRunning || isPaused || isRecognizing.get()) return

        stopVadEnergyGate()
        isRecognizing.set(true)

        // Safety watchdog: Return to silent VAD if SpeechRecognizer hangs or times out
        mainHandler.removeCallbacks(recognitionTimeoutRunnable)
        mainHandler.postDelayed(recognitionTimeoutRunnable, 3500L)

        safeStartListening()
    }

    private fun safeStartListening() {
        if (!isRunning || isPaused) {
            isRecognizing.set(false)
            return
        }

        try {
            muteAudioStreams()

            val localeTag = if (currentLanguage == "ml") "ml-IN" else Locale.getDefault().toLanguageTag()

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            speechRecognizer?.startListening(intent)
        } catch (e: Exception) {
            Log.w(TAG, "safeStartListening failed: ${e.message}")
            finishSpeechRecognitionPass()
        }
    }

    /**
     * Finishes the single recognition pass and safely returns to silent AudioRecord VAD monitoring.
     */
    private fun finishSpeechRecognitionPass() {
        mainHandler.removeCallbacks(recognitionTimeoutRunnable)
        restoreAudioStreams()

        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping recognizer: ${e.message}")
        }

        isRecognizing.set(false)

        if (isRunning && !isPaused) {
            // Re-activate silent VAD gate after 150ms settling cooldown
            mainHandler.postDelayed({ startVadEnergyGate() }, 150L)
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

    private fun onWakeWordDetected(query: String?) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastTriggerTimestamp < COOLDOWN_MS) {
            return
        }
        lastTriggerTimestamp = now
        Log.i(TAG, "Wake-word triggered! Initial query: $query")

        // Yield microphone to the foreground voice session
        pauseListening()

        // Haptic feedback pulse
        triggerVibration()

        // Wake screen display if phone is sleeping
        wakeScreenDisplay()

        // Launch Siri-style floating pop-up overlay if permission granted
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(this)) {
            val overlayIntent = Intent(this, MatrixOverlayService::class.java).apply {
                putExtra(EXTRA_INITIAL_QUERY, query)
                putExtra(EXTRA_TRIGGER_TYPE, "wake_word")
                putExtra(EXTRA_LANGUAGE, currentLanguage)
            }
            startService(overlayIntent)
        } else {
            // Fallback to full MainActivity if overlay permission not granted
            launchMainActivity(query)
        }
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

    fun pauseListening() {
        isPaused = true
        mainHandler.removeCallbacks(recognitionTimeoutRunnable)
        stopVadEnergyGate()
        restoreAudioStreams()
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "Error pausing recognizer: ${e.message}")
        }
        isRecognizing.set(false)
    }

    fun resumeListening() {
        if (!isRunning) return
        isPaused = false
        mainHandler.post { startVadEnergyGate() }
    }

    private fun destroySpeechRecognizer() {
        try {
            restoreAudioStreams()
            speechRecognizer?.destroy()
        } catch (e: Exception) {
            Log.w(TAG, "Error destroying speechRecognizer: ${e.message}")
        } finally {
            speechRecognizer = null
        }
    }

    /**
     * Mutes notification, system, and music streams temporarily to suppress Android's
     * native SpeechRecognizer start/restart beep tones.
     */
    private fun muteAudioStreams() {
        try {
            audioManager?.let { am ->
                if (!isMutedForRecognition) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            am.adjustStreamVolume(AudioManager.STREAM_SYSTEM, AudioManager.ADJUST_MUTE, 0)
                            am.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_MUTE, 0)
                            am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, 0)
                        } catch (_: SecurityException) {}
                    } else {
                        @Suppress("DEPRECATION")
                        am.setStreamMute(AudioManager.STREAM_SYSTEM, true)
                        @Suppress("DEPRECATION")
                        am.setStreamMute(AudioManager.STREAM_NOTIFICATION, true)
                        @Suppress("DEPRECATION")
                        am.setStreamMute(AudioManager.STREAM_MUSIC, true)
                    }
                    isMutedForRecognition = true
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "muteAudioStreams error: ${e.message}")
        }
    }

    /**
     * Restores audio streams to unmuted state.
     */
    private fun restoreAudioStreams() {
        try {
            audioManager?.let { am ->
                if (isMutedForRecognition) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            am.adjustStreamVolume(AudioManager.STREAM_SYSTEM, AudioManager.ADJUST_UNMUTE, 0)
                            am.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_UNMUTE, 0)
                            am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, 0)
                        } catch (_: SecurityException) {}
                    } else {
                        @Suppress("DEPRECATION")
                        am.setStreamMute(AudioManager.STREAM_SYSTEM, false)
                        @Suppress("DEPRECATION")
                        am.setStreamMute(AudioManager.STREAM_NOTIFICATION, false)
                        @Suppress("DEPRECATION")
                        am.setStreamMute(AudioManager.STREAM_MUSIC, false)
                    }
                    isMutedForRecognition = false
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "restoreAudioStreams error: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "MatrixWakeWord"
        const val CHANNEL_ID = "matrix_wake_word_channel"
        const val NOTIFICATION_ID = 2001
        const val EXTRA_WAKE_WORD_TRIGGERED = "EXTRA_WAKE_WORD_TRIGGERED"
        const val EXTRA_INITIAL_QUERY = "EXTRA_INITIAL_QUERY"
        const val EXTRA_TRIGGER_TYPE = "EXTRA_TRIGGER_TYPE"
        const val EXTRA_LANGUAGE = "EXTRA_LANGUAGE"
        const val ACTION_START = "com.matrixai.os.action.START_WAKE_WORD"
        const val ACTION_STOP = "com.matrixai.os.action.STOP_WAKE_WORD"
        const val ACTION_PAUSE = "com.matrixai.os.action.PAUSE_WAKE_WORD"
        const val ACTION_RESUME = "com.matrixai.os.action.RESUME_WAKE_WORD"
        const val ACTION_WAKE_WORD_TRIGGERED = "com.matrixai.os.action.WAKE_WORD_TRIGGERED"

        // VAD Tuning Parameters
        private const val SAMPLE_RATE = 16000
        private const val BUFFER_SIZE_SHORTS = 1024 // 2048 bytes (64ms)
        private const val VAD_RMS_THRESHOLD = 950.0 // RMS voice energy threshold
        private const val VAD_CONSECUTIVE_FRAMES = 2 // ~128ms of speech energy to trigger recognizer
        private const val COOLDOWN_MS = 3000L

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isPaused: Boolean = false
            private set

        @Volatile
        var currentLanguage: String = "en"

        var serviceInstance: MatrixWakeWordService? = null

        private val WAKE_PATTERNS = listOf(
            Regex("""\bhey\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bhi\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bhello\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bok\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bokay\s+matrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bmatrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bhey\s+metrix\b""", RegexOption.IGNORE_CASE),
            Regex("""\bmetrix\b""", RegexOption.IGNORE_CASE),
            // Malayalam Wake-Word Patterns
            Regex("""\bഹേയ്\s+മാട്രിക്സ്\b""", RegexOption.IGNORE_CASE),
            Regex("""\bമാട്രിക്സ്\b""", RegexOption.IGNORE_CASE)
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
