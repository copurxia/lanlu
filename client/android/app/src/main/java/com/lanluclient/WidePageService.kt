package com.lanluclient

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max

/**
 * Produces cached split/rotated files for wide spread pages. The source image
 * is downloaded through the same file cache as the webtoon strip decoder.
 */
internal object WidePageService {

  data class WidePageOutput(
    val wide: Boolean,
    val mode: String,
    val urls: List<String>,
    val width: Int,
    val height: Int,
    val sourceWidth: Int,
    val sourceHeight: Int,
  )

  private const val MAX_TRANSFORM_DIMENSION = 3072
  private const val MAX_CACHE_BYTES = 256L * 1024 * 1024

  private val locks = ConcurrentHashMap<String, Any>()

  fun create(
    context: Context,
    uri: String,
    headers: Map<String, String>,
    mode: String,
    invert: Boolean,
  ): WidePageOutput {
    val source = LanluLongImageStore.fetch(context, uri, headers) { _, _ -> }
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(source.absolutePath, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
      throw IOException("Unsupported or empty image")
    }
    if (!WidePageProcessor.isWide(bounds.outWidth, bounds.outHeight) || mode == "off") {
      return WidePageOutput(
        wide = false,
        mode = mode,
        urls = listOf(uri),
        width = bounds.outWidth,
        height = bounds.outHeight,
        sourceWidth = bounds.outWidth,
        sourceHeight = bounds.outHeight,
      )
    }

    val dir = File(context.applicationContext.cacheDir, "lanlu_wide_pages").apply { mkdirs() }
    val key = hash(
      "${source.absolutePath}|${source.length()}|${source.lastModified()}|$mode|$invert",
    )
    val lock = locks.getOrPut(key) { Any() }
    synchronized(lock) {
      try {
        if (mode == "split") {
          val left = File(dir, "$key-left.jpg")
          val right = File(dir, "$key-right.jpg")
          if (!left.exists() || left.length() == 0L || !right.exists() || right.length() == 0L) {
            val bitmap = decode(source, bounds)
            val split = WidePageProcessor.split(bitmap) ?: throw IOException("Unable to split image")
            bitmap.recycle()
            try {
              writeBitmap(split.left, left)
              writeBitmap(split.right, right)
            } finally {
              split.left.recycle()
              split.right.recycle()
            }
            trimCache(dir)
          }
          return WidePageOutput(
            wide = true,
            mode = "split",
            urls = listOf("file://${left.absolutePath}", "file://${right.absolutePath}"),
            width = bounds.outWidth / 2,
            height = bounds.outHeight,
            sourceWidth = bounds.outWidth,
            sourceHeight = bounds.outHeight,
          )
        }

        val rotated = File(dir, "$key-rotated.jpg")
        if (!rotated.exists() || rotated.length() == 0L) {
          val bitmap = decode(source, bounds)
          val rotatedBitmap = WidePageProcessor.rotate(bitmap, clockwise = !invert)
            ?: throw IOException("Unable to rotate image")
          bitmap.recycle()
          try {
            writeBitmap(rotatedBitmap, rotated)
          } finally {
            rotatedBitmap.recycle()
          }
          trimCache(dir)
        }
        return WidePageOutput(
          wide = true,
          mode = "rotate",
          urls = listOf("file://${rotated.absolutePath}"),
          width = bounds.outHeight,
          height = bounds.outWidth,
          sourceWidth = bounds.outWidth,
          sourceHeight = bounds.outHeight,
        )
      } finally {
        locks.remove(key)
      }
    }
  }

  private fun decode(source: File, bounds: BitmapFactory.Options): Bitmap {
    var sample = 1
    while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_TRANSFORM_DIMENSION) {
      sample *= 2
    }
    val options = BitmapFactory.Options().apply {
      inSampleSize = sample
      inPreferredConfig = Bitmap.Config.ARGB_8888
    }
    return BitmapFactory.decodeFile(source.absolutePath, options)
      ?: throw IOException("Unable to decode image")
  }

  private fun writeBitmap(bitmap: Bitmap, target: File) {
    target.outputStream().use { output ->
      if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 92, output)) {
        throw IOException("Unable to encode image")
      }
    }
  }


  private fun hash(value: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
    val builder = StringBuilder(digest.size * 2)
    for (byte in digest) {
      builder.append(String.format("%02x", byte))
    }
    return builder.toString()
  }

  private fun trimCache(dir: File) {
    val files = dir.listFiles { file -> file.isFile } ?: return
    var total = files.sumOf { it.length() }
    if (total <= MAX_CACHE_BYTES) return
    val target = (MAX_CACHE_BYTES * 3) / 4
    for (file in files.sortedBy { it.lastModified() }) {
      if (total <= target) break
      val length = file.length()
      if (file.delete()) total -= length
    }
  }
}
