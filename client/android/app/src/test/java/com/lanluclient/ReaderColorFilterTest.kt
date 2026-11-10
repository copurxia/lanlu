package com.lanluclient

import android.graphics.ColorMatrix
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = android.app.Application::class)
class ReaderColorFilterTest {

  @Test
  fun returnsNullForIdentitySettings() {
    assertNull(ReaderColorFilter.build(false, false, 1f))
  }

  @Test
  fun buildsGrayscaleMatrix() {
    val matrix = ReaderColorFilter.build(true, false, 1f)
    assertNotNull(matrix)
    val values = matrix!!.getArray()
    assertEquals(0.213f, values[0], 0.01f)
    assertEquals(0.715f, values[1], 0.01f)
    assertEquals(0.072f, values[2], 0.01f)
    assertEquals(values[0], values[5], 0.001f)
    assertEquals(values[1], values[6], 0.001f)
  }

  @Test
  fun buildsInvertMatrix() {
    val matrix = ReaderColorFilter.build(false, true, 1f)
    assertNotNull(matrix)
    val values = matrix!!.getArray()
    assertEquals(-1f, values[0], 0.001f)
    assertEquals(255f, values[4], 0.001f)
    assertEquals(-1f, values[6], 0.001f)
    assertEquals(-1f, values[12], 0.001f)
  }

  @Test
  fun scalesForBrightness() {
    val matrix = ReaderColorFilter.build(false, false, 1.5f)
    assertNotNull(matrix)
    val values = matrix!!.getArray()
    assertEquals(1.5f, values[0], 0.001f)
    assertEquals(1.5f, values[6], 0.001f)
    assertEquals(1.5f, values[12], 0.001f)
    assertEquals(1f, values[18], 0.001f)
  }

  @Test
  fun combinesGrayscaleInvertAndBrightness() {
    val matrix: ColorMatrix = ReaderColorFilter.build(true, true, 0.8f)!!
    val values = matrix.getArray()
    // Inversion offsets survive the final brightness scale on the alpha row only.
    assertEquals(0.8f * -0.213f, values[0], 0.01f)
    assertEquals(0.8f * 255f, values[4], 0.5f)
  }
}
