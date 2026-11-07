package com.lanluclient

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Canvas
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.Rect
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.View.MeasureSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private const val EVENT_NAME = "LanluLongImageEvent"
private const val MAX_CACHED_STRIPS = 4
private const val MAX_FALLBACK_DIMENSION = 4096
private const val MAX_CACHE_BYTES = 384L * 1024 * 1024
private const val DOWNLOAD_CONCURRENCY = 4
private const val DECODE_CONCURRENCY = 2

/**
 * Long webtoon pages are downloaded once, kept in a file cache and decoded as
 * visible horizontal strips with [BitmapRegionDecoder]. Only the strips around
 * the viewport are kept as bitmaps, so a very tall page never becomes one
 * oversized GPU texture or one giant allocation.
 */
class LanluLongImageView(context: Context) : View(context) {

  private val mainHandler = Handler(Looper.getMainLooper())
  private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
  private val decoderLock = Any()
  private val strips = LinkedHashMap<Int, Bitmap>(8, 0.75f, true)
  private val pendingStrips = HashSet<Int>()

  @Volatile private var loadGeneration = 0
  @Volatile private var isAttached = false

  private var handle = ""
  private var ready = false
  private var fallbackAspectRatio = 0.72f
  private var cropBorders = false
  private var grayscale = false
  private var invertColors = false
  private var brightness = 1f
  private var pendingUri: String? = null
  private var pendingHeaders: Map<String, String> = emptyMap()
  private var sourceUri: String? = null
  private var sourceHeaders: Map<String, String> = emptyMap()
  private var started = false

  private var sourceWidth = 0
  private var sourceHeight = 0
  private var sourceLeft = 0
  private var sourceTop = 0
  private var sampleSize = 1
  private var scaledWidth = 0
  private var scaledHeight = 0
  private var scale = 1f
  private var stripScaledHeight = LongImageGeometry.MIN_STRIP_HEIGHT
  private var viewWidth = 0
  private var loadedEmitted = false
  private var errorMessage: String? = null
  private var decoder: BitmapRegionDecoder? = null
  private var fallbackBitmap: Bitmap? = null

  internal var debugDecodedStripCount = 0
    private set
  internal var debugScheduledStripCount = 0
    private set
  @Volatile internal var debugDecodeResultCount = 0
    private set
  @Volatile internal var debugDrawCount = 0
    private set

  internal fun debugSettledForTest(): Boolean =
    debugDecodedStripCount > 0 || fallbackBitmap != null || errorMessage != null

  internal fun debugHasFallbackForTest(): Boolean = fallbackBitmap != null

  internal fun debugStateForTest(): String = buildString {
    append("started=").append(started)
    append(" ready=").append(ready)
    append(" uri=").append(sourceUri)
    append(" size=").append(sourceWidth).append('x').append(sourceHeight)
    append(" decoder=").append(decoder != null)
    append(" fallback=").append(fallbackBitmap != null)
    append(" error=").append(errorMessage)
    append(" draws=").append(debugDrawCount)
    append(" scheduled=").append(debugScheduledStripCount)
    append(" decoded=").append(debugDecodeResultCount)
    append(" strips=").append(debugDecodedStripCount)
  }

  internal fun onDetachedFromWindowForTest() {
    onDetachedFromWindow()
  }

  internal fun onAttachedToWindowForTest() {
    onAttachedToWindow()
  }

  private val stripCount: Int
    get() = LongImageGeometry.stripCount(scaledHeight, stripScaledHeight)

  fun setHandle(value: String) {
    if (handle == value) return
    handle = value
    maybeStart()
  }

  fun setReady(value: Boolean) {
    if (ready == value) return
    ready = value
    maybeStart()
  }

  fun setFallbackAspectRatio(value: Float) {
    val next = value.coerceIn(0.05f, 4f)
    if (fallbackAspectRatio == next) return
    fallbackAspectRatio = next
    requestLayout()
    invalidate()
  }

  fun setCropBorders(value: Boolean) {
    if (cropBorders == value) return
    cropBorders = value
    if (started) {
      resetForSourceChange()
    }
    maybeStart()
  }

  fun setGrayscale(value: Boolean) {
    if (grayscale == value) return
    grayscale = value
    updateColorFilter()
  }

  fun setInvertColors(value: Boolean) {
    if (invertColors == value) return
    invertColors = value
    updateColorFilter()
  }

  fun setBrightness(value: Float) {
    val next = value.coerceIn(0.2f, 2f)
    if (brightness == next) return
    brightness = next
    updateColorFilter()
  }

  private fun updateColorFilter() {
    paint.colorFilter =
      ReaderColorFilter.build(grayscale, invertColors, brightness)?.let { ColorMatrixColorFilter(it) }
    invalidate()
  }

  fun setSource(uri: String?, headers: Map<String, String>) {
    if (uri == pendingUri && headers == pendingHeaders) return
    pendingUri = uri?.takeIf { it.isNotBlank() }
    pendingHeaders = headers
    if (started) {
      resetForSourceChange()
    }
    maybeStart()
  }

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    isAttached = true
    maybeStart()
    invalidate()
  }

  override fun onDetachedFromWindow() {
    isAttached = false
    clearStrips()
    super.onDetachedFromWindow()
  }

  private fun maybeStart() {
    val uri = pendingUri
    if (started || !ready || uri.isNullOrBlank() || handle.isEmpty()) return
    started = true
    sourceUri = uri
    sourceHeaders = pendingHeaders
    startLoad()
  }

  private fun resetForSourceChange() {
    loadGeneration++
    synchronized(decoderLock) {
      decoder?.recycle()
      decoder = null
    }
    fallbackBitmap?.recycle()
    fallbackBitmap = null
    clearStrips()
    sourceWidth = 0
    sourceHeight = 0
    sourceLeft = 0
    sourceTop = 0
    sampleSize = 1
    scaledWidth = 0
    scaledHeight = 0
    scale = 1f
    loadedEmitted = false
    errorMessage = null
    started = false
    requestLayout()
    invalidate()
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    val width = MeasureSpec.getSize(widthMeasureSpec)
    val height = if (scaledWidth > 0 && scaledHeight > 0) {
      max(1, (width * scaledHeight.toFloat() / scaledWidth).roundToInt())
    } else {
      max(1, (width / fallbackAspectRatio).roundToInt())
    }
    setMeasuredDimension(width, height)
  }

  override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
    super.onSizeChanged(width, height, oldWidth, oldHeight)
    if (width <= 0 || width == viewWidth) return
    val hadWidth = viewWidth > 0
    viewWidth = width
    if (sourceWidth > 0 && sourceHeight > 0) {
      recomputeMetrics(width)
      if (hadWidth) {
        requestLayout()
      }
    }
    invalidate()
  }

  private fun startLoad() {
    val uri = sourceUri ?: return
    val headers = sourceHeaders
    loadGeneration++
    val generation = loadGeneration
    loadedEmitted = false
    errorMessage = null
    emitEvent("loadStart")

    LanluLongImageStore.download {
      try {
        val file = LanluLongImageStore.fetch(context, uri, headers) { loaded, total ->
          if (generation != loadGeneration) return@fetch
          mainHandler.post {
            if (generation != loadGeneration) return@post
            emitEvent("progress") {
              putDouble("loaded", loaded.toDouble())
              putDouble("total", total.toDouble())
            }
          }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
          throw IOException("Unsupported or empty image")
        }
        val crop = detectCropBox(file, bounds.outWidth, bounds.outHeight, cropBorders)
        val regionDecoder = openRegionDecoder(file)
        mainHandler.post {
          if (generation != loadGeneration) {
            synchronized(decoderLock) { regionDecoder?.recycle() }
            return@post
          }
          sourceLeft = crop.left
          sourceTop = crop.top
          sourceWidth = crop.width
          sourceHeight = crop.height
          if (sourceWidth <= 0 || sourceHeight <= 0) {
            sourceLeft = 0
            sourceTop = 0
            sourceWidth = bounds.outWidth
            sourceHeight = bounds.outHeight
          }
          val width = if (viewWidth > 0) viewWidth else context.resources.displayMetrics.widthPixels
          if (regionDecoder == null) {
            openFallback(file, width, generation)
          } else {
            synchronized(decoderLock) {
              decoder?.recycle()
              decoder = regionDecoder
            }
            recomputeMetrics(width)
            emitSize()
            requestLayout()
            invalidate()
          }
        }
      } catch (error: Throwable) {
        mainHandler.post {
          if (generation == loadGeneration) {
            fail(error.message ?: error.javaClass.simpleName)
          }
        }
      }
    }
  }

  @Suppress("DEPRECATION")
  private fun openRegionDecoder(file: File): BitmapRegionDecoder? =
    try {
      BitmapRegionDecoder.newInstance(file.absolutePath, false)
    } catch (_: Throwable) {
      null
    }

  private fun detectCropBox(
    file: File,
    originalWidth: Int,
    originalHeight: Int,
    enabled: Boolean,
  ): LongImageGeometry.CropBox {
    val full = LongImageGeometry.CropBox(0, 0, originalWidth, originalHeight)
    if (!enabled || originalWidth < 8 || originalHeight < 8) return full

    val thumb = try {
      var sample = 1
      while (
        (originalWidth / sample).toLong() * (originalHeight / sample) > 262_144L &&
        sample < 32
      ) {
        sample *= 2
      }
      while (originalWidth / sample < 16 && sample > 1) {
        sample /= 2
      }
      BitmapFactory.decodeFile(
        file.absolutePath,
        BitmapFactory.Options().apply {
          inSampleSize = sample
          inPreferredConfig = Bitmap.Config.ARGB_8888
        },
      )
    } catch (_: Throwable) {
      null
    } ?: return full

    val thumbWidth = thumb.width
    val thumbHeight = thumb.height
    if (thumbWidth <= 2 || thumbHeight <= 2) {
      thumb.recycle()
      return full
    }
    val pixels = IntArray(thumbWidth * thumbHeight)
    thumb.getPixels(pixels, 0, thumbWidth, 0, 0, thumbWidth, thumbHeight)
    val box = LongImageGeometry.detectCropBox(pixels, thumbWidth, thumbHeight)
    thumb.recycle()

    if (box.left == 0 && box.top == 0 && box.right == thumbWidth && box.bottom == thumbHeight) {
      return full
    }
    val left = (box.left.toLong() * originalWidth / thumbWidth).toInt().coerceIn(0, originalWidth - 2)
    val top = (box.top.toLong() * originalHeight / thumbHeight).toInt().coerceIn(0, originalHeight - 2)
    val right = ((box.right.toLong() * originalWidth + thumbWidth - 1) / thumbWidth)
      .toInt()
      .coerceIn(left + 2, originalWidth)
    val bottom = ((box.bottom.toLong() * originalHeight + thumbHeight - 1) / thumbHeight)
      .toInt()
      .coerceIn(top + 2, originalHeight)
    return LongImageGeometry.CropBox(left, top, right, bottom)
  }

  private fun cropBitmapIfNeeded(bitmap: Bitmap): Bitmap {
    if (
      !cropBorders ||
      bitmap.width <= 2 ||
      bitmap.height <= 2 ||
      bitmap.width.toLong() * bitmap.height > 4_000_000L
    ) {
      return bitmap
    }
    val pixels = IntArray(bitmap.width * bitmap.height)
    bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
    val box = LongImageGeometry.detectCropBox(pixels, bitmap.width, bitmap.height)
    if (box.left == 0 && box.top == 0 && box.right == bitmap.width && box.bottom == bitmap.height) {
      return bitmap
    }
    return try {
      val cropped = Bitmap.createBitmap(bitmap, box.left, box.top, box.width, box.height)
      if (cropped !== bitmap) bitmap.recycle()
      cropped
    } catch (_: Throwable) {
      bitmap
    }
  }

  private fun openFallback(file: File, width: Int, generation: Int) {
    LanluLongImageStore.decode {
      val bitmap = decodeFallback(file, width)
      mainHandler.post {
        if (generation != loadGeneration) {
          bitmap?.recycle()
          return@post
        }
        if (bitmap == null) {
          fail("Unsupported image format")
          return@post
        }
        fallbackBitmap?.recycle()
        fallbackBitmap = bitmap
        recomputeMetrics(width)
        emitSize()
        requestLayout()
        invalidate()
        if (!loadedEmitted) {
          loadedEmitted = true
          emitEvent("load")
        }
      }
    }
  }

  private fun decodeFallback(file: File, width: Int): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.absolutePath, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

    var sample = 1
    val reasonableWidth = max(width * 2, 720)
    while (bounds.outWidth / sample > reasonableWidth && sample < 16) {
      sample *= 2
    }
    while (bounds.outHeight / sample > MAX_FALLBACK_DIMENSION && sample < 64) {
      sample *= 2
    }
    val options = BitmapFactory.Options().apply {
      inSampleSize = sample
      inPreferredConfig = Bitmap.Config.ARGB_8888
    }
    return try {
      BitmapFactory.decodeFile(file.absolutePath, options)?.let(::cropBitmapIfNeeded)
    } catch (_: Throwable) {
      null
    }
  }

  private fun recomputeMetrics(width: Int) {
    if (sourceWidth <= 0 || sourceHeight <= 0 || width <= 0) return
    sampleSize = LongImageGeometry.sampleSize(sourceWidth, width)
    scaledWidth = max(1, ceil(sourceWidth.toDouble() / sampleSize).toInt())
    scaledHeight = max(1, ceil(sourceHeight.toDouble() / sampleSize).toInt())
    scale = width.toFloat() / scaledWidth
    stripScaledHeight = LongImageGeometry.stripScaledHeight(scaledWidth)
    clearStrips()
  }

  private fun emitSize() {
    emitEvent("size") {
      putDouble("width", sourceWidth.toDouble())
      putDouble("height", sourceHeight.toDouble())
      if (viewWidth > 0) {
        putDouble("viewWidth", viewWidth.toDouble())
        putDouble(
          "viewHeight",
          (viewWidth * sourceHeight.toFloat() / max(1, sourceWidth)).toDouble(),
        )
      }
    }
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    debugDrawCount++
    val width = viewWidth
    if (width <= 0) return
    val viewHeight = height

    fallbackBitmap?.let { bitmap ->
      canvas.drawBitmap(bitmap, null, Rect(0, 0, width, viewHeight), paint)
      return
    }

    val activeDecoder = synchronized(decoderLock) { decoder }
    if (activeDecoder == null || scaledWidth <= 0 || stripCount <= 0) return

    val clip = Rect()
    canvas.getClipBounds(clip)
    if (clip.isEmpty) clip.set(0, 0, width, viewHeight)
    val first = (clip.top / scale / stripScaledHeight).toInt().coerceIn(0, stripCount - 1)
    val last = (clip.bottom / scale / stripScaledHeight).toInt().coerceIn(first, stripCount - 1)

    var drewAny = false
    for (index in first..last) {
      val bitmap = strips[index]
      if (bitmap == null) {
        scheduleStrip(index)
        continue
      }
      val top = (index * stripScaledHeight * scale).roundToInt()
      val bottom = (min(scaledHeight, (index + 1) * stripScaledHeight) * scale).roundToInt()
      canvas.drawBitmap(bitmap, null, Rect(0, top, width, bottom), paint)
      drewAny = true
    }
    scheduleStrip(last + 1)
    if (!loadedEmitted && drewAny) {
      loadedEmitted = true
      emitEvent("load")
    }
  }

  private fun scheduleStrip(index: Int) {
    if (index < 0 || index >= stripCount) return
    if (strips.containsKey(index) || !pendingStrips.add(index)) return
    val activeDecoder = synchronized(decoderLock) { decoder }
    if (activeDecoder == null) {
      pendingStrips.remove(index)
      return
    }
    val generation = loadGeneration
    val sample = sampleSize
    val stripHeight = stripScaledHeight
    val stripSourceTop = sourceTop + index * stripHeight * sample
    val stripSourceBottom = min(
      sourceTop + sourceHeight,
      sourceTop + (index + 1) * stripHeight * sample,
    )
    if (stripSourceBottom <= stripSourceTop) {
      pendingStrips.remove(index)
      return
    }
    val region = Rect(sourceLeft, stripSourceTop, sourceLeft + sourceWidth, stripSourceBottom)
    debugScheduledStripCount++
    val options = BitmapFactory.Options().apply {
      inSampleSize = sample
      inPreferredConfig = Bitmap.Config.ARGB_8888
    }

    LanluLongImageStore.decode {
      val bitmap = synchronized(decoderLock) {
        if (generation != loadGeneration || activeDecoder !== decoder) {
          null
        } else {
          try {
            activeDecoder.decodeRegion(region, options)
          } catch (_: Throwable) {
            null
          }
        }
      }
      debugDecodeResultCount++
      mainHandler.post {
        pendingStrips.remove(index)
        if (bitmap == null) {
          if (generation == loadGeneration && isAttached && strips.isEmpty() && errorMessage == null) {
            fail("Image strip decode failed")
          }
          return@post
        }
        if (generation != loadGeneration || !isAttached) {
          bitmap.recycle()
          return@post
        }
        putStrip(index, bitmap)
        invalidate()
      }
    }
  }

  private fun putStrip(index: Int, bitmap: Bitmap) {
    strips[index] = bitmap
    debugDecodedStripCount++
    while (strips.size > MAX_CACHED_STRIPS) {
      val iterator = strips.entries.iterator()
      if (!iterator.hasNext()) break
      val eldest = iterator.next()
      eldest.value.recycle()
      iterator.remove()
    }
  }

  private fun clearStrips() {
    for (bitmap in strips.values) {
      bitmap.recycle()
    }
    strips.clear()
    pendingStrips.clear()
  }

  private fun fail(message: String) {
    if (errorMessage == message) return
    errorMessage = message
    emitEvent("error") {
      putString("message", message)
    }
    invalidate()
  }

  private fun emitEvent(type: String, buildPayload: (WritableMap.() -> Unit)? = null) {
    // ThemedReactContext inherits ReactContext.emitDeviceEvent(), which resolves
    // RCTDeviceEventEmitter through getJSModule and is unreliable under
    // bridgeless. BridgelessReactContext overrides it with a direct JS call.
    val themed = context as? ThemedReactContext
    val target: ReactContext =
      themed?.reactApplicationContext ?: (context as? ReactContext ?: return)
    val event = Arguments.createMap()
    event.putString("handle", handle)
    event.putString("type", type)
    if (buildPayload != null) {
      val payload = Arguments.createMap()
      payload.buildPayload()
      event.putMap("payload", payload)
    }
    try {
      target.emitDeviceEvent(EVENT_NAME, event)
    } catch (_: Throwable) {
      // The React instance can be gone while a download finishes during exit.
    }
  }
}

class LanluLongImageViewManager : SimpleViewManager<LanluLongImageView>() {

  override fun getName(): String = "LanluLongImage"

  override fun createViewInstance(reactContext: ThemedReactContext): LanluLongImageView =
    LanluLongImageView(reactContext)

  @ReactProp(name = "source")
  fun setSource(view: LanluLongImageView, source: ReadableMap?) {
    if (source == null) {
      view.setSource(null, emptyMap())
      return
    }
    val uri = if (source.hasKey("uri") && !source.isNull("uri")) source.getString("uri") else null
    val headers = mutableMapOf<String, String>()
    if (source.hasKey("headers") && !source.isNull("headers")) {
      val headerMap = source.getMap("headers")
      headerMap?.let { map ->
        val iterator = map.keySetIterator()
        while (iterator.hasNextKey()) {
          val key = iterator.nextKey()
          if (map.hasKey(key) && !map.isNull(key)) {
            map.getString(key)?.let { headers[key] = it }
          }
        }
      }
    }
    view.setSource(uri, headers)
  }

  @ReactProp(name = "handle")
  fun setHandle(view: LanluLongImageView, handle: String?) {
    view.setHandle(handle ?: "")
  }

  @ReactProp(name = "ready")
  fun setReady(view: LanluLongImageView, ready: Boolean) {
    view.setReady(ready)
  }

  @ReactProp(name = "fallbackAspectRatio", defaultFloat = 0.72f)
  fun setFallbackAspectRatio(view: LanluLongImageView, ratio: Float) {
    view.setFallbackAspectRatio(ratio)
  }

  @ReactProp(name = "cropBorders", defaultBoolean = false)
  fun setCropBorders(view: LanluLongImageView, cropBorders: Boolean) {
    view.setCropBorders(cropBorders)
  }

  @ReactProp(name = "grayscale", defaultBoolean = false)
  fun setGrayscale(view: LanluLongImageView, grayscale: Boolean) {
    view.setGrayscale(grayscale)
  }

  @ReactProp(name = "invertColors", defaultBoolean = false)
  fun setInvertColors(view: LanluLongImageView, invertColors: Boolean) {
    view.setInvertColors(invertColors)
  }

  @ReactProp(name = "brightness", defaultFloat = 1f)
  fun setBrightness(view: LanluLongImageView, brightness: Float) {
    view.setBrightness(brightness)
  }
}

internal object LanluLongImageStore {

  private val client = OkHttpClient.Builder()
    .connectTimeout(20, TimeUnit.SECONDS)
    .readTimeout(120, TimeUnit.SECONDS)
    .followRedirects(true)
    .build()

  private val downloadExecutor: ExecutorService = daemonPool("lanlu-long-download", DOWNLOAD_CONCURRENCY)
  private val decodeExecutor: ExecutorService = daemonPool("lanlu-long-decode", DECODE_CONCURRENCY)
  private val locks = ConcurrentHashMap<String, Any>()
  private val dirLock = Any()

  @Volatile private var cacheDir: File? = null

  private fun daemonPool(name: String, size: Int): ExecutorService =
    Executors.newFixedThreadPool(size) { runnable ->
      Thread(runnable, name).apply { isDaemon = true }
    }

  fun download(runnable: Runnable) {
    downloadExecutor.execute(runnable)
  }

  fun prefetch(context: Context, uri: String, headers: Map<String, String>) {
    download {
      try {
        fetch(context, uri, headers) { _, _ -> }
      } catch (_: Throwable) {
        // Prefetch is best-effort; the visible page will retry on mount.
      }
    }
  }

  fun decode(runnable: Runnable) {
    decodeExecutor.execute(runnable)
  }

  fun fetch(
    context: Context,
    uri: String,
    headers: Map<String, String>,
    onProgress: (Long, Long) -> Unit,
  ): File {
    if (uri.startsWith("file://")) {
      val path = Uri.parse(uri).path ?: throw IOException("Invalid file URI")
      val file = File(path)
      if (!file.exists() || file.length() <= 0) throw IOException("Image file not found")
      return file
    }

    val dir = ensureCacheDir(context)
    val key = cacheKey(uri, headers)
    val target = File(dir, "$key.bin")
    if (target.exists() && target.length() > 0) return target

    val lock = locks.getOrPut(key) { Any() }
    synchronized(lock) {
      if (target.exists() && target.length() > 0) return target
      val temp = File(dir, "$key.tmp")
      try {
        if (uri.startsWith("content://")) {
          val input = context.contentResolver.openInputStream(Uri.parse(uri))
            ?: throw IOException("Unable to open image URI")
          input.use { source ->
            temp.outputStream().use { output ->
              copyWithProgress(source, output, -1L, onProgress)
            }
          }
        } else {
          val builder = Request.Builder().url(uri)
          headers.forEach { (name, value) ->
            if (value.isNotBlank()) builder.header(name, value)
          }
          client.newCall(builder.build()).execute().use { response ->
            if (!response.isSuccessful) {
              throw IOException("HTTP ${response.code}")
            }
            val body = response.body ?: throw IOException("Empty image response")
            body.byteStream().use { source ->
              temp.outputStream().use { output ->
                copyWithProgress(source, output, body.contentLength(), onProgress)
              }
            }
          }
        }
        if (!temp.renameTo(target)) {
          temp.copyTo(target, overwrite = true)
          temp.delete()
        }
        trimCache(dir)
        return target
      } catch (error: Throwable) {
        temp.delete()
        throw error
      } finally {
        locks.remove(key)
      }
    }
  }

  private fun ensureCacheDir(context: Context): File {
    cacheDir?.let { if (it.exists()) return it }
    synchronized(dirLock) {
      cacheDir?.let { if (it.exists()) return it }
      val dir = File(context.applicationContext.cacheDir, "lanlu_long_images")
      if (!dir.exists()) dir.mkdirs()
      cacheDir = dir
      return dir
    }
  }

  private fun cacheKey(uri: String, headers: Map<String, String>): String {
    val headerPart = headers.toSortedMap().entries.joinToString("\u0000") { "${it.key}:${it.value}" }
    val digest = MessageDigest.getInstance("SHA-256")
      .digest("$uri\u0000$headerPart".toByteArray(Charsets.UTF_8))
    val builder = StringBuilder(digest.size * 2)
    for (byte in digest) {
      builder.append(String.format("%02x", byte))
    }
    return builder.toString()
  }

  private fun copyWithProgress(
    input: InputStream,
    output: OutputStream,
    total: Long,
    onProgress: (Long, Long) -> Unit,
  ) {
    val buffer = ByteArray(64 * 1024)
    var loaded = 0L
    var lastReport = 0L
    onProgress(0L, total)
    while (true) {
      val read = input.read(buffer)
      if (read <= 0) break
      output.write(buffer, 0, read)
      loaded += read
      val now = System.currentTimeMillis()
      if (now - lastReport >= 200 || (total > 0 && loaded >= total)) {
        lastReport = now
        onProgress(loaded, total)
      }
    }
    onProgress(loaded, total)
  }

  private fun trimCache(dir: File) {
    val files = dir.listFiles { file ->
      file.isFile && file.name.endsWith(".bin")
    } ?: return
    var total = files.sumOf { it.length() }
    if (total <= MAX_CACHE_BYTES) return
    val target = (MAX_CACHE_BYTES * 3) / 4
    for (file in files.sortedBy { it.lastModified() }) {
      if (total <= target) break
      val length = file.length()
      if (file.delete()) total -= length
    }
  }
}
