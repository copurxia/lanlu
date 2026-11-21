package com.lanluclient

import android.app.ActivityManager
import android.app.Application
import android.app.ApplicationExitInfo
import android.os.Build
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** API 30+ only: copied on the next launch to capture native crashes/ANRs. */
@android.annotation.TargetApi(Build.VERSION_CODES.R)
object ExitHistoryRecorder {
  private const val MAX_TRACE_BYTES = 128 * 1024

  fun record(application: Application) {
    try {
      val manager = application.getSystemService(ActivityManager::class.java) ?: return
      val reasons = manager.getHistoricalProcessExitReasons(application.packageName, 0, 5)
      if (reasons.isEmpty()) return
      val text = buildString {
        appendLine("Lanlu exit history")
        appendLine("generatedAt=${dateString(System.currentTimeMillis())}")
        reasons.forEach { info ->
          appendLine("---")
          appendLine("process=${info.processName}")
          appendLine("reason=${reasonName(info.reason)}")
          appendLine("importance=${info.importance}")
          appendLine("timestamp=${dateString(info.timestamp)}")
          appendLine("description=${info.description.orEmpty()}")
          val trace = try {
            info.traceInputStream?.bufferedReader()?.use { it.readText() }
          } catch (_: Throwable) {
            null
          }
          if (!trace.isNullOrBlank()) {
            appendLine("trace=")
            appendLine(trace.take(MAX_TRACE_BYTES))
          }
        }
      }
      write(application, "exit-history-${System.currentTimeMillis()}.txt", text)
    } catch (_: Throwable) {
    }
  }

  private fun write(application: Application, name: String, text: String) {
    val bytes = text.toByteArray(Charsets.UTF_8)
    try {
      val internal = File(application.filesDir, "crash").apply { mkdirs() }
      File(internal, name).writeBytes(bytes)
    } catch (_: Throwable) {
    }
    try {
      val external = application.getExternalFilesDir(null)
      if (external != null) {
        val dir = File(external, "crash").apply { mkdirs() }
        File(dir, name).writeBytes(bytes)
      }
    } catch (_: Throwable) {
    }
  }

  private fun dateString(value: Long): String =
    SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date(value))

  private fun reasonName(reason: Int): String = when (reason) {
    ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
    ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
    ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
    ApplicationExitInfo.REASON_CRASH -> "CRASH"
    ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
    ApplicationExitInfo.REASON_ANR -> "ANR"
    ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
    ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
    ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
    ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
    ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
    ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
    ApplicationExitInfo.REASON_OTHER -> "OTHER"
    else -> "UNKNOWN($reason)"
  }
}
