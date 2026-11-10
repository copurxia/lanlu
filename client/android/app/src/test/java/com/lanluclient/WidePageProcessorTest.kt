package com.lanluclient

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = android.app.Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WidePageProcessorTest {

  @Test
  fun detectsWidePages() {
    assertTrue(WidePageProcessor.isWide(2000, 1400))
    assertTrue(!WidePageProcessor.isWide(1400, 2000))
    assertTrue(!WidePageProcessor.isWide(1000, 1000))
  }

  @Test
  fun splitsIntoLeftAndRightHalves() {
    val source = sideBySideBitmap()
    val split = WidePageProcessor.split(source)
    assertNotNull(split)
    val result = split!!
    assertEquals(50, result.left.width)
    assertEquals(50, result.right.width)
    assertEquals(50, result.left.height)
    assertEquals(50, result.right.height)
    assertEquals(Color.RED, result.left.getPixel(10, 10))
    assertEquals(Color.BLUE, result.right.getPixel(10, 10))
    source.recycle()
    result.left.recycle()
    result.right.recycle()
  }

  @Test
  fun rotatesWidePagesClockwiseAndCounterClockwise() {
    val source = topBottomBitmap()
    val clockwise = WidePageProcessor.rotate(source, clockwise = true)
    assertNotNull(clockwise)
    val cw = clockwise!!
    assertEquals(4, cw.width)
    assertEquals(10, cw.height)
    // Top half (red) rotates to the right half; bottom half (blue) to the left.
    assertEquals(Color.RED, cw.getPixel(3, 5))
    assertEquals(Color.BLUE, cw.getPixel(0, 5))

    val counter = WidePageProcessor.rotate(source, clockwise = false)
    assertNotNull(counter)
    val ccw = counter!!
    assertEquals(4, ccw.width)
    assertEquals(10, ccw.height)
    assertEquals(Color.BLUE, ccw.getPixel(3, 5))
    assertEquals(Color.RED, ccw.getPixel(0, 5))

    source.recycle()
    cw.recycle()
    ccw.recycle()
  }

  private fun sideBySideBitmap(): Bitmap {
    val bitmap = Bitmap.createBitmap(100, 50, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint()
    paint.color = Color.RED
    canvas.drawRect(0f, 0f, 50f, 50f, paint)
    paint.color = Color.BLUE
    canvas.drawRect(50f, 0f, 100f, 50f, paint)
    return bitmap
  }

  private fun topBottomBitmap(): Bitmap {
    val bitmap = Bitmap.createBitmap(10, 4, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint()
    paint.color = Color.RED
    canvas.drawRect(0f, 0f, 10f, 2f, paint)
    paint.color = Color.BLUE
    canvas.drawRect(0f, 2f, 10f, 4f, paint)
    return bitmap
  }
}
