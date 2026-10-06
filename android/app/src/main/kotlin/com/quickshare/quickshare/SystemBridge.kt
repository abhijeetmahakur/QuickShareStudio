package com.quickshare.quickshare

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Platform services Dart needs on Android: the transfer foreground service, opening received
 * files, and installing a downloaded update after checking it is signed like this app.
 */
class SystemBridge(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "quickshare/system")
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
