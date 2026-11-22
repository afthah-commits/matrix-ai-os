package com.matrixai.os.matrix_ai_os

import android.Manifest
import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.CallLog
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

/**
 * Native MethodChannel implementation for device telemetry and permission management.
 */
class DeviceStatsChannel(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDailyAppUsage" -> handleGetDailyAppUsage(result)
            "getRecentCallLogs" -> {
                val limit = call.argument<Int>("limit") ?: 50
                val sinceTimestamp = call.argument<Long>("sinceTimestamp")
                handleGetRecentCallLogs(limit, sinceTimestamp, result)
            }
            "checkPermissions" -> handleCheckPermissions(result)
            "openUsageAccessSettings" -> handleOpenUsageAccessSettings(result)
            "openNotificationListenerSettings" -> handleOpenNotificationListenerSettings(result)
            "openAppSettings" -> handleOpenAppSettings(result)
            "getBufferedNotifications" -> {
                val buffered = MatrixNotificationListener.drainBufferedNotifications()
                result.success(buffered)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleGetDailyAppUsage(result: MethodChannel.Result) {
        if (!hasUsageAccess()) {
            result.error("PERMISSION_DENIED", "PACKAGE_USAGE_STATS permission not granted by user.", null)
            return
        }

        try {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            if (usageStatsManager == null) {
                result.error("UNAVAILABLE", "UsageStatsManager is not available on this device.", null)
                return
            }

            // Midnight today
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val startOfDay = calendar.timeInMillis
            val now = System.currentTimeMillis()

            val statsList: List<UsageStats> = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startOfDay,
                now
            ) ?: emptyList()

            val packageManager = context.packageManager
            val appUsageList = mutableListOf<Map<String, Any>>()
            var totalScreenTimeMinutes = 0L

            for (usage in statsList) {
                val foregroundMs = usage.totalTimeInForeground
                if (foregroundMs <= 0) continue

                val minutes = foregroundMs / (1000 * 60)
                if (minutes <= 0) continue // Skip micro-second background transitions

                totalScreenTimeMinutes += minutes

                val appName = try {
                    val appInfo = packageManager.getApplicationInfo(usage.packageName, 0)
                    packageManager.getApplicationLabel(appInfo).toString()
                } catch (e: Exception) {
                    usage.packageName
                }

                val item = mapOf(
                    "packageName" to usage.packageName,
                    "appName" to appName,
                    "minutes" to minutes,
                    "lastTimeUsed" to usage.lastTimeUsed
                )
                appUsageList.add(item)
            }

            // Sort descending by usage minutes
            appUsageList.sortByDescending { (it["minutes"] as? Long) ?: 0L }

            val response = mapOf(
                "totalScreenTimeMinutes" to totalScreenTimeMinutes,
                "startTime" to startOfDay,
                "endTime" to now,
                "apps" to appUsageList
            )

            result.success(response)
        } catch (e: Exception) {
            result.error("USAGE_STATS_ERROR", "Failed querying daily app usage: ${e.message}", null)
        }
    }

    private fun handleGetRecentCallLogs(limit: Int, sinceTimestamp: Long?, result: MethodChannel.Result) {
        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CALL_LOG
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasPermission) {
            result.error("PERMISSION_DENIED", "READ_CALL_LOG permission not granted.", null)
            return
        }

        try {
            val callLogs = mutableListOf<Map<String, Any>>()
            val uri = CallLog.Calls.CONTENT_URI
            val projection = arrayOf(
                CallLog.Calls.NUMBER,
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.TYPE,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION
            )

            val selection = if (sinceTimestamp != null && sinceTimestamp > 0) {
                "${CallLog.Calls.DATE} > ?"
            } else null

            val selectionArgs = if (sinceTimestamp != null && sinceTimestamp > 0) {
                arrayOf(sinceTimestamp.toString())
            } else null

            val sortOrder = "${CallLog.Calls.DATE} DESC LIMIT $limit"

            context.contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val numberIdx = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = cursor.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = cursor.getColumnIndex(CallLog.Calls.DATE)
                val durationIdx = cursor.getColumnIndex(CallLog.Calls.DURATION)

                while (cursor.moveToNext()) {
                    val rawNumber = if (numberIdx != -1) cursor.getString(numberIdx) ?: "" else ""
                    val cachedName = if (nameIdx != -1) cursor.getString(nameIdx) else null
                    val rawType = if (typeIdx != -1) cursor.getInt(typeIdx) else -1
                    val date = if (dateIdx != -1) cursor.getLong(dateIdx) else 0L
                    val duration = if (durationIdx != -1) cursor.getLong(durationIdx) else 0L

                    val typeStr = when (rawType) {
                        CallLog.Calls.INCOMING_TYPE -> "INCOMING"
                        CallLog.Calls.OUTGOING_TYPE -> "OUTGOING"
                        CallLog.Calls.MISSED_TYPE -> "MISSED"
                        CallLog.Calls.REJECTED_TYPE -> "REJECTED"
                        else -> "UNKNOWN"
                    }

                    // Mask full phone number for privacy display while preserving identity
                    val contactName = if (!cachedName.isNullOrBlank()) cachedName else maskPhoneNumber(rawNumber)

                    callLogs.add(
                        mapOf(
                            "number" to rawNumber,
                            "contactName" to contactName,
                            "type" to typeStr,
                            "timestamp" to date,
                            "durationSeconds" to duration
                        )
                    )
                }
            }

            result.success(callLogs)
        } catch (e: Exception) {
            result.error("CALL_LOG_ERROR", "Failed querying CallLogs: ${e.message}", null)
        }
    }

    private fun handleCheckPermissions(result: MethodChannel.Result) {
        val usageGranted = hasUsageAccess()
        val notifGranted = hasNotificationListenerAccess()
        val callLogGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CALL_LOG
        ) == PackageManager.PERMISSION_GRANTED

        val map = mapOf(
            "usageStatsGranted" to usageGranted,
            "notificationListenerGranted" to notifGranted,
            "callLogGranted" to callLogGranted
        )
        result.success(map)
    }

    private fun handleOpenUsageAccessSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("INTENT_ERROR", "Could not open Usage Access settings: ${e.message}", null)
        }
    }

    private fun handleOpenNotificationListenerSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("INTENT_ERROR", "Could not open Notification Listener settings: ${e.message}", null)
        }
    }

    private fun handleOpenAppSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", context.packageName, null)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("INTENT_ERROR", "Could not open App Details settings: ${e.message}", null)
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun hasNotificationListenerAccess(): Boolean {
        val packageNames = NotificationManagerCompat.getEnabledListenerPackages(context)
        return packageNames.contains(context.packageName)
    }

    private fun maskPhoneNumber(number: String): String {
        if (number.length <= 4) return number
        val visiblePart = number.takeLast(4)
        return "****$visiblePart"
    }

    fun cleanUp() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL_NAME = "com.matrixai.os/device_stats"
    }
}
