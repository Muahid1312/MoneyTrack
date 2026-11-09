package com.moneytrack.moneytrack

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class DocumentBridge(private val activity: FlutterFragmentActivity) {
    private var pending: MethodChannel.Result? = null
    private var camera: File? = null
    private var limit = 10485760
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "moneytrack/documents").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    if (pending != null) { result.error("BUSY", "A document picker is already open", null); return@setMethodCallHandler }
                    val kind = call.argument<String>("kind") ?: "document"
                    limit = if (kind == "backup") 33554432 else 10485760
                    try {
                        pending = result
                        if (kind == "camera") {
                            val folder = File(activity.cacheDir, "camera").apply { mkdirs() }
                            folder.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86400000 }?.forEach { it.delete() }
                            camera = File(folder, UUID.randomUUID().toString() + ".jpg")
                            val uri = FileProvider.getUriForFile(activity, activity.packageName + ".privatefiles", camera!!)
                            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).putExtra(MediaStore.EXTRA_OUTPUT, uri)
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            intent.clipData = ClipData.newRawUri("Receipt", uri)
                            activity.startActivityForResult(intent, 7404)
                        } else {
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                            intent.type = if (kind == "gallery") "image/*" else if (kind == "document") "application/pdf" else "*/*"
                            if (kind == "gallery") intent.putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png"))
                            activity.startActivityForResult(intent, 7405)
                        }
                    } catch (_: Exception) { pending = null; camera?.delete(); camera = null; result.error("PICK", "No suitable document or camera provider is available", null) }
                }
                "open" -> {
                    try {
                        val file = File(call.argument<String>("path") ?: "").canonicalFile
                        val allowed = (file.path.startsWith(File(activity.filesDir, "moneytrack-data").canonicalPath + File.separator) && file.path.contains("/receipts/")) ||
                            file.path.startsWith(File(activity.cacheDir, "exports").canonicalPath + File.separator)
                        val type = when (file.extension.lowercase()) { "pdf" -> "application/pdf"; "png" -> "image/png"; "jpg" -> "image/jpeg"; else -> throw IllegalArgumentException() }
                        if (!allowed || !file.isFile) throw IllegalArgumentException()
                        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".privatefiles", file)
                        activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, type).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result.success(null)
                    } catch (_: Exception) { result.error("OPEN", "This private file cannot be opened", null) }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun onResult(request: Int, status: Int, intent: Intent?): Boolean {
        if (request != 7404 && request != 7405) return false
        val result = pending ?: return true; pending = null
        val savedCamera = camera; camera = null
        val maximum = limit
        Thread {
        try {
            if (status != Activity.RESULT_OK) { activity.runOnUiThread { result.success(null) }; return@Thread }
            val file = savedCamera
            val uri: Uri = if (request == 7404) Uri.fromFile(file ?: throw IllegalStateException()) else intent?.data ?: throw IllegalArgumentException()
            var name = if (request == 7404) "Receipt.jpg" else "Document"
            if (request == 7405) activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    name = cursor.getString(0) ?: name
                    if (!cursor.isNull(1) && cursor.getLong(1) > maximum) throw IllegalArgumentException()
                }
            }
            val bytes = (if (request == 7404) file!!.inputStream() else activity.contentResolver.openInputStream(uri)!!).use { input ->
                val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(16384); var total = 0
                while (true) { val size = input.read(buffer); if (size < 0) break; total += size; if (total > maximum) throw IllegalArgumentException(); output.write(buffer, 0, size) }
                output.toByteArray()
            }
            activity.runOnUiThread { result.success(mapOf("name" to name, "bytes" to bytes)) }
        } catch (_: Exception) { activity.runOnUiThread { result.error("IMPORT", "File unreadable or too large", null) } }
        finally { savedCamera?.delete() }
        }.start()
        return true
    }
}
