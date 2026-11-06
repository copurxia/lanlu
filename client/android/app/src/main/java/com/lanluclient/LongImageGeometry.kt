package com.lanluclient

import kotlin.math.abs

/**
 * Pure geometry for the strip decoder. Kept outside the View so the memory
 * budget and downsampling rules can be unit tested on the JVM.
 */
internal object LongImageGeometry {
  const val STRIP_BUDGET_BYTES = 8L * 1024 * 1024
  const val MAX_STRIP_HEIGHT = 4096
  const val MIN_STRIP_HEIGHT = 512

  fun sampleSize(sourceWidth: Int, targetWidth: Int, maxSample: Int = 8): Int {
    if (sourceWidth <= 0 || targetWidth <= 0) return 1
    var sample = 1
    while (sourceWidth / (sample * 2) >= targetWidth && sample < maxSample) {
      sample *= 2
    }
    return sample
  }

  fun stripScaledHeight(scaledWidth: Int): Int {
    if (scaledWidth <= 0) return MIN_STRIP_HEIGHT
    val budgetHeight = (STRIP_BUDGET_BYTES / 4 / scaledWidth.toLong()).toInt()
    return budgetHeight.coerceIn(MIN_STRIP_HEIGHT, MAX_STRIP_HEIGHT)
  }

  fun stripCount(scaledHeight: Int, stripScaledHeight: Int): Int {
    if (scaledHeight <= 0 || stripScaledHeight <= 0) return 0
    return (scaledHeight + stripScaledHeight - 1) / stripScaledHeight
  }

  data class CropBox(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
  }

  /**
   * Finds a uniform border around the artwork, using the top-left pixel as the
   * border colour. Returns the full box when no usable border is found.
   */
  fun detectCropBox(
    pixels: IntArray,
    width: Int,
    height: Int,
    tolerance: Int = 12,
  ): CropBox {
    if (width <= 2 || height <= 2 || pixels.size < width * height) {
      return CropBox(0, 0, width, height)
    }
    val border = pixels[0]
    val borderR = (border shr 16) and 0xFF
    val borderG = (border shr 8) and 0xFF
    val borderB = border and 0xFF

    fun differs(pixel: Int): Boolean {
      val r = (pixel shr 16) and 0xFF
      val g = (pixel shr 8) and 0xFF
      val b = pixel and 0xFF
      return abs(r - borderR) > tolerance ||
        abs(g - borderG) > tolerance ||
        abs(b - borderB) > tolerance
    }

    fun uniformRow(y: Int): Boolean {
      val offset = y * width
      for (x in 0 until width) {
        if (differs(pixels[offset + x])) return false
      }
      return true
    }

    fun uniformColumn(x: Int): Boolean {
      for (y in 0 until height) {
        if (differs(pixels[y * width + x])) return false
      }
      return true
    }

    var top = 0
    while (top < height && uniformRow(top)) top++
    if (top >= height) return CropBox(0, 0, width, height)

    var bottom = height
    while (bottom > top && uniformRow(bottom - 1)) bottom--

    var left = 0
    while (left < width && uniformColumn(left)) left++
    var right = width
    while (right > left && uniformColumn(right - 1)) right--

    if (right - left <= 1 || bottom - top <= 1) {
      return CropBox(0, 0, width, height)
    }
    return CropBox(left, top, right, bottom)
  }
}
