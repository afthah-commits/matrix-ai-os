package com.matrixai.os.matrix_ai_os

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.util.Locale

/**
 * Native Android Floating Siri-Style Pop-Up Overlay Service.
 *
 * Appears dynamically over lock-screen, home-screen, or third-party apps
 * when "Hey Matrix" is triggered hands-free.
 *
 * Displays live speech transcription, executes phone actions directly in-place,
 * speaks confirmations via native TTS, and smoothly auto-dismisses.
 */
class MatrixOverlayService : Service(), TextToSpeech.OnInitListener {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlayContainer: FrameLayout? = null

    private var speechRecognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var isTtsReady = false

    private lateinit var statusText: TextView
    private lateinit var transcriptText: TextView
    private lateinit var actionBadge: TextView
    private lateinit var glowingOrb: View

    private var currentLanguage = "en"
    private var isActionExecuted = false

    override fun onCreate() {
        super.onCreate()
        startForegroundNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w(TAG, "Overlay permission not granted; stopping MatrixOverlayService")
            stopSelf()
            return
        }

        windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        tts = TextToSpeech(this, this)
        buildOverlayView()
    }

    private fun startForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                OVERLAY_CHANNEL_ID,
                "Matrix Voice Assistant Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Floating Siri-Style Voice Overlay for Matrix AI"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, OVERLAY_CHANNEL_ID)
            .setContentTitle("Matrix AI OS")
            .setContentText("Voice Assistant Overlay active")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(OVERLAY_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(OVERLAY_NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val query = intent?.getStringExtra(MatrixWakeWordService.EXTRA_INITIAL_QUERY)?.trim()
        val lang = intent?.getStringExtra(MatrixWakeWordService.EXTRA_LANGUAGE) ?: MatrixWakeWordService.currentLanguage
        currentLanguage = lang

        updateLanguageUi()

        if (!query.isNullOrEmpty()) {
            transcriptText.text = "\"$query\""
            executeVoiceCommand(query)
        } else {
            startSpeechRecognition()
        }

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isTtsReady = true
            val locale = if (currentLanguage == "ml") Locale("ml", "IN") else Locale.US
            tts?.language = locale
            tts?.setSpeechRate(0.95f)
        }
    }

    private fun buildOverlayView() {
        val wm = windowManager ?: return

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dpToPx(24)
        }

        val root = FrameLayout(this).apply {
            setPadding(dpToPx(16), 0, dpToPx(16), dpToPx(16))
        }

        // Inner glowing glass card
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(18), dpToPx(16), dpToPx(18), dpToPx(16))

            val bg = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#E61E1B4B"), Color.parseColor("#F20F172A"))
            ).apply {
                cornerRadius = dpToPx(22).toFloat()
                setStroke(dpToPx(1.5f), Color.parseColor("#10B981")) // Emerald glow border
            }
            background = bg
            elevation = dpToPx(12).toFloat()
        }

        // Header Row: Glowing Orb + Title + Buttons
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        // Animated glowing pulsing orb
        glowingOrb = View(this).apply {
            val orbDrawable = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#10B981"))
            }
            background = orbDrawable
            layoutParams = LinearLayout.LayoutParams(dpToPx(12), dpToPx(12))
        }
        startPulsingAnimation(glowingOrb)

        statusText = TextView(this).apply {
            text = "MATRIX ASSISTANT"
            setTextColor(Color.parseColor("#10B981"))
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.08f
            setPadding(dpToPx(8), 0, 0, 0)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }

        // Expand to Full App Button
        val expandBtn = TextView(this).apply {
            text = "⤢"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 18f
            setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
            setOnClickListener {
                expandToFullApp()
            }
        }

        // Close Button
        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 15f
            setPadding(dpToPx(10), dpToPx(4), dpToPx(6), dpToPx(4))
            setOnClickListener {
                dismissOverlay()
            }
        }

        headerRow.addView(glowingOrb)
        headerRow.addView(statusText)
        headerRow.addView(expandBtn)
        headerRow.addView(closeBtn)

        // Middle Row: Live Transcript Box
        transcriptText = TextView(this).apply {
            text = "Listening hands-free..."
            setTextColor(Color.WHITE)
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dpToPx(10), 0, dpToPx(8))
        }

        // Bottom Row: Status / Action Pill
        actionBadge = TextView(this).apply {
            text = "Ready"
            setTextColor(Color.parseColor("#06B6D4"))
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            val badgeBg = GradientDrawable().apply {
                setColor(Color.parseColor("#2606B6D4"))
                cornerRadius = dpToPx(8).toFloat()
            }
            background = badgeBg
            setPadding(dpToPx(10), dpToPx(4), dpToPx(10), dpToPx(4))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        card.addView(headerRow)
        card.addView(transcriptText)
        card.addView(actionBadge)
        root.addView(card)

        overlayContainer = root
        try {
            wm.addView(root, params)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to attach overlay window: ${e.message}")
            stopSelf()
        }
    }

    private fun updateLanguageUi() {
        if (currentLanguage == "ml") {
            statusText.text = "മാട്രിക്സ് അസിസ്റ്റന്റ്"
            transcriptText.text = "കേൾക്കുന്നു..."
            actionBadge.text = "സജീവം"
        } else {
            statusText.text = "MATRIX ASSISTANT"
            transcriptText.text = "Listening hands-free..."
            actionBadge.text = "Ready"
        }
    }

    private fun startSpeechRecognition() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            statusText.text = "Speech Recognizer Unavailable"
            return
        }

        try {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        actionBadge.text = if (currentLanguage == "ml") "സംസാരിക്കൂ..." else "Listening..."
                    }
                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {
                        actionBadge.text = if (currentLanguage == "ml") "പ്രോസസ്സ് ചെയ്യുന്നു..." else "Processing..."
                    }

                    override fun onError(error: Int) {
                        Log.w(TAG, "Overlay SpeechRecognizer error: $error")
                        mainHandler.postDelayed({ dismissOverlay() }, 1800L)
                    }

                    override fun onResults(results: Bundle?) {
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        if (!matches.isNullOrEmpty()) {
                            val recognized = matches[0]
                            transcriptText.text = "\"$recognized\""
                            executeVoiceCommand(recognized)
                        } else {
                            dismissOverlay()
                        }
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        if (!matches.isNullOrEmpty()) {
                            transcriptText.text = "\"${matches[0]}\""
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })
            }

            val localeTag = if (currentLanguage == "ml") "ml-IN" else Locale.getDefault().toLanguageTag()
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            speechRecognizer?.startListening(intent)
        } catch (e: Exception) {
            Log.e(TAG, "SpeechRecognizer start error: ${e.message}")
            dismissOverlay()
        }
    }

    /**
     * Executes parsed voice commands directly on the phone.
     */
    private fun executeVoiceCommand(rawCommand: String) {
        if (isActionExecuted) return
        isActionExecuted = true
        val command = rawCommand.trim()
        val lower = command.lowercase()

        // 1. WhatsApp Direct Messaging (English & Malayalam)
        // E.g.: "Send Hi to Rahulan on WhatsApp", "WhatsApp Rahulan saying hello", "രാഹുലിന് വാട്സാപ്പിൽ ഹായ് അയക്കൂ"
        val waRegexEn = Regex("""(?:send\s+)?(?:message\s+)?(.+?)\s+(?:to\s+)?(.+?)\s+(?:on|via)\s+whatsapp""", RegexOption.IGNORE_CASE)
        val waRegexEnAlt = Regex("""whatsapp\s+(.+?)\s+(?:saying|message)?\s*(.+)""", RegexOption.IGNORE_CASE)
        val waRegexMl = Regex("""(.+?)(?:-ന്|ക്ക്|ന്)?\s+വാട്സാപ്പിൽ\s+(.+?)\s+അയക്കൂ""", RegexOption.IGNORE_CASE)

        var waContact: String? = null
        var waMessage: String? = null

        val mlMatch = waRegexMl.find(command)
        if (mlMatch != null) {
            waContact = mlMatch.groupValues[1].trim()
            waMessage = mlMatch.groupValues[2].trim()
        } else {
            val enMatch = waRegexEn.find(command)
            if (enMatch != null) {
                // E.g. "Send Hi to Rahulan on WhatsApp" -> g1="Hi", g2="Rahulan"
                waMessage = enMatch.groupValues[1].trim()
                waContact = enMatch.groupValues[2].trim()
            } else {
                val enAltMatch = waRegexEnAlt.find(command)
                if (enAltMatch != null) {
                    waContact = enAltMatch.groupValues[1].trim()
                    waMessage = enAltMatch.groupValues[2].trim()
                }
            }
        }

        if (waContact != null && waMessage != null) {
            actionBadge.text = if (currentLanguage == "ml") "വാട്സാപ്പ് സന്ദേശം അയക്കുന്നു..." else "Sending WhatsApp..."
            ActionExecutorChannel.composeWhatsAppMessage(this, waContact, waMessage, autoSend = true)
            speakFeedback(
                if (currentLanguage == "ml") "$waContact-ന് വാട്സാപ്പിൽ സന്ദേശം അയക്കുന്നു" else "Sending WhatsApp message to $waContact"
            )
            scheduleAutoDismiss(2000L)
            return
        }

        // 2. App Launching (English & Malayalam)
        // E.g.: "Open YouTube", "Launch Camera", "യൂട്യൂബ് തുറക്കൂ", "ക്യാമറ തുറക്കൂ"
        val openAppRegexEn = Regex("""(?:open|launch|start)\s+(.+)""", RegexOption.IGNORE_CASE)
        val openAppRegexMl = Regex("""(.+?)\s+(?:തുറക്കൂ|ഓപ്പൺ ചെയ്യൂ|തുറക്കുക)""", RegexOption.IGNORE_CASE)

        var appToLaunch: String? = null
        val appMlMatch = openAppRegexMl.find(command)
        if (appMlMatch != null) {
            appToLaunch = appMlMatch.groupValues[1].trim()
        } else {
            val appEnMatch = openAppRegexEn.find(command)
            if (appEnMatch != null) {
                appToLaunch = appEnMatch.groupValues[1].trim()
            }
        }

        if (appToLaunch != null) {
            actionBadge.text = if (currentLanguage == "ml") "ആപ്പ് തുറക്കുന്നു..." else "Opening $appToLaunch..."
            val result = ActionExecutorChannel.launchAppByName(this, appToLaunch)
            if (result["success"] == true) {
                val launchedName = result["appName"] ?: appToLaunch
                speakFeedback(if (currentLanguage == "ml") "$launchedName തുറക്കുന്നു" else "Opening $launchedName")
            } else {
                speakFeedback(if (currentLanguage == "ml") "$appToLaunch കണ്ടെത്താനായില്ല" else "Could not find $appToLaunch")
            }
            scheduleAutoDismiss(1600L)
            return
        }

        // 3. Phone Call (English & Malayalam)
        val callRegexEn = Regex("""(?:call|dial)\s+(.+)""", RegexOption.IGNORE_CASE)
        val callRegexMl = Regex("""(.+?)(?:-നെ|യെ|നെ)?\s+വിളിക്കൂ""", RegexOption.IGNORE_CASE)

        var callTarget: String? = null
        val callMlMatch = callRegexMl.find(command)
        if (callMlMatch != null) {
            callTarget = callMlMatch.groupValues[1].trim()
        } else {
            val callEnMatch = callRegexEn.find(command)
            if (callEnMatch != null) {
                callTarget = callEnMatch.groupValues[1].trim()
            }
        }

        if (callTarget != null) {
            actionBadge.text = if (currentLanguage == "ml") "കോൾ ചെയ്യുന്നു..." else "Calling $callTarget..."
            ActionExecutorChannel.dialNumber(this, callTarget)
            speakFeedback(if (currentLanguage == "ml") "$callTarget-നെ വിളിക്കുന്നു" else "Calling $callTarget")
            scheduleAutoDismiss(1600L)
            return
        }

        // 4. Document / Passport Finder
        if (lower.contains("passport") || lower.contains("ticket") || lower.contains("പാസ്പോർട്ട്") || lower.contains("ടിക്കറ്റ്")) {
            actionBadge.text = if (currentLanguage == "ml") "രേഖകൾ തിരയുന്നു..." else "Searching documents..."
            speakFeedback(if (currentLanguage == "ml") "രേഖകൾ തുറക്കുന്നു" else "Searching your documents")
            expandToFullApp(command)
            return
        }

        // 5. General Fallback: Expand to Full App
        actionBadge.text = if (currentLanguage == "ml") "മാട്രിക്സ് ആരംഭിക്കുന്നു..." else "Opening Matrix..."
        speakFeedback(if (currentLanguage == "ml") "മാട്രിക്സ് സഹായിക്കുന്നു" else "Processing your request")
        expandToFullApp(command)
    }

    private fun speakFeedback(text: String) {
        if (!isTtsReady) return
        try {
            if (currentLanguage == "ml") {
                tts?.language = Locale("ml", "IN")
            } else {
                tts?.language = Locale.US
            }
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "matrix_overlay_tts")
        } catch (e: Exception) {
            Log.w(TAG, "TTS speak failed: ${e.message}")
        }
    }

    private fun startPulsingAnimation(view: View) {
        val anim = ObjectAnimator.ofFloat(view, "alpha", 0.3f, 1.0f).apply {
            duration = 800
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
        }
        anim.start()
    }

    private fun expandToFullApp(initialQuery: String? = null) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MatrixWakeWordService.EXTRA_WAKE_WORD_TRIGGERED, true)
            putExtra(MatrixWakeWordService.EXTRA_TRIGGER_TYPE, "overlay_expand")
            putExtra(MatrixWakeWordService.EXTRA_INITIAL_QUERY, initialQuery ?: transcriptText.text.toString().trim('"', ' '))
        }
        startActivity(intent)
        dismissOverlay()
    }

    private fun scheduleAutoDismiss(delayMs: Long) {
        mainHandler.postDelayed({ dismissOverlay() }, delayMs)
    }

    private fun dismissOverlay() {
        mainHandler.removeCallbacksAndMessages(null)
        try {
            speechRecognizer?.destroy()
            speechRecognizer = null
        } catch (_: Exception) {}

        try {
            tts?.stop()
            tts?.shutdown()
            tts = null
        } catch (_: Exception) {}

        overlayContainer?.let { container ->
            try {
                windowManager?.removeView(container)
            } catch (e: Exception) {
                Log.w(TAG, "Error removing overlay container: ${e.message}")
            }
        }
        overlayContainer = null

        // Resume hands-free background wake-word listening
        MatrixWakeWordService.serviceInstance?.resumeListening()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }

        stopSelf()
    }

    override fun onDestroy() {
        dismissOverlay()
        super.onDestroy()
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            resources.displayMetrics
        ).toInt()
    }

    private fun dpToPx(dp: Int): Int = dpToPx(dp.toFloat())

    companion object {
        private const val TAG = "MatrixOverlayService"
        private const val OVERLAY_CHANNEL_ID = "matrix_voice_overlay_channel"
        private const val OVERLAY_NOTIFICATION_ID = 2025
    }
}
