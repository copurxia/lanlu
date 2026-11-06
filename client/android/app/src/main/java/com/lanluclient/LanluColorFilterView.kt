package com.lanluclient

import android.content.Context
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.widget.FrameLayout
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewGroupManager
import com.facebook.react.uimanager.annotations.ReactProp

/**
 * Container that applies a colour matrix to everything drawn by its children.
 * Used for paged FastImage content; the webtoon strip view applies the same
 * matrix directly to its paint.
 */
class LanluColorFilterView(context: Context) : FrameLayout(context) {

  private val paint = Paint()
  private var grayscale = false
  private var invertColors = false
  private var brightness = 1f
  private var matrix: ColorMatrix? = null

  fun setGrayscale(value: Boolean) {
    if (grayscale == value) return
    grayscale = value
    updateFilter()
  }

  fun setInvertColors(value: Boolean) {
    if (invertColors == value) return
    invertColors = value
    updateFilter()
  }

  fun setBrightness(value: Float) {
    val next = value.coerceIn(0.2f, 2f)
    if (brightness == next) return
    brightness = next
    updateFilter()
  }

  private fun updateFilter() {
    matrix = ReaderColorFilter.build(grayscale, invertColors, brightness)
    paint.colorFilter = matrix?.let { ColorMatrixColorFilter(it) }
    invalidate()
  }

  override fun dispatchDraw(canvas: Canvas) {
    val filter = paint.colorFilter
    if (filter == null) {
      super.dispatchDraw(canvas)
      return
    }
    val save = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), paint)
    super.dispatchDraw(canvas)
    canvas.restoreToCount(save)
  }
}

class LanluColorFilterViewManager : ViewGroupManager<LanluColorFilterView>() {

  override fun getName(): String = "LanluColorFilterView"

  override fun createViewInstance(reactContext: ThemedReactContext): LanluColorFilterView =
    LanluColorFilterView(reactContext)

  @ReactProp(name = "grayscale", defaultBoolean = false)
  fun setGrayscale(view: LanluColorFilterView, value: Boolean) {
    view.setGrayscale(value)
  }

  @ReactProp(name = "invertColors", defaultBoolean = false)
  fun setInvertColors(view: LanluColorFilterView, value: Boolean) {
    view.setInvertColors(value)
  }

  @ReactProp(name = "brightness", defaultFloat = 1f)
  fun setBrightness(view: LanluColorFilterView, value: Float) {
    view.setBrightness(value)
  }
}
