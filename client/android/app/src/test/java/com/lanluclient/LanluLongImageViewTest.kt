package com.lanluclient

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.view.View.MeasureSpec
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Device-free smoke tests for the strip decoder. They exercise measure, layout
 * and draw with real PNGs, and let Robolectric's main looper run the posts from
 * the download/decode executors.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LanluLongImageViewTest {

  @Test
  fun measuresFallbackAspectWithoutSource() {
    val view = LanluLongImageView(RuntimeEnvironment.getApplication())
    view.setHandle("measure")
    measureAndLayout(view, 1080)

    assertEquals(1080, view.measuredWidth)
    assertEquals(1500, view.measuredHeight)

    val bitmap = Bitmap.createBitmap(1080, 1500, Bitmap.Config.ARGB_8888)
    view.draw(Canvas(bitmap))
    assertEquals(1080, bitmap.width)
  }

  @Test
  fun loadsLongPngAndDrawsVisibleStripsWithoutCrashing() {
    val context = RuntimeEnvironment.getApplication()
    val view = createLoadingView(context, "lanlu-long-test.png", "strips")
    val canvas = Canvas(Bitmap.createBitmap(1080, 1200, Bitmap.Config.ARGB_8888))

    val settled = awaitSettle(view, canvas, "strip test")

    assertTrue("image load did not settle: ${view.debugStateForTest()}", settled)
    assertTrue(
      "expected a decoded strip or the fallback bitmap",
      view.debugDecodedStripCount > 0 || view.debugHasFallbackForTest(),
    )
    assertTrue("long page should be taller than the fallback", view.measuredHeight > 1500)
    view.onDetachedFromWindowForTest()
  }

  @Test
  fun cropsUniformBordersWhenEnabled() {
    val context = RuntimeEnvironment.getApplication()
    val view = createLoadingView(context, "lanlu-long-bordered.png", "cropped")
    view.setCropBorders(true)
    val canvas = Canvas(Bitmap.createBitmap(1080, 1200, Bitmap.Config.ARGB_8888))

    val settled = awaitSettle(view, canvas, "crop test")

    assertTrue("image load did not settle: ${view.debugStateForTest()}", settled)
    assertTrue("expected decoded strips", view.debugDecodedStripCount > 0)
    // 200x4000 with a 20px border crops to about 160x3960, which is ~26730px
    // tall at 1080px wide (uncropped would be 21600px).
    assertTrue(
      "expected cropped height, got ${view.measuredHeight}",
      view.measuredHeight > 24000,
    )
    view.onDetachedFromWindowForTest()
  }

  @Test
  fun sourceChangeAndDetachDoNotCrash() {
    val context = RuntimeEnvironment.getApplication()
    val view = LanluLongImageView(context)
    view.setHandle("detach")
    view.setSource("file:///does/not/exist.png", emptyMap())
    view.setReady(true)
    measureAndLayout(view, 1080)
    view.draw(Canvas(Bitmap.createBitmap(1080, 1200, Bitmap.Config.ARGB_8888)))

    shadowOf(Looper.getMainLooper()).idle()
    view.setSource(null, emptyMap())
    view.setFallbackAspectRatio(0.5f)
    measureAndLayout(view, 1080)
    assertEquals(1080, view.measuredWidth)
    assertEquals(2160, view.measuredHeight)

    // The load failure and the detach path must both be safe.
    shadowOf(Looper.getMainLooper()).idle()
    view.onDetachedFromWindowForTest()
    view.onAttachedToWindowForTest()
    view.draw(Canvas(Bitmap.createBitmap(1080, 1200, Bitmap.Config.ARGB_8888)))
  }

  private fun createLoadingView(
    context: Application,
    resource: String,
    handle: String,
  ): LanluLongImageView {
    val png = javaClass.classLoader!!.getResourceAsStream(resource)
      ?: error("$resource missing from test resources")
    val file = File(context.cacheDir, resource)
    png.use { input -> file.outputStream().use { output -> input.copyTo(output) } }

    val view = LanluLongImageView(context)
    view.setHandle(handle)
    view.setSource("file://${file.absolutePath}", emptyMap())
    view.setReady(true)
    view.onAttachedToWindowForTest()
    return view
  }

  private fun awaitSettle(
    view: LanluLongImageView,
    canvas: Canvas,
    label: String,
  ): Boolean {
    for (attempt in 0 until 1000) {
      shadowOf(Looper.getMainLooper()).idle()
      measureAndLayout(view, 1080)
      view.draw(canvas)
      if (view.debugSettledForTest()) {
        // Let the remaining strip decode posts land and draw the content.
        repeat(20) {
          shadowOf(Looper.getMainLooper()).idle()
          view.draw(canvas)
          Thread.sleep(5)
        }
        return true
      }
      if (attempt % 100 == 0) {
        println("$label attempt=$attempt ${view.debugStateForTest()}")
      }
      Thread.sleep(10)
    }
    return false
  }

  private fun measureAndLayout(view: LanluLongImageView, width: Int) {
    view.measure(
      MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
    )
    view.layout(0, 0, view.measuredWidth, view.measuredHeight)
  }
}
