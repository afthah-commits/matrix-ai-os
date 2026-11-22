package com.matrixai.os.matrix_ai_os

import android.accessibilityservice.AccessibilityService
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

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
                    val autoSend = call.argument<Boolean>("autoSend") ?: true
                    val success = composeWhatsAppMessage(context, phoneNumber, message, autoSend)
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

                "clickUiElement" -> {
                    val targetText = call.argument<String>("targetText") ?: call.argument<String>("text")
                    if (targetText.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "targetText cannot be empty", null)
                        return
                    }
                    val clickResult = MatrixAccessibilityService.clickNodeByText(targetText)
                    result.success(clickResult)
                }

                "typeUiText" -> {
                    val textToInject = call.argument<String>("text")
                    if (textToInject == null) {
                        result.error("INVALID_ARGS", "text cannot be null", null)
                        return
                    }
                    val targetHint = call.argument<String>("targetHint")
                    val typeResult = MatrixAccessibilityService.inputTextIntoField(textToInject, targetHint)
                    result.success(typeResult)
                }

                "scrollUi" -> {
                    val direction = call.argument<String>("direction") ?: "down"
                    val scrollResult = MatrixAccessibilityService.scrollScreen(direction)
                    result.success(scrollResult)
                }

                "inspectUiTree" -> {
                    val tree = MatrixAccessibilityService.getInteractiveUiTree()
                    result.success(tree)
                }

                "searchDeviceFiles" -> {
                    val query = call.argument<String>("query") ?: ""
                    val files = searchDeviceFiles(query)
                    result.success(files)
                }

                "renderPdfPageForOcr" -> {
                    val contentUri = call.argument<String>("contentUri") ?: call.argument<String>("uri")
                    if (contentUri.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "contentUri cannot be empty", null)
                        return
                    }
                    val pageIndex = call.argument<Int>("pageIndex") ?: 0
                    val renderResult = renderPdfPageForOcr(contentUri, pageIndex)
                    result.success(renderResult)
                }

                "openFileUri" -> {
                    val uri = call.argument<String>("uri") ?: call.argument<String>("contentUri")
                    if (uri.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "uri cannot be empty", null)
                        return
                    }
                    val mime = call.argument<String>("mimeType")
                    val openResult = openFileUri(uri, mime)
                    result.success(openResult)
                }

                "checkAllFilesAccess" -> {
                    val hasAccess = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Environment.isExternalStorageManager()
                    } else {
                        true
                    }
                    result.success(hasAccess)
                }

                "requestAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val uri = Uri.parse("package:${context.packageName}")
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, uri).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            val fallbackIntent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(fallbackIntent)
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
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

    private fun launchAppByName(query: String): Map<String, Any> = launchAppByName(context, query)
    private fun launchApp(packageName: String): Boolean = launchApp(context, packageName)
    private fun dialNumber(phoneNumber: String): Boolean = dialNumber(context, phoneNumber)
    private fun composeWhatsAppMessage(phoneNumber: String, message: String, autoSend: Boolean = true): Boolean =
        composeWhatsAppMessage(context, phoneNumber, message, autoSend)

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

    /**
     * Queries Android's MediaStore and direct storage directories (Downloads, Documents, Pictures, DCIM)
     * for images (screenshots, camera photos) and files (PDFs) matching the requested keyword, or recent documents.
     */
    fun searchDeviceFiles(rawQuery: String): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val cleanQuery = rawQuery.trim().lowercase()

        // Extract potential search keywords
        val keywords: List<String> = when {
            cleanQuery.contains("passport") -> listOf("passport", "pass_port")
            cleanQuery.contains("password") -> listOf("password", "passcode", "secret", "credential")
            cleanQuery.contains("ticket") || cleanQuery.contains("boarding") -> listOf("ticket", "boarding", "flight", "booking", "train", "pnr")
            cleanQuery.contains("invoice") || cleanQuery.contains("bill") || cleanQuery.contains("receipt") -> listOf("invoice", "bill", "receipt", "tax", "order")
            cleanQuery.contains("statement") -> listOf("statement", "bank", "account")
            cleanQuery.contains("id") || cleanQuery.contains("aadhaar") || cleanQuery.contains("pan") -> listOf("id", "aadhaar", "pan", "card", "license")
            cleanQuery.contains("document") || cleanQuery.contains("doc") || cleanQuery.contains("pdf") || cleanQuery.contains("file") -> listOf("passport", "ticket", "invoice", "receipt", "statement", "bill", "doc")
            cleanQuery.isNotEmpty() -> cleanQuery.split(" ").filter { it.length > 2 }
            else -> emptyList()
        }

        val matchedResults = mutableListOf<Map<String, Any>>()
        val recentResults = mutableListOf<Map<String, Any>>()
        val seenPaths = mutableSetOf<String>()

        try {
            // 1. Query Images (MediaStore Images)
            val imageProjection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.MIME_TYPE,
                MediaStore.Images.Media.DATE_MODIFIED,
                MediaStore.Images.Media.SIZE,
                MediaStore.MediaColumns.DATA
            )

            val imageCursor = context.contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                imageProjection,
                null,
                null,
                "${MediaStore.Images.Media.DATE_MODIFIED} DESC"
            )

            imageCursor?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
                val pathCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)

                var count = 0
                while (cursor.moveToNext() && count < 30) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol) ?: ""
                    val mime = cursor.getString(mimeCol) ?: "image/jpeg"
                    val date = cursor.getLong(dateCol) * 1000L
                    val size = cursor.getLong(sizeCol)
                    val path = if (pathCol != -1) cursor.getString(pathCol) ?: "" else ""

                    val contentUri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
                    val item = mapOf(
                        "uri" to contentUri.toString(),
                        "displayName" to name,
                        "mimeType" to mime,
                        "dateModified" to date,
                        "sizeBytes" to size,
                        "filePath" to path
                    )

                    if (path.isNotEmpty()) seenPaths.add(path)

                    val nameLower = name.lowercase()
                    val matches = if (keywords.isEmpty()) true else keywords.any { nameLower.contains(it) }

                    if (matches) {
                        matchedResults.add(item)
                    } else if (recentResults.size < 15) {
                        recentResults.add(item)
                    }
                    count++
                }
            }

            // 2. Query Files (PDFs in Downloads/Documents via MediaStore Files)
            val fileProjection = arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.MIME_TYPE,
                MediaStore.Files.FileColumns.DATE_MODIFIED,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.MediaColumns.DATA
            )

            val fileUri = MediaStore.Files.getContentUri("external")
            val selection = "${MediaStore.Files.FileColumns.MIME_TYPE} = ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE '%.pdf'"
            val selectionArgs = arrayOf("application/pdf")

            val fileCursor = context.contentResolver.query(
                fileUri,
                fileProjection,
                selection,
                selectionArgs,
                "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
            )

            fileCursor?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                val pathCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)

                var count = 0
                while (cursor.moveToNext() && count < 20) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol) ?: ""
                    val mime = cursor.getString(mimeCol) ?: "application/pdf"
                    val date = cursor.getLong(dateCol) * 1000L
                    val size = cursor.getLong(sizeCol)
                    val path = if (pathCol != -1) cursor.getString(pathCol) ?: "" else ""

                    val contentUri = ContentUris.withAppendedId(fileUri, id)
                    val item = mapOf(
                        "uri" to contentUri.toString(),
                        "displayName" to name,
                        "mimeType" to mime,
                        "dateModified" to date,
                        "sizeBytes" to size,
                        "filePath" to path
                    )

                    if (path.isNotEmpty()) seenPaths.add(path)

                    val nameLower = name.lowercase()
                    val matches = if (keywords.isEmpty()) true else keywords.any { nameLower.contains(it) }

                    if (matches) {
                        matchedResults.add(item)
                    } else if (recentResults.size < 20) {
                        recentResults.add(item)
                    }
                    count++
                }
            }

            // 3. Direct File System Scan if All-Files Access is granted
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()) {
                val searchDirs = listOf(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM)
                )

                for (dir in searchDirs) {
                    if (dir != null && dir.exists() && dir.isDirectory) {
                        dir.listFiles()?.take(50)?.forEach { file ->
                            if (file.isFile && !seenPaths.contains(file.absolutePath)) {
                                val name = file.name
                                val nameLower = name.lowercase()
                                val isDocOrImage = nameLower.endsWith(".pdf") ||
                                        nameLower.endsWith(".jpg") ||
                                        nameLower.endsWith(".jpeg") ||
                                        nameLower.endsWith(".png")

                                if (isDocOrImage) {
                                    val mime = if (nameLower.endsWith(".pdf")) "application/pdf" else "image/jpeg"
                                    val item = mapOf(
                                        "uri" to Uri.fromFile(file).toString(),
                                        "displayName" to name,
                                        "mimeType" to mime,
                                        "dateModified" to file.lastModified(),
                                        "sizeBytes" to file.length(),
                                        "filePath" to file.absolutePath
                                    )
                                    seenPaths.add(file.absolutePath)

                                    val matches = if (keywords.isEmpty()) true else keywords.any { nameLower.contains(it) }
                                    if (matches) {
                                        matchedResults.add(item)
                                    } else if (recentResults.size < 25) {
                                        recentResults.add(item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying device files: ${e.message}")
        }

        // Return keyword matches first, followed by recent unindexed images/PDFs for ML Kit OCR
        results.addAll(matchedResults)
        for (item in recentResults) {
            if (!results.any { it["filePath"] == item["filePath"] || it["uri"] == item["uri"] }) {
                results.add(item)
            }
        }
        return results.take(25)
    }

    /**
     * Renders page 0 (or [pageIndex]) of a PDF into a temporary JPEG bitmap file using
     * native Android PdfRenderer, enabling on-device ML Kit OCR without heavy third-party libraries.
     */
    fun renderPdfPageForOcr(contentUriStr: String, pageIndex: Int = 0): Map<String, Any> {
        try {
            val uri = Uri.parse(contentUriStr)
            val pfd: ParcelFileDescriptor = if (contentUriStr.startsWith("content://")) {
                context.contentResolver.openFileDescriptor(uri, "r")
                    ?: return mapOf("success" to false, "error" to "Could not open ContentResolver file descriptor")
            } else {
                val file = File(contentUriStr)
                if (!file.exists()) {
                    return mapOf("success" to false, "error" to "File does not exist: $contentUriStr")
                }
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            }

            pfd.use { descriptor ->
                val pdfRenderer = PdfRenderer(descriptor)
                pdfRenderer.use { renderer ->
                    val pageCount = renderer.pageCount
                    if (pageCount == 0) {
                        return mapOf("success" to false, "error" to "PDF has 0 pages")
                    }
                    val targetPage = if (pageIndex in 0 until pageCount) pageIndex else 0
                    val page = renderer.openPage(targetPage)
                    page.use { pdfPage ->
                        val scale = Math.min(2.0f, 2048f / Math.max(pdfPage.width, pdfPage.height).toFloat())
                        val width = (pdfPage.width * scale).toInt()
                        val height = (pdfPage.height * scale).toInt()
                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

                        val canvas = Canvas(bitmap)
                        canvas.drawColor(Color.WHITE)
                        pdfPage.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                        val cacheDir = File(context.cacheDir, "pdf_renders").apply { if (!exists()) mkdirs() }
                        val tempFile = File(cacheDir, "pdf_page_${System.currentTimeMillis()}_$targetPage.jpg")
                        FileOutputStream(tempFile).use { out ->
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                        }
                        bitmap.recycle()

                        return mapOf(
                            "success" to true,
                            "imagePath" to tempFile.absolutePath,
                            "pageCount" to pageCount,
                            "pageIndex" to targetPage
                        )
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error rendering PDF page: ${e.message}")
            return mapOf("success" to false, "error" to (e.message ?: "PDF rendering error"))
        }
    }

    /**
     * Opens a document or image URI directly in the phone's native viewer (Gallery, Adobe, Drive, etc.).
     */
    fun openFileUri(uriStr: String, mimeType: String?): Map<String, Any> {
        try {
            val uri = Uri.parse(uriStr)
            val resolvedMime = if (!mimeType.isNullOrBlank() && mimeType != "*/*") {
                mimeType
            } else {
                val ext = MimeTypeMap.getFileExtensionFromUrl(uriStr)
                if (ext.isNotEmpty()) {
                    MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.lowercase()) ?: "application/*"
                } else if (uriStr.contains(".pdf")) {
                    "application/pdf"
                } else {
                    "image/*"
                }
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, resolvedMime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            return mapOf("success" to true, "message" to "Opened file ($resolvedMime)")
        } catch (e: Exception) {
            Log.e(TAG, "Error opening file URI '$uriStr': ${e.message}")
            return mapOf("success" to false, "error" to (e.message ?: "Failed to open file"))
        }
    }

    fun cleanUp() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL_NAME = "com.matrixai.os/action_executor"
        private const val TAG = "ActionExecutorChannel"

        fun resolveContactNumberByName(context: Context, name: String): String? {
            val cleanName = name.trim().lowercase()
            val candidates = mutableListOf(cleanName)
            for (sfx in listOf("ിനെ", "ിന്", "യ്ക്ക്", "ക്ക്", "നെ", "യെ", "റെ", "ന്")) {
                if (cleanName.endsWith(sfx) && cleanName.length > sfx.length + 1) {
                    val root = cleanName.removeSuffix(sfx)
                    candidates.add(root)
                    if (root.endsWith("ല")) candidates.add(root.dropLast(1) + "ൽ")
                    if (root.endsWith("ര")) candidates.add(root.dropLast(1) + "ർ")
                    if (root.endsWith("ന")) candidates.add(root.dropLast(1) + "ൻ")
                }
            }

            try {
                for (cand in candidates) {
                    val cursor = context.contentResolver.query(
                        ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                        arrayOf(
                            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                            ContactsContract.CommonDataKinds.Phone.NUMBER
                        ),
                        "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                        arrayOf("%$cand%"),
                        null
                    )
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val numIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                            if (numIdx >= 0) {
                                val rawNumber = it.getString(numIdx)
                                return rawNumber.replace(Regex("[^0-9+]"), "")
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "resolveContactNumberByName error: ${e.message}")
            }
            return null
        }

        fun dialNumber(context: Context, phoneNumber: String): Boolean {
            var target = phoneNumber.trim()
            if (target.any { it.isLetter() }) {
                val resolved = resolveContactNumberByName(context, target)
                if (resolved != null) {
                    target = resolved
                }
            }
            val intent = Intent(Intent.ACTION_DIAL).apply {
                data = Uri.parse("tel:${Uri.encode(target)}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            return true
        }

        fun composeWhatsAppMessage(
            context: Context,
            phoneNumber: String,
            message: String,
            autoSend: Boolean = true
        ): Boolean {
            var target = phoneNumber.trim()
            if (target.any { it.isLetter() }) {
                val resolved = resolveContactNumberByName(context, target)
                if (resolved != null) {
                    target = resolved
                }
            }
            val digitsOnly = target.replace(Regex("[^0-9]"), "")
            val uri = if (digitsOnly.isNotEmpty()) {
                Uri.parse("https://wa.me/$digitsOnly?text=${Uri.encode(message)}")
            } else {
                Uri.parse("https://wa.me/?text=${Uri.encode(message)}")
            }

            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                setPackage("com.whatsapp")
            }
            try {
                context.startActivity(intent)
            } catch (_: Exception) {
                val fallback = Intent(Intent.ACTION_VIEW, uri).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(fallback)
            }

            if (autoSend && MatrixAccessibilityService.isServiceRunning()) {
                MatrixAccessibilityService.autoSendWhatsAppMessage(retryAttempts = 4, retryDelayMs = 700L)
            }
            return true
        }

        fun launchApp(context: Context, packageName: String): Boolean {
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

        fun getInstalledApps(context: Context): List<Map<String, String>> {
            val packageManager = context.packageManager
            val intent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolveInfoList: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
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

        fun launchAppByName(context: Context, query: String): Map<String, Any> {
            val cleanQuery = query.trim().lowercase()
            if (cleanQuery.isEmpty()) {
                return mapOf("success" to false, "error" to "Query is empty")
            }

            val apps = getInstalledApps(context)

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

            // 5. Semantic keyword & Malayalam aliases for standard OEM/Android apps
            if (matched == null) {
                when (cleanQuery) {
                    "camera", "ക്യാമറ" -> {
                        matched = apps.firstOrNull {
                            val name = it["appName"]?.lowercase() ?: ""
                            val pkg = it["packageName"]?.lowercase() ?: ""
                            name.contains("camera") || pkg.contains("camera")
                        }
                    }
                    "settings", "സെറ്റിംഗ്സ്" -> {
                        matched = apps.firstOrNull {
                            val pkg = it["packageName"]?.lowercase() ?: ""
                            pkg == "com.android.settings" || it["appName"]?.lowercase() == "settings"
                        }
                    }
                    "gallery", "photos", "ഗാലറി" -> {
                        matched = apps.firstOrNull {
                            val name = it["appName"]?.lowercase() ?: ""
                            val pkg = it["packageName"]?.lowercase() ?: ""
                            name.contains("gallery") || name.contains("photos") || pkg.contains("gallery") || pkg.contains("photos")
                        }
                    }
                    "browser", "internet", "chrome", "ക്രോം" -> {
                        matched = apps.firstOrNull {
                            val name = it["appName"]?.lowercase() ?: ""
                            val pkg = it["packageName"]?.lowercase() ?: ""
                            name.contains("chrome") || pkg.contains("chrome") || name.contains("browser")
                        }
                    }
                    "youtube", "യൂട്യൂബ്" -> {
                        matched = apps.firstOrNull {
                            val name = it["appName"]?.lowercase() ?: ""
                            val pkg = it["packageName"]?.lowercase() ?: ""
                            name.contains("youtube") || pkg.contains("youtube")
                        }
                    }
                    "whatsapp", "വാട്സാപ്പ്", "വാട്സാപ്" -> {
                        matched = apps.firstOrNull {
                            val pkg = it["packageName"]?.lowercase() ?: ""
                            pkg.contains("whatsapp")
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
                val launched = launchApp(context, pkg)
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
    }
}
