package com.moneytrack.moneytrack

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
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
    private var compressPhoto = false
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "moneytrack/documents").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    if (pending != null) { result.error("BUSY", "A document picker is already open", null); return@setMethodCallHandler }
                    val kind = call.argument<String>("kind") ?: "document"
                    compressPhoto = call.argument<Boolean>("compressPhoto") == true && kind in listOf("camera", "gallery")
                    limit = if (kind == "backup" || compressPhoto) 33554432 else 10485760
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
        val shrink = compressPhoto
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
            val content = if (shrink) resizeReceipt(bytes) else bytes
            if (shrink) {
                val extension = if (content[0] == 0x89.toByte()) ".png" else ".jpg"
                name = name.substringBeforeLast('.') + extension
            }
            activity.runOnUiThread { result.success(mapOf("name" to name, "bytes" to content)) }
        } catch (_: Exception) { activity.runOnUiThread { result.error("IMPORT", "File unreadable or too large", null) } }
        finally { savedCamera?.delete() }
        }.start()
        return true
    }
    private fun resizeReceipt(bytes: ByteArray): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth in 1..20000 && bounds.outHeight in 1..20000)
        val jpeg = bounds.outMimeType == "image/jpeg"
        val png = bounds.outMimeType == "image/png"
        require(jpeg || png)
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        if (bytes.size <= 2 * 1024 * 1024 && longest <= 2400) return bytes

        var sample = 1
        while (longest / sample > 4800) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(
            bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }
        ) ?: throw IllegalArgumentException("Invalid receipt photo")
        val matrix = Matrix()
        if (jpeg && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val orientation = bytes.inputStream().use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(-90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(270f)
            }
        }
        val scale = minOf(1f, 2400f / maxOf(decoded.width, decoded.height))
        matrix.postScale(scale, scale)
        val resized = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        try {
            val output = java.io.ByteArrayOutputStream()
            for (quality in listOf(90, 82, 74, 66)) {
                output.reset()
                require(resized.compress(Bitmap.CompressFormat.JPEG, quality, output))
                if (output.size() <= 2 * 1024 * 1024) return output.toByteArray()
            }
            throw IllegalArgumentException("Receipt could not be compressed to 2 MiB")
        } finally {
            if (resized !== decoded) resized.recycle()
            decoded.recycle()
        }
    }
}
