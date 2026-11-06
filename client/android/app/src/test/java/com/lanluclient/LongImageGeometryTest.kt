package com.lanluclient

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LongImageGeometryTest {

  @Test
  fun keepsNarrowPagesAtFullResolution() {
    assertEquals(1, LongImageGeometry.sampleSize(1080, 1080))
    assertEquals(1, LongImageGeometry.sampleSize(1600, 1080))
  }

  @Test
  fun downsamplesWidePagesAndCapsTheSample() {
    assertEquals(1, LongImageGeometry.sampleSize(1600, 1080))
    assertEquals(2, LongImageGeometry.sampleSize(2160, 1080))
    assertEquals(2, LongImageGeometry.sampleSize(4000, 1080))
    assertEquals(8, LongImageGeometry.sampleSize(50000, 1080))
    assertEquals(1, LongImageGeometry.sampleSize(0, 1080))
  }

  @Test
  fun stripHeightStaysInsideTheBitmapBudget() {
    for (width in intArrayOf(360, 720, 1080, 1440, 2160, 4096)) {
      val height = LongImageGeometry.stripScaledHeight(width)
      assertTrue("height for $width", height in 512..4096)
      assertTrue("budget for $width", width.toLong() * height * 4 <= 8L * 1024 * 1024)
    }
  }

  @Test
  fun veryTallPagesSplitIntoVisibleSizedStrips() {
    val sample = LongImageGeometry.sampleSize(1080, 1080)
    val scaledHeight = (20000 + sample - 1) / sample
    val stripHeight = LongImageGeometry.stripScaledHeight(1080)
    val count = LongImageGeometry.stripCount(scaledHeight, stripHeight)

    assertEquals(1, sample)
    assertTrue("strip count", count in 2..16)
    assertEquals(count, LongImageGeometry.stripCount(20000, stripHeight))
  }

  @Test
  fun emptyDimensionsHaveNoStrips() {
    assertEquals(0, LongImageGeometry.stripCount(0, 1000))
    assertEquals(0, LongImageGeometry.stripCount(1000, 0))
  }

  @Test
  fun detectsUniformBorderAroundArtwork() {
    val pixels = IntArray(10 * 10) { index ->
      val x = index % 10
      val y = index / 10
      if (x in 2..7 && y in 2..7) GRAY else WHITE
    }
    val box = LongImageGeometry.detectCropBox(pixels, 10, 10)
    assertEquals(2, box.left)
    assertEquals(2, box.top)
    assertEquals(8, box.right)
    assertEquals(8, box.bottom)
  }

  @Test
  fun keepsFullyUniformImagesUncropped() {
    val box = LongImageGeometry.detectCropBox(IntArray(100) { WHITE }, 10, 10)
    assertEquals(0, box.left)
    assertEquals(0, box.top)
    assertEquals(10, box.right)
    assertEquals(10, box.bottom)
  }

  @Test
  fun cropsOnlyTheBorderThatExists() {
    val pixels = IntArray(10 * 10) { index ->
      if (index / 10 < 3) WHITE else GRAY
    }
    val box = LongImageGeometry.detectCropBox(pixels, 10, 10)
    assertEquals(0, box.left)
    assertEquals(3, box.top)
    assertEquals(10, box.right)
    assertEquals(10, box.bottom)
  }

  @Test
  fun toleratesNearBorderColours() {
    val nearWhite = 0xFFF8F8F8.toInt()
    val pixels = IntArray(10 * 10) { index ->
      if (index % 10 in 2..7 && index / 10 in 2..7) GRAY else nearWhite
    }
    val box = LongImageGeometry.detectCropBox(pixels, 10, 10)
    assertEquals(2, box.left)
    assertEquals(2, box.top)
    assertEquals(8, box.right)
    assertEquals(8, box.bottom)
  }

  private companion object {
    const val WHITE = 0xFFFFFFFF.toInt()
    const val GRAY = 0xFF808080.toInt()
  }
}
