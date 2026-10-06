package com.quickshare.quickshare

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.security.MessageDigest

/**
 * Platform services Dart needs on Android: the transfer foreground service, opening received
 * files, and installing a downloaded update after checking it is signed like this app.
 */
class SystemBridge(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "quickshare/system")
    private val downloadStreams = mutableMapOf<String, OutputStream>()
    var activity: Activity? = null

    init {
        channel.setMethodCallHandler(this)
    }

    private val authority get() = "${context.packageName}.fileprovider"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "transferServiceUpdate" -> {
                    TransferService.update(
                        context,
                        call.argument<String>("title") ?: "Transferring files",
                        call.argument<String>("text") ?: "",
                        call.argument<Int>("progress") ?: -1,
                    )
                    result.success(null)
                }
                "transferServiceStop" -> {
                    TransferService.stop(context)
                    result.success(null)
                }
                "openFile" -> result.success(openFile(call.argument<String>("path")!!))
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                "beginDownload" -> result.success(beginDownload(call.argument<String>("name")!!))
                "writeDownloadChunk" -> {
                    writeDownloadChunk(call.argument<String>("uri")!!, call.argument<ByteArray>("data")!!)
                    result.success(null)
                }
                "finishDownload" -> result.success(finishDownload(call.argument<String>("uri")!!))
                "discardDownload" -> {
                    discardDownload(call.argument<String>("uri")!!)
                    result.success(null)
                }
                "installApk" -> result.success(installApk(call.argument<String>("path")!!))
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    private fun openFile(path: String): Boolean {
        val parsedUri = Uri.parse(path)
        if (parsedUri.scheme == "content") {
            val mime = context.contentResolver.getType(parsedUri) ?: "application/octet-stream"
            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(parsedUri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            return try {
                context.startActivity(Intent.createChooser(intent, "Open received file").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (_: ActivityNotFoundException) {
                false
            }
        }

        val file = File(if (parsedUri.scheme == "file") parsedUri.path ?: return false else path)
        if (!file.exists()) return false
        val uri = FileProvider.getUriForFile(context, authority, file)
        val ext = file.extension.lowercase()
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(Intent.createChooser(intent, file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun beginDownload(name: String): Map<String, String> {
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/QuickShare/"
        val savedName: String
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            savedName = availableDownloadName(name, relativePath)
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, savedName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType(name))
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Android could not create a file in Downloads/QuickShare.")
        } else {
            val directory = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "QuickShare",
            )
            if (!directory.exists() && !directory.mkdirs()) {
                throw IllegalStateException("Could not create the QuickShare folder in Downloads.")
            }
            savedName = availableDownloadName(name, directory.path)
            val file = File(directory, savedName)
            Uri.fromFile(file)
        }

        val key = uri.toString()
        try {
            val output = if (uri.scheme == "content") {
                context.contentResolver.openOutputStream(uri, "w")
            } else {
                FileOutputStream(File(uri.path ?: throw IllegalStateException("Invalid Downloads file path.")))
            } ?: throw IllegalStateException("Android could not open the Downloads file for writing.")
            downloadStreams[key] = output
        } catch (error: Exception) {
            if (uri.scheme == "content") context.contentResolver.delete(uri, null, null)
            throw error
        }
        return mapOf("uri" to key, "name" to savedName)
    }

    private fun writeDownloadChunk(uri: String, data: ByteArray) {
        val output = downloadStreams[uri]
            ?: throw IllegalStateException("The Downloads file is no longer open.")
        output.write(data)
    }

    private fun finishDownload(uri: String): String {
        val output = downloadStreams.remove(uri)
            ?: throw IllegalStateException("The Downloads file is no longer open.")
        val parsedUri = Uri.parse(uri)
        try {
            output.flush()
            output.close()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && parsedUri.scheme == "content") {
                val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
                if (context.contentResolver.update(parsedUri, values, null, null) == 0) {
                    throw IllegalStateException("Android could not publish the file in Downloads.")
                }
            }
            return uri
        } catch (error: Exception) {
            if (parsedUri.scheme == "content") {
                context.contentResolver.delete(parsedUri, null, null)
            } else {
                parsedUri.path?.let { File(it).delete() }
            }
            throw error
        }
    }

    private fun discardDownload(uri: String) {
        val parsedUri = Uri.parse(uri)
        try {
            downloadStreams.remove(uri)?.close()
        } finally {
            if (parsedUri.scheme == "content") {
                context.contentResolver.delete(parsedUri, null, null)
            } else {
                File(parsedUri.path ?: return).delete()
            }
        }
    }

    private fun availableDownloadName(name: String, relativePath: String): String {
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val displayName = MediaStore.MediaColumns.DISPLAY_NAME
        val relative = MediaStore.MediaColumns.RELATIVE_PATH
        var candidate = name
        var suffix = 1
        while (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            resolver.query(
                collection,
                arrayOf(displayName),
                "$displayName = ? AND $relative = ?",
                arrayOf(candidate, relativePath),
                null,
            )?.use { it.moveToFirst() } == true
        ) {
            val dot = name.lastIndexOf('.')
            candidate = if (dot > 0) {
                "${name.substring(0, dot)} ($suffix)${name.substring(dot)}"
            } else {
                "$name ($suffix)"
            }
            suffix++
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val directory = File(relativePath)
            while (File(directory, candidate).exists()) {
                val dot = name.lastIndexOf('.')
                candidate = if (dot > 0) {
                    "${name.substring(0, dot)} ($suffix)${name.substring(dot)}"
                } else {
                    "$name ($suffix)"
                }
                suffix++
            }
        }
        return candidate
    }

    private fun mimeType(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
    }

    @Suppress("DEPRECATION")
    private fun signerDigests(info: PackageInfo?): Set<String> {
        if (info == null) return emptySet()
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            val signing = info.signingInfo ?: return emptySet()
            if (signing.hasMultipleSigners()) signing.apkContentsSigners else signing.signingCertificateHistory
        } else {
            info.signatures
        } ?: return emptySet()
        val sha = MessageDigest.getInstance("SHA-256")
        return signatures.map { s -> sha.digest(s.toByteArray()).joinToString("") { "%02x".format(it) } }.toSet()
    }

    /**
     * Returns "started", "needs_permission" (the user must allow installs from QuickShare first),
     * "signature_mismatch", "wrong_package" or "invalid".
     */
    @Suppress("DEPRECATION")
    private fun installApk(path: String): String {
        val file = File(path)
        val pm = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = pm.getPackageArchiveInfo(file.path, flags) ?: return "invalid"
        if (archive.packageName != context.packageName) return "wrong_package"
        // Android refuses an update signed by someone else anyway; checking first gives a clear
        // message instead of a generic "App not installed".
        archive.applicationInfo?.apply {
            sourceDir = file.path
            publicSourceDir = file.path
        }
        val installed = pm.getPackageInfo(context.packageName, flags)
        val mine = signerDigests(installed)
        val theirs = signerDigests(archive)
        if (mine.isEmpty() || theirs.isEmpty() || mine.intersect(theirs).isEmpty()) return "signature_mismatch"

        if (Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) {
            val settings = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(settings)
            return "needs_permission"
        }
        val uri = FileProvider.getUriForFile(context, authority, file)
        val install = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(install)
        return "started"
    }
}
