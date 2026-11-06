package com.lanluclient

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.view.View
import android.view.View.MeasureSpec
import android.widget.FrameLayout
import org.junit.Assert.assertEquals
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
class LanluColorFilterViewTest {

  @Test
  fun appliesGrayscaleAndInvertToChildren() {
    val view = createRedChildView()
    val bitmap = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    view.draw(canvas)
    assertEquals(Color.RED, bitmap.getPixel(50, 50))

    view.setGrayscale(true)
    view.draw(canvas)
    val gray = bitmap.getPixel(50, 50)
    assertTrue("expected gray, got ${Integer.toHexString(gray)}", red(gray) < 90)
    assertTrue(Math.abs(red(gray) - green(gray)) <= 2)
    assertTrue(Math.abs(green(gray) - blue(gray)) <= 2)

    view.setGrayscale(false)
    view.setInvertColors(true)
    view.draw(canvas)
    val inverted = bitmap.getPixel(50, 50)
    assertTrue("expected inverted red, got ${Integer.toHexString(inverted)}", red(inverted) < 10)
    assertTrue(green(inverted) > 240)
    assertTrue(blue(inverted) > 240)
  }

  @Test
  fun scalesBrightness() {
    val view = createRedChildView()
    val bitmap = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)

    view.setBrightness(0.5f)
    view.draw(canvas)
    val dimmed = bitmap.getPixel(50, 50)
    assertTrue("expected dimmed red, got ${Integer.toHexString(dimmed)}", red(dimmed) in 110..145)

    view.setBrightness(1.5f)
    view.draw(canvas)
    val bright = bitmap.getPixel(50, 50)
    assertEquals(255, red(bright))
  }

  private fun createRedChildView(): LanluColorFilterView {
    val context = RuntimeEnvironment.getApplication()
    val view = LanluColorFilterView(context)
    val child = View(context)
    child.setBackgroundColor(Color.RED)
    view.addView(child, FrameLayout.LayoutParams(100, 100))
    view.measure(
      MeasureSpec.makeMeasureSpec(100, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(100, MeasureSpec.EXACTLY),
    )
    view.layout(0, 0, 100, 100)
    return view
  }

  private fun red(color: Int) = (color shr 16) and 0xFF

  private fun green(color: Int) = (color shr 8) and 0xFF

  private fun blue(color: Int) = color and 0xFF
}
