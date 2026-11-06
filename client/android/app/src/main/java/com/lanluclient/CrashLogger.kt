package com.lanluclient

import android.app.Application
import android.os.Build
import android.os.Environment
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Crash evidence for builds that cannot be attached to adb.
 *
 * Java exceptions are written before the process dies. Android 11+ also keeps a
 * process-exit history (native crashes/ANRs), which is copied on the next start.
 */
object CrashLogger {
  private const val MAX_TRACE_BYTES = 128 * 1024
  private const val CRASH_DIR = "LanluCrash"

  @Volatile
  private var installed = false

  fun install(application: Application) {
    if (installed) return
    installed = true
    val previous = Thread.getDefaultUncaughtExceptionHandler()
    Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
      try {
        writeCrash(application, thread, throwable)
      } catch (_: Throwable) {
        // Never mask the original crash.
      }
      previous?.uncaughtException(thread, throwable)
    }
  }

  private fun writeCrash(application: Application, thread: Thread, throwable: Throwable) {
    val sw = StringWriter()
    PrintWriter(sw).use { throwable.printStackTrace(it) }
    val text = buildString {
      appendLine("Lanlu crash")
      appendLine("time=${timestamp()}")
      appendLine("thread=${thread.name}")
      appendLine("device=${Build.MANUFACTURER} ${Build.MODEL}")
      appendLine("android=${Build.VERSION.RELEASE} (sdk ${Build.VERSION.SDK_INT})")
      appendLine("app=${application.packageName}")
      appendLine()
      append(sw.toString().take(MAX_TRACE_BYTES))
    }
    writeText(application, "crash-${System.currentTimeMillis()}.txt", text)
  }

  private fun writeText(application: Application, name: String, text: String) {
    val bytes = text.toByteArray(Charsets.UTF_8)
    // Internal copy is always available.
    try {
      val internal = File(application.filesDir, "crash").apply { mkdirs() }
      File(internal, name).writeBytes(bytes)
    } catch (_: Throwable) {
    }
    // External app directory: Android/data/com.lanluclient/files/crash.
    try {
      val external = application.getExternalFilesDir(null)
      if (external != null) {
        val dir = File(external, "crash").apply { mkdirs() }
        File(dir, name).writeBytes(bytes)
      }
    } catch (_: Throwable) {
    }
    // Public Downloads on Android 10+: visible from the Files app / share sheet.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      PublicCrashWriter.write(application, name, bytes)
    } else {
      // Legacy Android 8/9: best-effort public copy if legacy storage is writable.
      try {
        val dir = File(
          Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
          CRASH_DIR,
        ).apply { mkdirs() }
        File(dir, name).writeBytes(bytes)
      } catch (_: Throwable) {
      }
    }
  }

  private fun timestamp(): String = dateString(System.currentTimeMillis())

  private fun dateString(value: Long): String =
    SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date(value))

  private fun reasonName(reason: Int): String = when (reason) {
    android.app.ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
    android.app.ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
    android.app.ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
    android.app.ApplicationExitInfo.REASON_CRASH -> "CRASH"
    android.app.ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
    android.app.ApplicationExitInfo.REASON_ANR -> "ANR"
    android.app.ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
    android.app.ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
    android.app.ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
    android.app.ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
    android.app.ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
    android.app.ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
    android.app.ApplicationExitInfo.REASON_OTHER -> "OTHER"
    else -> "UNKNOWN($reason)"
  }
}
