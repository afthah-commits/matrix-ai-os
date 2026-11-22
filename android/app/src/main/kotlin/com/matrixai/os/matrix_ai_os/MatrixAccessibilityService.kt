package com.matrixai.os.matrix_ai_os

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.ArrayDeque

/**
 * Native Android Accessibility Service for Matrix AI OS.
 *
 * Provides safe on-device UI context awareness (screen reading),
 * deep UI automation (finding nodes, clicking elements, injecting text, scrolling),
 * and global action assistance (back, home, notifications).
 */
class MatrixAccessibilityService : AccessibilityService() {

    var currentPackageName: String = ""
    var currentWindowTitle: String = ""

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "MatrixAccessibilityService connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            if (event.packageName != null) {
                currentPackageName = event.packageName.toString()
            }

            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                val title = event.text?.joinToString(" ") ?: ""
                if (title.isNotEmpty()) {
                    currentWindowTitle = title
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling accessibility event: ${e.message}")
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "MatrixAccessibilityService interrupted")
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        Log.i(TAG, "MatrixAccessibilityService unbound")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
        Log.i(TAG, "MatrixAccessibilityService destroyed")
    }

    companion object {
        private const val TAG = "MatrixAccessibility"
        var instance: MatrixAccessibilityService? = null

        fun isServiceRunning(): Boolean = instance != null

        /**
         * Dangerous payment and account modification keywords that are strictly blocked
         * from blind autonomous clicking without explicit user confirmation.
         */
        private val DANGEROUS_FINANCIAL_KEYWORDS = listOf(
            "pay now",
            "confirm payment",
            "make payment",
            "send money",
            "proceed to pay",
            "transfer funds",
            "transfer money",
            "delete account",
            "wipe data",
            "authorize payment"
        )

        /**
         * Reads visible text and content descriptions from the active window.
         * Traverses the AccessibilityNodeInfo tree safely using BFS up to [maxNodes].
         */
        fun getVisibleScreenText(maxNodes: Int = 120): String {
            val service = instance ?: return ""
            val root = service.rootInActiveWindow ?: return ""

            val stringBuilder = StringBuilder()
            val queue = ArrayDeque<AccessibilityNodeInfo>()
            queue.add(root)

            var nodesVisited = 0

            try {
                while (!queue.isEmpty() && nodesVisited < maxNodes) {
                    val current = queue.poll() ?: continue
                    nodesVisited++

                    val text = current.text
                    val desc = current.contentDescription

                    if (!text.isNullOrBlank()) {
                        val trimmed = text.toString().trim()
                        if (trimmed.length > 1) {
                            stringBuilder.append(trimmed).append("\n")
                        }
                    } else if (!desc.isNullOrBlank()) {
                        val trimmed = desc.toString().trim()
                        if (trimmed.length > 1) {
                            stringBuilder.append(trimmed).append("\n")
                        }
                    }

                    for (i in 0 until current.childCount) {
                        val child = current.getChild(i)
                        if (child != null) {
                            queue.add(child)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error reading screen node tree: ${e.message}")
            }

            return stringBuilder.toString().trim()
        }

        /**
         * Traverses active window and returns a structured list of interactive UI nodes.
         */
        fun getInteractiveUiTree(maxNodes: Int = 150): List<Map<String, Any>> {
            val service = instance ?: return emptyList()
            val root = service.rootInActiveWindow ?: return emptyList()

            val results = mutableListOf<Map<String, Any>>()
            val queue = ArrayDeque<AccessibilityNodeInfo>()
            queue.add(root)

            var nodesVisited = 0

            try {
                while (!queue.isEmpty() && nodesVisited < maxNodes) {
                    val current = queue.poll() ?: continue
                    nodesVisited++

                    val text = current.text?.toString() ?: ""
                    val desc = current.contentDescription?.toString() ?: ""
                    val viewId = current.viewIdResourceName ?: ""
                    val className = current.className?.toString() ?: ""
                    val isClickable = current.isClickable
                    val isEditable = current.isEditable
                    val isScrollable = current.isScrollable

                    // Keep node if it has text, description, or is interactive
                    if (text.isNotBlank() || desc.isNotBlank() || isClickable || isEditable || isScrollable) {
                        val rect = Rect()
                        current.getBoundsInScreen(rect)

                        results.add(mapOf(
                            "text" to text,
                            "contentDescription" to desc,
                            "viewId" to viewId,
                            "className" to className,
                            "isClickable" to isClickable,
                            "isEditable" to isEditable,
                            "isScrollable" to isScrollable,
                            "bounds" to mapOf(
                                "left" to rect.left,
                                "top" to rect.top,
                                "right" to rect.right,
                                "bottom" to rect.bottom
                            )
                        ))
                    }

                    for (i in 0 until current.childCount) {
                        val child = current.getChild(i)
                        if (child != null) {
                            queue.add(child)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error retrieving interactive UI tree: ${e.message}")
            }

            return results
        }

        /**
         * Finds a UI element matching [targetText], walks up to find a clickable container,
         * and performs an ACTION_CLICK gesture while enforcing safety guardrails.
         */
        fun clickNodeByText(targetText: String, maxNodes: Int = 150): Map<String, Any> {
            val service = instance ?: return mapOf(
                "success" to false,
                "error" to "Accessibility Service is not enabled"
            )
            val root = service.rootInActiveWindow ?: return mapOf(
                "success" to false,
                "error" to "No active window found on screen"
            )

            val cleanTarget = targetText.trim().lowercase()
            if (cleanTarget.isEmpty()) {
                return mapOf("success" to false, "error" to "Target text cannot be empty")
            }

            // Financial & Destructive Action Safety Filter
            if (DANGEROUS_FINANCIAL_KEYWORDS.any { cleanTarget.contains(it) }) {
                Log.w(TAG, "Blocked autonomous click on safety-critical keyword '$targetText'")
                return mapOf(
                    "success" to false,
                    "isFinancialBlocked" to true,
                    "message" to "Safety Block: Action '$targetText' matches critical financial/payment action. Human-in-the-Loop approval required."
                )
            }

            val queue = ArrayDeque<AccessibilityNodeInfo>()
            queue.add(root)

            var bestMatch: AccessibilityNodeInfo? = null
            var exactMatch: AccessibilityNodeInfo? = null
            var nodesVisited = 0

            try {
                while (!queue.isEmpty() && nodesVisited < maxNodes) {
                    val current = queue.poll() ?: continue
                    nodesVisited++

                    val text = current.text?.toString()?.trim()?.lowercase() ?: ""
                    val desc = current.contentDescription?.toString()?.trim()?.lowercase() ?: ""
                    val viewId = current.viewIdResourceName?.lowercase() ?: ""

                    // Priority 1: Exact match on text or contentDescription
                    if (text == cleanTarget || desc == cleanTarget) {
                        exactMatch = current
                        break
                    }

                    // Priority 2: Starts with or contains
                    if (bestMatch == null) {
                        if (text.startsWith(cleanTarget) || desc.startsWith(cleanTarget)) {
                            bestMatch = current
                        } else if (text.contains(cleanTarget) || desc.contains(cleanTarget) || viewId.contains(cleanTarget)) {
                            bestMatch = current
                        }
                    }

                    for (i in 0 until current.childCount) {
                        val child = current.getChild(i)
                        if (child != null) {
                            queue.add(child)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error traversing tree for click: ${e.message}")
            }

            val targetNode = exactMatch ?: bestMatch
            if (targetNode == null) {
                return mapOf(
                    "success" to false,
                    "message" to "No visible UI element matching '$targetText' was found."
                )
            }

            // Walk up hierarchy to find a clickable container if current node is not directly clickable
            var clickableNode: AccessibilityNodeInfo? = targetNode
            while (clickableNode != null && !clickableNode.isClickable) {
                clickableNode = clickableNode.parent
            }

            val nodeToClick = clickableNode ?: targetNode
            val clicked = nodeToClick.performAction(AccessibilityNodeInfo.ACTION_CLICK)

            val matchedLabel = targetNode.text?.toString() ?: targetNode.contentDescription?.toString() ?: targetText
            return if (clicked) {
                mapOf(
                    "success" to true,
                    "message" to "Clicked on '$matchedLabel'",
                    "matchedText" to matchedLabel
                )
            } else {
                // Try focus + click fallback
                nodeToClick.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                val secondTry = nodeToClick.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                mapOf(
                    "success" to secondTry,
                    "message" to if (secondTry) "Clicked on '$matchedLabel' (after focus)" else "Unable to perform click on '$matchedLabel'",
                    "matchedText" to matchedLabel
                )
            }
        }

        /**
         * Focuses an editable input field (or searches for one matching [targetHint])
         * and injects the specified text via ACTION_SET_TEXT.
         */
        fun inputTextIntoField(textToInject: String, targetHint: String? = null, maxNodes: Int = 150): Map<String, Any> {
            val service = instance ?: return mapOf(
                "success" to false,
                "error" to "Accessibility Service is not enabled"
            )
            val root = service.rootInActiveWindow ?: return mapOf(
                "success" to false,
                "error" to "No active window found on screen"
            )

            val cleanHint = targetHint?.trim()?.lowercase() ?: ""
            var editableNode: AccessibilityNodeInfo? = null

            // 1. If focused editable input exists, use it
            val currentFocus = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (currentFocus != null && currentFocus.isEditable) {
                editableNode = currentFocus
            }

            // 2. If no focused node or hint given, search tree for matching EditText / editable node
            if (editableNode == null || cleanHint.isNotEmpty()) {
                val queue = ArrayDeque<AccessibilityNodeInfo>()
                queue.add(root)
                var nodesVisited = 0

                try {
                    while (!queue.isEmpty() && nodesVisited < maxNodes) {
                        val current = queue.poll() ?: continue
                        nodesVisited++

                        if (current.isEditable) {
                            if (cleanHint.isNotEmpty()) {
                                val t = current.text?.toString()?.lowercase() ?: ""
                                val d = current.contentDescription?.toString()?.lowercase() ?: ""
                                val v = current.viewIdResourceName?.lowercase() ?: ""
                                if (t.contains(cleanHint) || d.contains(cleanHint) || v.contains(cleanHint)) {
                                    editableNode = current
                                    break
                                }
                            } else if (editableNode == null) {
                                editableNode = current
                            }
                        }

                        for (i in 0 until current.childCount) {
                            val child = current.getChild(i)
                            if (child != null) {
                                queue.add(child)
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error finding editable node: ${e.message}")
                }
            }

            if (editableNode == null) {
                return mapOf(
                    "success" to false,
                    "error" to "No editable text field found on screen"
                )
            }

            // Focus and inject text via bundle
            editableNode.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            val arguments = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, textToInject)
            }
            val success = editableNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)

            return mapOf(
                "success" to success,
                "message" to if (success) "Injected text: '$textToInject'" else "Failed to set text",
                "injectedText" to textToInject
            )
        }

        /**
         * Performs scroll action on the active window using node action or gesture swipe fallback.
         */
        fun scrollScreen(direction: String, maxNodes: Int = 100): Map<String, Any> {
            val service = instance ?: return mapOf(
                "success" to false,
                "error" to "Accessibility Service is not enabled"
            )
            val root = service.rootInActiveWindow ?: return mapOf(
                "success" to false,
                "error" to "No active window found on screen"
            )

            val dir = direction.trim().lowercase()

            // 1. Search for primary scrollable node in window
            val queue = ArrayDeque<AccessibilityNodeInfo>()
            queue.add(root)
            var scrollableNode: AccessibilityNodeInfo? = null
            var nodesVisited = 0

            try {
                while (!queue.isEmpty() && nodesVisited < maxNodes) {
                    val current = queue.poll() ?: continue
                    nodesVisited++

                    if (current.isScrollable) {
                        scrollableNode = current
                        break
                    }

                    for (i in 0 until current.childCount) {
                        val child = current.getChild(i)
                        if (child != null) {
                            queue.add(child)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error searching scrollable node: ${e.message}")
            }

            if (scrollableNode != null) {
                val scrolled = if (dir == "down" || dir == "right") {
                    scrollableNode.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                } else {
                    scrollableNode.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
                }

                if (scrolled) {
                    return mapOf(
                        "success" to true,
                        "direction" to dir,
                        "method" to "ACTION_SCROLL"
                    )
                }
            }

            // 2. Fallback: Dispatch Gesture Swipe on API 24+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val displayMetrics = service.resources.displayMetrics
                val width = displayMetrics.widthPixels.toFloat()
                val height = displayMetrics.heightPixels.toFloat()

                val path = Path()
                when (dir) {
                    "down" -> { // Swipe up to scroll down
                        path.moveTo(width / 2f, height * 0.75f)
                        path.lineTo(width / 2f, height * 0.25f)
                    }
                    "up" -> { // Swipe down to scroll up
                        path.moveTo(width / 2f, height * 0.25f)
                        path.lineTo(width / 2f, height * 0.75f)
                    }
                    "right" -> {
                        path.moveTo(width * 0.8f, height / 2f)
                        path.lineTo(width * 0.2f, height / 2f)
                    }
                    "left" -> {
                        path.moveTo(width * 0.2f, height / 2f)
                        path.lineTo(width * 0.8f, height / 2f)
                    }
                    else -> {
                        path.moveTo(width / 2f, height * 0.75f)
                        path.lineTo(width / 2f, height * 0.25f)
                    }
                }

                val stroke = GestureDescription.StrokeDescription(path, 0, 300)
                val gesture = GestureDescription.Builder().addStroke(stroke).build()
                val dispatched = service.dispatchGesture(gesture, null, null)

                return mapOf(
                    "success" to dispatched,
                    "direction" to dir,
                    "method" to "dispatchGesture"
                )
            }

            return mapOf(
                "success" to false,
                "error" to "Could not scroll window in direction '$direction'"
            )
        }

        /**
         * Safely executes standard Android Global Actions.
         */
        fun executeGlobalAction(action: Int): Boolean {
            return instance?.performGlobalAction(action) ?: false
        }

        /**
         * Automatically locates and clicks WhatsApp's "Send" button after opening
         * a prefilled chat. Retries over multiple attempts to wait for WhatsApp's activity animation.
         */
        fun autoSendWhatsAppMessage(
            retryAttempts: Int = 4,
            retryDelayMs: Long = 700L,
            callback: ((Boolean) -> Unit)? = null
        ) {
            val handler = Handler(Looper.getMainLooper())
            var currentAttempt = 0

            val clickRunnable = object : Runnable {
                override fun run() {
                    currentAttempt++
                    val service = instance
                    if (service == null) {
                        callback?.invoke(false)
                        return
                    }

                    val root = service.rootInActiveWindow
                    var clicked = false

                    if (root != null) {
                        // 1. Search by WhatsApp's official view ID (com.whatsapp:id/send)
                        val sendById = root.findAccessibilityNodeInfosByViewId("com.whatsapp:id/send")
                        if (!sendById.isNullOrEmpty()) {
                            for (node in sendById) {
                                var target: AccessibilityNodeInfo? = node
                                while (target != null && !target.isClickable) {
                                    target = target.parent
                                }
                                if (target != null && target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                                    clicked = true
                                    Log.i(TAG, "WhatsApp Send button clicked via view ID!")
                                    break
                                }
                            }
                        }

                        // 2. Fallback search by text or contentDescription "Send"
                        if (!clicked) {
                            val sendByText = root.findAccessibilityNodeInfosByText("Send")
                            if (!sendByText.isNullOrEmpty()) {
                                for (node in sendByText) {
                                    val desc = node.contentDescription?.toString() ?: ""
                                    val text = node.text?.toString() ?: ""
                                    if (desc.equals("Send", ignoreCase = true) || text.equals("Send", ignoreCase = true)) {
                                        var target: AccessibilityNodeInfo? = node
                                        while (target != null && !target.isClickable) {
                                            target = target.parent
                                        }
                                        if (target != null && target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                                            clicked = true
                                            Log.i(TAG, "WhatsApp Send button clicked via text/contentDescription!")
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if (clicked) {
                        callback?.invoke(true)
                    } else if (currentAttempt < retryAttempts) {
                        handler.postDelayed(this, retryDelayMs)
                    } else {
                        Log.w(TAG, "autoSendWhatsAppMessage: Send button not found after $retryAttempts attempts")
                        callback?.invoke(false)
                    }
                }
            }

            handler.postDelayed(clickRunnable, retryDelayMs)
        }
    }
}
