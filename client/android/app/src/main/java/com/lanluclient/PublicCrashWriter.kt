package com.lanluclient

import android.app.Application
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore

/** API 29+ only: make crash files visible in the public Downloads folder. */
@android.annotation.TargetApi(Build.VERSION_CODES.Q)
object PublicCrashWriter {
  fun write(application: Application, name: String, bytes: ByteArray) {
    try {
      val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, name)
        put(MediaStore.Downloads.MIME_TYPE, "text/plain")
        put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/LanluCrash")
      }
      val uri = application.contentResolver.insert(
        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
        values,
      )
      if (uri != null) {
        application.contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
      }
    } catch (_: Throwable) {
    }
  }
}
