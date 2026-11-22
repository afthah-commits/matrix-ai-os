package com.matrixai.os.matrix_ai_os

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel handler for Phone Action Execution, Dynamic App Launcher, and Accessibility screen reading.
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
                "getInstalledApps" -> {
                    val apps = getInstalledApps()
                    result.success(apps)
                }

                "launchAppByName" -> {
                    val query = call.argument<String>("name") ?: call.argument<String>("query")
                    if (query.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "App name query cannot be empty", null)
                        return
                    }
                    val launchResult = launchAppByName(query)
                    result.success(launchResult)
                }

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

    /**
     * Query Android's PackageManager to retrieve all launchable applications dynamically.
     */
    private fun getInstalledApps(): List<Map<String, String>> {
        val packageManager = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfoList: List<ResolveInfo> = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }

        val appList = ArrayList<Map<String, String>>(resolveInfoList.size)
        for (resolveInfo in resolveInfoList) {
            val appName = resolveInfo.loadLabel(packageManager).toString().trim()
            val packageName = resolveInfo.activityInfo.packageName
            appList.add(mapOf("appName" to appName, "packageName" to packageName))
        }
        return appList
    }

    /**
     * Finds the best matching installed app (case-insensitive exact, prefix, contains, or alias)
     * and launches it immediately.
     */
    private fun launchAppByName(query: String): Map<String, Any> {
        val cleanQuery = query.trim().lowercase()
        if (cleanQuery.isEmpty()) {
            return mapOf("success" to false, "error" to "Query is empty")
        }

        val apps = getInstalledApps()

        // 1. Exact match by App Name
        var matched = apps.firstOrNull { it["appName"]?.lowercase() == cleanQuery }

        // 2. Starts with query (e.g. "Whats" -> "WhatsApp")
        if (matched == null) {
            matched = apps.firstOrNull { it["appName"]?.lowercase()?.startsWith(cleanQuery) == true }
        }

        // 3. Contains query (e.g. "tube" -> "YouTube")
        if (matched == null) {
            matched = apps.firstOrNull { it["appName"]?.lowercase()?.contains(cleanQuery) == true }
        }

        // 4. Exact or partial match on package name
        if (matched == null) {
            matched = apps.firstOrNull { it["packageName"]?.lowercase() == cleanQuery }
        }
        if (matched == null) {
            matched = apps.firstOrNull { it["packageName"]?.lowercase()?.contains(cleanQuery) == true }
        }

        // 5. Semantic keyword aliases for standard OEM/Android apps (Nothing OS, Pixel, Samsung, etc.)
        if (matched == null) {
            when (cleanQuery) {
                "camera" -> {
                    matched = apps.firstOrNull {
                        val name = it["appName"]?.lowercase() ?: ""
                        val pkg = it["packageName"]?.lowercase() ?: ""
                        name.contains("camera") || pkg.contains("camera")
                    }
                }
                "settings" -> {
                    matched = apps.firstOrNull {
                        val pkg = it["packageName"]?.lowercase() ?: ""
                        pkg == "com.android.settings" || it["appName"]?.lowercase() == "settings"
                    }
                }
                "gallery", "photos" -> {
                    matched = apps.firstOrNull {
                        val name = it["appName"]?.lowercase() ?: ""
                        val pkg = it["packageName"]?.lowercase() ?: ""
                        name.contains("gallery") || name.contains("photos") || pkg.contains("gallery") || pkg.contains("photos")
                    }
                }
                "browser", "internet", "chrome" -> {
                    matched = apps.firstOrNull {
                        val name = it["appName"]?.lowercase() ?: ""
                        val pkg = it["packageName"]?.lowercase() ?: ""
                        name.contains("chrome") || pkg.contains("chrome") || name.contains("browser")
                    }
                }
                "calculator" -> {
                    matched = apps.firstOrNull {
                        val name = it["appName"]?.lowercase() ?: ""
                        val pkg = it["packageName"]?.lowercase() ?: ""
                        name.contains("calculator") || pkg.contains("calculator")
                    }
                }
                "clock", "alarm" -> {
                    matched = apps.firstOrNull {
                        val name = it["appName"]?.lowercase() ?: ""
                        val pkg = it["packageName"]?.lowercase() ?: ""
                        name.contains("clock") || pkg.contains("deskclock")
                    }
                }
                "files", "file manager" -> {
                    matched = apps.firstOrNull {
                        val name = it["appName"]?.lowercase() ?: ""
                        val pkg = it["packageName"]?.lowercase() ?: ""
                        name.contains("files") || pkg.contains("documentsui") || pkg.contains("filemanager")
                    }
                }
            }
        }

        if (matched != null) {
            val pkg = matched["packageName"] ?: ""
            val name = matched["appName"] ?: pkg
            val launched = launchApp(pkg)
            return if (launched) {
                mapOf("success" to true, "appName" to name, "packageName" to pkg)
            } else {
                mapOf("success" to false, "error" to "Failed to start activity for $pkg", "appName" to name, "packageName" to pkg)
            }
        }

        return mapOf(
            "success" to false,
            "error" to "No installed app found matching '$query'",
            "query" to query
        )
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
