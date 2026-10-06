package com.quickshare.quickshare

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Saves files into the public Downloads/QuickShare folder, where the Files app shows them:
 * through MediaStore on Android 10+ (no storage permission needed), as plain files before that
 * (Dart asks for storage permission first). Calls run on a background queue, so disk writes
 * never block the UI thread.
 *
 * A file is written in steps (begin, write..., then finish or discard) and is identified by a
 * handle: its content:// URI on Android 10+, its path before.
 */
class DownloadsBridge(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(
        messenger,
        "quickshare/downloads",
        StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue(),
    )
    private val open = ConcurrentHashMap<String, OutputStream>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "begin" -> result.success(begin(call.argument<String>("name")!!))
                "write" -> {
                    write(call.argument<String>("handle")!!, call.argument<ByteArray>("data")!!)
                    result.success(null)
                }
                "finish" -> result.success(finish(call.argument<String>("handle")!!))
                "discard" -> {
                    discard(call.argument<String>("handle")!!)
                    result.success(null)
                }
                "keep" -> result.success(keep(call.argument<String>("path")!!, call.argument<String>("name")!!))
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    /** Deletes files that were still being written (the app is closing, so they never finish). */
    fun dispose() {
        channel.setMethodCallHandler(null)
        for (handle in open.keys.toList()) {
            try {
                discard(handle)
            } catch (_: Exception) {
            }
        }
    }

    /** Creates an empty file that other apps cannot see yet; returns its handle. */
    private fun begin(name: String): String {
        val (handle, output) = create(name)
        open[handle] = output
        return handle
    }

    private fun write(handle: String, data: ByteArray) {
        val output = open[handle] ?: throw IOException("The Downloads file is no longer open.")
        output.write(data)
    }

    /** Closes and publishes the file; returns the name Android gave it, e.g. "photo (1).jpg". */
    private fun finish(handle: String): String {
        val output = open.remove(handle) ?: throw IOException("The Downloads file is no longer open.")
        try {
            output.close()
            return publish(handle)
        } catch (e: Exception) {
            delete(handle)
            throw e
        }
    }

    private fun discard(handle: String) {
        try {
            open.remove(handle)?.close()
        } finally {
            delete(handle)
        }
    }

    /**
     * Makes sure the file at [path] is in Downloads: returns it unchanged if it already is there,
     * copies it in as [name] if it is somewhere else (e.g. app storage), or returns null if it no
     * longer exists.
     */
    private fun keep(path: String, name: String): Map<String, Any>? {
        if (isContent(path)) {
            val existing = displayName(Uri.parse(path)) ?: return null
            return mapOf("path" to path, "name" to existing, "copied" to false)
        }
        val source = File(if (path.startsWith("file://")) Uri.parse(path).path ?: return null else path)
        if (!source.isFile) return null
        if (source.canonicalPath.startsWith(publicDownloads().canonicalPath + File.separator)) {
            return mapOf("path" to source.path, "name" to source.name, "copied" to false)
        }
        val (handle, output) = create(name)
        try {
            output.use { out -> source.inputStream().use { it.copyTo(out) } }
            return mapOf("path" to handle, "name" to publish(handle), "copied" to true)
        } catch (e: Exception) {
            delete(handle)
            throw e
        }
    }

    private fun create(name: String): Pair<String, OutputStream> {
        val safeName = File(name).name.ifEmpty { "file" }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType(safeName))
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/QuickShare")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            // Android renames on a clash ("photo (1).jpg"); finish() reports the final name.
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Android could not create a file in Downloads/QuickShare.")
            val output = try {
                resolver.openOutputStream(uri, "w") ?: throw IOException("Android could not open the new Downloads file.")
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            return uri.toString() to output
        }
        val folder = File(publicDownloads(), "QuickShare")
        if (!folder.isDirectory && !folder.mkdirs()) {
            throw IOException("Could not create the Downloads/QuickShare folder.")
        }
        val file = uniqueFile(folder, safeName)
        return file.path to FileOutputStream(file)
    }

    /** Makes a written file visible in Downloads; returns its final name. */
    private fun publish(handle: String): String {
        if (isContent(handle)) {
            val uri = Uri.parse(handle)
            val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            if (context.contentResolver.update(uri, values, null, null) == 0) {
                throw IOException("Android could not publish the file in Downloads.")
            }
            return displayName(uri) ?: throw IOException("The Downloads file disappeared.")
        }
        MediaScannerConnection.scanFile(context, arrayOf(handle), null, null)
        return File(handle).name
    }

    private fun delete(handle: String) {
        if (isContent(handle)) {
            context.contentResolver.delete(Uri.parse(handle), null, null)
        } else {
            File(handle).delete()
        }
    }

    /** The entry's current name, or null if it is gone (or belongs to an earlier install). */
    private fun displayName(uri: Uri): String? = try {
        context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (_: Exception) {
        null
    }

    private fun isContent(handle: String) = handle.startsWith("content://")

    @Suppress("DEPRECATION") // Still the public Downloads path: written directly before Android 10.
    private fun publicDownloads(): File = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)

    /** [name], or "name (1).ext", "name (2).ext"...: the first one not taken in [folder]. */
    private fun uniqueFile(folder: File, name: String): File {
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var file = File(folder, name)
        var n = 1
        while (file.exists()) file = File(folder, "$stem (${n++})$ext")
        return file
    }

    private fun mimeType(name: String): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"
}
