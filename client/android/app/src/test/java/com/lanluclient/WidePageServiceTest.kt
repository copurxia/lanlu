package com.lanluclient

import android.app.Application
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WidePageServiceTest {

  @Test
  fun returnsOriginalForNonWidePages() {
    val context = RuntimeEnvironment.getApplication()
    val file = copyResource(context, "lanlu-long-test.png")
    val uri = "file://${file.absolutePath}"

    val output = WidePageService.create(context, uri, emptyMap(), "split", false)

    assertTrue(!output.wide)
    assertEquals(1, output.urls.size)
    assertEquals(uri, output.urls[0])
    assertEquals(64, output.sourceWidth)
    assertEquals(12000, output.sourceHeight)
  }

  @Test
  fun splitsWidePagesIntoLeftAndRightFiles() {
    val context = RuntimeEnvironment.getApplication()
    val file = copyResource(context, "lanlu-wide-test.png")
    val output = WidePageService.create(
      context,
      "file://${file.absolutePath}",
      emptyMap(),
      "split",
      false,
    )

    assertTrue(output.wide)
    assertEquals("split", output.mode)
    assertEquals(2, output.urls.size)
    assertEquals(100, output.width)
    assertEquals(100, output.height)
    assertEquals(200, output.sourceWidth)
    assertEquals(100, output.sourceHeight)

    val left = decode(output.urls[0])
    val right = decode(output.urls[1])
    assertNotNull(left)
    assertNotNull(right)
    assertEquals(100, left!!.width)
    assertEquals(100, left.height)
    assertEquals(100, right!!.width)
    assertEquals(100, right.height)
    assertReddish(left.getPixel(20, 20))
    assertBluish(right.getPixel(20, 20))
    left.recycle()
    right.recycle()
  }

  @Test
  fun rotatesWidePagesInBothDirections() {
    val context = RuntimeEnvironment.getApplication()
    val file = copyResource(context, "lanlu-wide-test.png")
    val uri = "file://${file.absolutePath}"

    val clockwise = WidePageService.create(context, uri, emptyMap(), "rotate", false)
    assertEquals(1, clockwise.urls.size)
    assertEquals("rotate", clockwise.mode)
    assertEquals(100, clockwise.width)
    assertEquals(200, clockwise.height)
    val cw = decode(clockwise.urls[0])
    assertNotNull(cw)
    assertEquals(100, cw!!.width)
    assertEquals(200, cw.height)
    // Clockwise: the left (red) half becomes the top half.
    assertReddish(cw.getPixel(20, 20))
    assertBluish(cw.getPixel(20, 160))
    cw.recycle()

    val counterClockwise = WidePageService.create(context, uri, emptyMap(), "rotate", true)
    val ccw = decode(counterClockwise.urls[0])
    assertNotNull(ccw)
    // Counter-clockwise: the left (red) half becomes the bottom half.
    assertBluish(ccw!!.getPixel(20, 20))
    assertReddish(ccw.getPixel(20, 160))
    ccw.recycle()
  }

  private fun copyResource(context: Application, name: String): File {
    val stream = javaClass.classLoader!!.getResourceAsStream(name)
      ?: error("$name missing from test resources")
    val file = File(context.cacheDir, name)
    stream.use { input -> file.outputStream().use { output -> input.copyTo(output) } }
    return file
  }

  private fun decode(url: String): Bitmap? {
    val path = Uri.parse(url).path ?: return null
    return BitmapFactory.decodeFile(path)
  }

  private fun assertReddish(pixel: Int) {
    assertTrue(
      "expected red pixel, got ${Integer.toHexString(pixel)}",
      Color.red(pixel) > 160 && Color.blue(pixel) < 100,
    )
  }

  private fun assertBluish(pixel: Int) {
    assertTrue(
      "expected blue pixel, got ${Integer.toHexString(pixel)}",
      Color.blue(pixel) > 160 && Color.red(pixel) < 100,
    )
  }
}
