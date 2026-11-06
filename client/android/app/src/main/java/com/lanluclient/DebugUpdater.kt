package com.lanluclient

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Debug-only LAN updater. The container serves /version.json and the latest
 * debug APK on port 8083; physical devices install once, then update in place.
 */
object DebugUpdater {
  private const val VERSION_URL = "http://192.168.0.111:8083/version.json"
  private const val PREFS = "lanlu_debug_updater"

  fun check(activity: Activity) {
    if (!BuildConfig.DEBUG) return
    Thread {
      try {
        val info = JSONObject(readUrl(VERSION_URL))
        val remoteCode = info.optInt("versionCode", 0)
        if (remoteCode <= BuildConfig.VERSION_CODE) return@Thread
        val prefs = activity.getSharedPreferences(PREFS, 0)
        if (prefs.getInt("last_prompted", 0) >= remoteCode) return@Thread
        val remoteSha = info.optString("sha256", "")
        val apkUrl = info.optString("url", "")
        if (apkUrl.isBlank()) return@Thread

        val apk = File(activity.getExternalFilesDir(null), "update/app-debug.apk")
        apk.parentFile?.mkdirs()
        download(apkUrl, apk)
        if (remoteSha.isNotBlank() && sha256(apk) != remoteSha) {
          apk.delete()
          return@Thread
        }
        activity.runOnUiThread {
          AlertDialog.Builder(activity)
            .setTitle("Lanlu debug update")
            .setMessage("New debug build $remoteCode is ready. Install now?")
            .setPositiveButton("Install") { _, _ -> install(activity, apk, remoteCode) }
            .setNegativeButton("Later") { _, _ ->
              prefs.edit().putInt("last_prompted", remoteCode).apply()
            }
            .show()
        }
      } catch (_: Throwable) {
        // Update service is optional; never block app start.
      }
    }.start()
  }

  private fun install(activity: Activity, apk: File, remoteCode: Int) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
      !activity.packageManager.canRequestPackageInstalls()
    ) {
      AlertDialog.Builder(activity)
        .setTitle("Allow install")
        .setMessage("Allow Lanlu to install unknown apps, then reopen the app to update.")
        .setPositiveButton("Settings") { _, _ ->
          activity.startActivity(
            Intent(
              Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
              Uri.parse("package:${activity.packageName}"),
            ),
          )
        }
        .setNegativeButton("Cancel", null)
        .show()
      return
    }
    val uri = FileProvider.getUriForFile(
      activity,
      "${activity.packageName}.fileprovider",
      apk,
    )
    val intent = Intent(Intent.ACTION_VIEW)
      .setDataAndType(uri, "application/vnd.android.package-archive")
      .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    activity.startActivity(intent)
    activity.getSharedPreferences(PREFS, 0).edit().putInt("last_prompted", remoteCode).apply()
  }

  private fun readUrl(url: String): String {
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.connectTimeout = 5000
    connection.readTimeout = 15000
    connection.requestMethod = "GET"
    return connection.inputStream.bufferedReader().use { it.readText() }
  }

  private fun download(url: String, target: File) {
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.connectTimeout = 5000
    connection.readTimeout = 60000
    connection.inputStream.use { input ->
      FileOutputStream(target).use { output -> input.copyTo(output) }
    }
  }

  private fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
      val buffer = ByteArray(64 * 1024)
      while (true) {
        val read = input.read(buffer)
        if (read <= 0) break
        digest.update(buffer, 0, read)
      }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
  }
}
