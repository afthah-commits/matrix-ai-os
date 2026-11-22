package com.matrixai.os.matrix_ai_os

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel handler for Phone Action Execution and Accessibility screen reading.
 */
class ActionExecutorChannel(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Package name cannot be empty", null)
                        return
                    }
                    val success = launchApp(packageName)
                    result.success(success)
                }

                "dialNumber" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    if (phoneNumber.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Phone number cannot be empty", null)
                        return
                    }
                    val success = dialNumber(phoneNumber)
                    result.success(success)
                }

                "composeWhatsAppMessage" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val success = composeWhatsAppMessage(phoneNumber, message)
                    result.success(success)
                }

                "getCurrentScreenContext" -> {
                    val screenData = getCurrentScreenContext()
                    result.success(screenData)
                }

                "checkAccessibilityEnabled" -> {
                    val isEnabled = MatrixAccessibilityService.isServiceRunning()
                    result.success(isEnabled)
                }

                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(intent)
                    result.success(true)
                }

                "performGlobalAction" -> {
                    val actionName = call.argument<String>("action") ?: "back"
                    val success = performGlobalAction(actionName)
                    result.success(success)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in ActionExecutorChannel call '${call.method}': ${e.message}")
            result.error("EXECUTION_ERROR", e.message, null)
        }
    }

    private fun launchApp(packageName: String): Boolean {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
        return if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launchIntent)
            true
        } else {
            Log.w(TAG, "App with package '$packageName' not found on device")
            false
        }
    }

    private fun dialNumber(phoneNumber: String): Boolean {
        val intent = Intent(Intent.ACTION_DIAL).apply {
            data = Uri.parse("tel:${Uri.encode(phoneNumber.trim())}")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(intent)
        return true
    }

    private fun composeWhatsAppMessage(phoneNumber: String, message: String): Boolean {
        // Strip non-digits except leading +
        val digitsOnly = phoneNumber.replace(Regex("[^0-9]"), "")
        val uri = if (digitsOnly.isNotEmpty()) {
            Uri.parse("https://wa.me/$digitsOnly?text=${Uri.encode(message)}")
        } else {
            Uri.parse("https://wa.me/?text=${Uri.encode(message)}")
        }

        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(intent)
        return true
    }

    private fun getCurrentScreenContext(): Map<String, Any> {
        val serviceRunning = MatrixAccessibilityService.isServiceRunning()
        val pkg = MatrixAccessibilityService.instance?.currentPackageName ?: ""
        val title = MatrixAccessibilityService.instance?.currentWindowTitle ?: ""
        val screenText = if (serviceRunning) {
            MatrixAccessibilityService.getVisibleScreenText()
        } else {
            ""
        }

        return mapOf(
            "packageName" to pkg,
            "windowTitle" to title,
            "screenText" to screenText,
            "isAccessibilityEnabled" to serviceRunning
        )
    }

    private fun performGlobalAction(actionName: String): Boolean {
        val actionId = when (actionName.lowercase()) {
            "back" -> AccessibilityService.GLOBAL_ACTION_BACK
            "home" -> AccessibilityService.GLOBAL_ACTION_HOME
            "notifications" -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
            else -> AccessibilityService.GLOBAL_ACTION_BACK
        }
        return MatrixAccessibilityService.executeGlobalAction(actionId)
    }

    fun cleanUp() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL_NAME = "com.matrixai.os/action_executor"
        private const val TAG = "ActionExecutorChannel"
    }
}
