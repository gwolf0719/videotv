package com.example.videotv

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "install_apk"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        installApk(filePath, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath is required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun installApk(filePath: String, result: MethodChannel.Result) {
        try {
            // Android 8+ 需要先檢查安裝權限
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (!packageManager.canRequestPackageInstalls()) {
                    // 請求安裝權限
                    val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    intent.data = Uri.parse("package:$packageName")
                    startActivity(intent)
                    result.success("Permission requested")
                    return
                }
            }

            val file = File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "APK file not found", null)
                return
            }

            val intent = Intent(Intent.ACTION_VIEW)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Android 7+ 使用 FileProvider
                val uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    file
                )
                intent.setDataAndType(uri, "application/vnd.android.package-archive")
            } else {
                intent.setDataAndType(Uri.fromFile(file), "application/vnd.android.package-archive")
            }

            startActivity(intent)
            result.success("Install intent started")
        } catch (e: Exception) {
            result.error("INSTALL_ERROR", e.message, null)
        }
    }
}
