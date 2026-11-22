package com.matrixai.os.matrix_ai_os

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.ArrayDeque

/**
 * Native Android Accessibility Service for Matrix AI OS.
 *
 * Provides safe on-device UI context awareness (screen reading)
 * and global action assistance (back, home, notifications)
 * strictly when explicitly commanded by the user.
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
         * Safely executes standard Android Global Actions.
         */
        fun executeGlobalAction(action: Int): Boolean {
            return instance?.performGlobalAction(action) ?: false
        }
    }
}
