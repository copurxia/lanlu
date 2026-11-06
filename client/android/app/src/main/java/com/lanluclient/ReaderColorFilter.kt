package com.lanluclient

import android.graphics.ColorMatrix
import kotlin.math.abs

/** Builds the reader-wide colour matrix for grayscale/invert/brightness. */
internal object ReaderColorFilter {

  fun build(grayscale: Boolean, invert: Boolean, brightness: Float): ColorMatrix? {
    val scale = brightness.coerceIn(0.2f, 2f)
    if (!grayscale && !invert && abs(scale - 1f) < 0.001f) return null

    val matrix = ColorMatrix()
    if (grayscale) {
      matrix.setSaturation(0f)
    }
    if (invert) {
      matrix.postConcat(
        ColorMatrix(
          floatArrayOf(
            -1f, 0f, 0f, 0f, 255f,
            0f, -1f, 0f, 0f, 255f,
            0f, 0f, -1f, 0f, 255f,
            0f, 0f, 0f, 1f, 0f,
          ),
        ),
      )
    }
    if (abs(scale - 1f) >= 0.001f) {
      matrix.postConcat(ColorMatrix().apply { setScale(scale, scale, scale, 1f) })
    }
    return matrix
  }
}
