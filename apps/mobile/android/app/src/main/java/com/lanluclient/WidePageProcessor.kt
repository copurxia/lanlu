package com.lanluclient

import android.graphics.Bitmap
import android.graphics.Matrix

/**
 * Pure bitmap operations for wide spread pages. Kept separate from the
 * download/cache code so they can be exercised by Robolectric tests.
 */
internal object WidePageProcessor {

  data class SplitResult(val left: Bitmap, val right: Bitmap)

  fun isWide(width: Int, height: Int): Boolean = width > height

  fun split(bitmap: Bitmap): SplitResult? {
    if (bitmap.width < 2 || bitmap.height <= 0) return null
    val leftWidth = bitmap.width / 2
    val rightWidth = bitmap.width - leftWidth
    if (leftWidth <= 0 || rightWidth <= 0) return null
    return try {
      SplitResult(
        Bitmap.createBitmap(bitmap, 0, 0, leftWidth, bitmap.height),
        Bitmap.createBitmap(bitmap, leftWidth, 0, rightWidth, bitmap.height),
      )
    } catch (_: Throwable) {
      null
    }
  }

  fun rotate(bitmap: Bitmap, clockwise: Boolean): Bitmap? {
    if (bitmap.width <= 0 || bitmap.height <= 0) return null
    return try {
      Bitmap.createBitmap(
        bitmap,
        0,
        0,
        bitmap.width,
        bitmap.height,
        Matrix().apply { postRotate(if (clockwise) 90f else -90f) },
        true,
      )
    } catch (_: Throwable) {
      null
    }
  }
}
