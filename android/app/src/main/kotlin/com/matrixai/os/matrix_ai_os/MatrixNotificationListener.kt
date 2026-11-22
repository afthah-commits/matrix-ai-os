package com.matrixai.os.matrix_ai_os

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.regex.Pattern

/**
 * Passive Notification Listener Service for Matrix AI OS.
 *
 * Intercepts banking alerts, transaction receipts, UPI notifications, and critical alerts.
 * Extracts structured metadata on-device and streams it to Flutter or buffers it safely.
 * Strict zero-log policy for sensitive personal data in release logs.
 */
class MatrixNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        // Ignore ongoing or system background progress notifications
        val isOngoing = (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0
        if (isOngoing) return

        val packageName = sbn.packageName ?: ""
        // Do not process own notifications
        if (packageName == applicationContext.packageName) return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val fullContent = if (bigText.isNotBlank()) "$title: $bigText" else "$title: $text"

        if (fullContent.isBlank()) return

        // Categorize notification
        val isFinancial = isFinancialAlert(packageName, fullContent)
        val isMessage = isMessagingAlert(packageName)

        if (!isFinancial && !isMessage) {
            // Drop unrelated background noise (marketing, system stats, games)
            return
        }

        val eventData = HashMap<String, Any>()
        eventData["packageName"] = packageName
        eventData["title"] = title
        eventData["text"] = if (bigText.isNotBlank()) bigText else text
        eventData["timestamp"] = sbn.postTime

        if (isFinancial) {
            eventData["category"] = "transaction"
            val parsedTx = extractTransactionDetails(fullContent)
            eventData["amount"] = parsedTx.amount ?: 0.0
            eventData["merchant"] = parsedTx.merchant ?: title
            eventData["txType"] = parsedTx.type
            eventData["accountRef"] = parsedTx.accountRef ?: ""
        } else {
            eventData["category"] = "notification"
            eventData["sender"] = title
        }

        // Deliver to active Flutter engine or buffer for later retrieval
        val dispatched = listenerCallback?.invoke(eventData) ?: false
        if (!dispatched) {
            bufferNotification(eventData)
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnected = true
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isConnected = false
    }

    companion object {
        var isConnected: Boolean = false
            private set

        private const val MAX_BUFFER_SIZE = 100
        private val notificationBuffer = ConcurrentLinkedQueue<Map<String, Any>>()

        var listenerCallback: ((Map<String, Any>) -> Boolean)? = null

        private fun bufferNotification(data: Map<String, Any>) {
            while (notificationBuffer.size >= MAX_BUFFER_SIZE) {
                notificationBuffer.poll()
            }
            notificationBuffer.offer(data)
        }

        /**
         * Drains buffered notifications and returns them to Flutter.
         */
        fun drainBufferedNotifications(): List<Map<String, Any>> {
            val list = mutableListOf<Map<String, Any>>()
            while (true) {
                val item = notificationBuffer.poll() ?: break
                list.add(item)
            }
            return list
        }

        private val FINANCIAL_KEYWORDS = listOf(
            "debited", "credited", "spent", "transferred", "payment of", "paid to",
            "received from", "upi", "vpa", "inr", "rs.", "rs ", "₹", "bank", "axis",
            "hdfc", "sbi", "icici", "kotak", "pnb", "bob", "paytm", "phonepe", "gpay",
            "cred", "slice", "jupiter", "fi money", "amazon pay"
        )

        private val MESSAGING_PACKAGES = setOf(
            "com.whatsapp",
            "org.telegram.messenger",
            "org.thoughtcrime.securesms", // Signal
            "com.google.android.apps.messaging", // Google Messages
            "com.android.mms"
        )

        fun isFinancialAlert(packageName: String, text: String): Boolean {
            val lower = text.lowercase()
            val lowerPkg = packageName.lowercase()

            val hasBankKeyword = FINANCIAL_KEYWORDS.any { lower.contains(it) || lowerPkg.contains(it) }
            val hasCurrency = lower.contains("rs") || lower.contains("₹") || lower.contains("inr") || lower.contains("$")
            val hasAction = lower.contains("debited") || lower.contains("credited") || lower.contains("spent") ||
                    lower.contains("paid") || lower.contains("sent") || lower.contains("received") || lower.contains("transfer")

            return (hasBankKeyword && (hasCurrency || hasAction))
        }

        fun isMessagingAlert(packageName: String): Boolean {
            return MESSAGING_PACKAGES.contains(packageName)
        }

        data class ParsedTransaction(
            val amount: Double?,
            val merchant: String?,
            val type: String, // "debit", "credit", or "unknown"
            val accountRef: String?
        )

        fun extractTransactionDetails(text: String): ParsedTransaction {
            val lower = text.lowercase()

            // 1. Detect Type
            val type = when {
                lower.contains("debited") || lower.contains("spent") || lower.contains("paid") || lower.contains("sent") -> "debit"
                lower.contains("credited") || lower.contains("received") || lower.contains("refund") -> "credit"
                else -> "unknown"
            }

            // 2. Extract Amount
            // Matches: Rs. 1,450.50 | INR 250 | ₹500.00 | $45.00 | 1,200.00 debited
            var amount: Double? = null
            val amountPattern = Pattern.compile(
                "(?:(?:rs\\.?|inr|₹|\\$)\\s*([0-9,]+(?:\\.[0-9]{1,2})?))|(?:([0-9,]+(?:\\.[0-9]{1,2})?)\\s*(?:debited|credited|spent|paid))",
                Pattern.CASE_INSENSITIVE
            )
            val matcher = amountPattern.matcher(text)
            if (matcher.find()) {
                val rawVal = matcher.group(1) ?: matcher.group(2)
                if (rawVal != null) {
                    val cleanVal = rawVal.replace(",", "").trim()
                    amount = cleanVal.toDoubleOrNull()
                }
            }

            // 3. Extract Merchant / Recipient
            // Matches "to VPA abc@upi", "at Amazon", "to Rahul", "info: SWIGGY"
            var merchant: String? = null
            val merchantPattern = Pattern.compile(
                "(?:to|at|vpa|info|towards)\\s+([a-zA-Z0-9_.-@]+(?:\\s+[a-zA-Z0-9_.-]+)?)",
                Pattern.CASE_INSENSITIVE
            )
            val mMatcher = merchantPattern.matcher(text)
            if (mMatcher.find()) {
                merchant = mMatcher.group(1)?.trim()
            }

            // 4. Extract Account Reference (e.g. A/c **1234 or XX1234)
            var accRef: String? = null
            val accPattern = Pattern.compile("(?:a/c|account|ac|card)\\s*(?:no\\.?)?\\s*(?:ending)?\\s*([xX*]*[0-9]{3,4})", Pattern.CASE_INSENSITIVE)
            val aMatcher = accPattern.matcher(text)
            if (aMatcher.find()) {
                accRef = aMatcher.group(1)
            }

            return ParsedTransaction(
                amount = amount,
                merchant = merchant,
                type = type,
                accountRef = accRef
            )
        }
    }
}
