package com.cnkh.cnkh_pos_desktop

import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.cnkh.cnkh_pos_desktop/whatsapp_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sharePdf" -> {
                        val path = call.argument<String>("path")
                        val text = call.argument<String>("text") ?: ""
                        val phone = call.argument<String>("phone")
                        if (path.isNullOrBlank()) {
                            result.error("ARG", "path required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val ok = sharePdfToWhatsApp(path, text, phone)
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("SHARE", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sharePdfToWhatsApp(path: String, text: String, phone: String?): Boolean {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalStateException("PDF not found: $path")
        }
        val authority = "${applicationContext.packageName}.fileprovider"
        val uri = FileProvider.getUriForFile(this, authority, file)

        fun launch(pkg: String): Boolean {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/pdf"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TEXT, text)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                setPackage(pkg)
                if (!phone.isNullOrBlank()) {
                    // Pre-select chat when number is known
                    putExtra("jid", "$phone@s.whatsapp.net")
                }
            }
            return try {
                grantUriPermission(
                    pkg,
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
                // Verify package can handle the intent
                val resolved = packageManager.resolveActivity(
                    intent,
                    PackageManager.MATCH_DEFAULT_ONLY,
                )
                if (resolved == null) return false
                startActivity(intent)
                true
            } catch (_: Exception) {
                false
            }
        }

        if (launch("com.whatsapp")) return true
        if (launch("com.whatsapp.w4b")) return true
        return false
    }
}
