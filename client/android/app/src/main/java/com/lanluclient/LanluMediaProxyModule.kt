package com.lanluclient

import android.content.ClipData
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import androidx.core.content.FileProvider
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.X509TrustManager
import okhttp3.Cache
import okhttp3.CacheControl
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class LanluMediaProxyModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

  private val uploadExecutor = Executors.newCachedThreadPool()

  override fun getName(): String = "LanluMediaProxy"

  @ReactMethod
  fun setSystemBarsHidden(hidden: Boolean, edgeToEdge: Boolean) {
    val activity = reactApplicationContext.currentActivity ?: return
    activity.runOnUiThread {
      val window = activity.window ?: return@runOnUiThread
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        window.setDecorFitsSystemWindows(!edgeToEdge)
        val controller = window.insetsController
        if (controller != null) {
          controller.systemBarsBehavior =
              WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
          if (hidden) {
            controller.hide(WindowInsets.Type.statusBars())
          } else {
            controller.show(WindowInsets.Type.statusBars())
          }
        }
      } else {
        val layoutFlags =
            if (edgeToEdge) {
              View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                  View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                  View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            } else {
              0
            }
        val immersiveFlags =
            if (hidden) {
              View.SYSTEM_UI_FLAG_FULLSCREEN or
                  View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            } else {
              0
            }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = layoutFlags or immersiveFlags
      }
    }
  }

  @ReactMethod
  fun createUrl(uri: String, headers: ReadableMap?, compress: Boolean, promise: Promise) {
    try {
      val id = ProxyServer.cacheKey(uri, headers, compress)
      val copiedHeaders = mutableMapOf<String, String>()
      headers?.let {
        val iterator = it.keySetIterator()
        while (iterator.hasNextKey()) {
          val key = iterator.nextKey()
          if (it.hasKey(key) && !it.isNull(key)) {
            copiedHeaders[key] = it.getString(key) ?: ""
          }
        }
      }
      val port = ProxyServer.register(reactApplicationContext, id, uri, copiedHeaders, compress)
      val encodedId = URLEncoder.encode(id, "UTF-8")
      promise.resolve("http://127.0.0.1:$port/media/$encodedId")
    } catch (error: Exception) {
      promise.reject("LANLU_MEDIA_PROXY", error)
    }
  }

  @ReactMethod
  fun createPageUrl(uri: String, headers: ReadableMap?, path: String, promise: Promise) {
    try {
      val id = UUID.randomUUID().toString()
      val copiedHeaders = mutableMapOf<String, String>()
      headers?.let {
        val iterator = it.keySetIterator()
        while (iterator.hasNextKey()) {
          val key = iterator.nextKey()
          if (it.hasKey(key) && !it.isNull(key)) {
            copiedHeaders[key] = it.getString(key) ?: ""
          }
        }
      }
      val port = ProxyServer.register(reactApplicationContext, id, uri, copiedHeaders)
      val encodedId = URLEncoder.encode(id, "UTF-8")
      promise.resolve("http://127.0.0.1:$port/page/$encodedId/${encodeLocalPath(path)}")
    } catch (error: Exception) {
      promise.reject("LANLU_PAGE_PROXY", error)
    }
  }

  @ReactMethod
  fun writeTextFile(extension: String, text: String, promise: Promise) {
    try {
      val safeExtension = extension
          .lowercase()
          .replace(Regex("[^a-z0-9]"), "")
          .ifBlank { "ass" }
      val directory = File(reactApplicationContext.cacheDir, "lanlu_subtitles")
      if (!directory.exists()) {
        directory.mkdirs()
      }
      val file = File(directory, "subtitle-${UUID.randomUUID()}.$safeExtension")
      file.writeText(text, Charsets.UTF_8)
      promise.resolve(Uri.fromFile(file).toString())
    } catch (error: Exception) {
      promise.reject("LANLU_SUBTITLE_FILE", error)
    }
  }

  @ReactMethod
  fun uploadFileChunk(
      sourceUri: String,
      targetUrl: String,
      headers: ReadableMap?,
      start: Double,
      length: Double,
      promise: Promise,
  ) {
    uploadExecutor.execute {
      var connection: HttpURLConnection? = null
      try {
        val chunkStart = start.toLong()
        val chunkLength = length.toLong()
        if (chunkStart < 0 || chunkLength <= 0) {
          promise.reject("LANLU_UPLOAD_CHUNK", "Invalid chunk range")
          return@execute
        }

        val uri = Uri.parse(sourceUri)
        val input = reactApplicationContext.contentResolver.openInputStream(uri)
            ?: throw IllegalArgumentException("Unable to open selected file")

        connection = URL(targetUrl).openConnection() as HttpURLConnection
        configureTlsIfNeeded(connection!!)
        connection!!.requestMethod = "PUT"
        connection!!.doOutput = true
        connection!!.instanceFollowRedirects = true
        connection!!.connectTimeout = 15000
        connection!!.readTimeout = 0
        connection!!.setRequestProperty("Content-Type", "application/octet-stream")
        headers?.let {
          val iterator = it.keySetIterator()
          while (iterator.hasNextKey()) {
            val key = iterator.nextKey()
            if (it.hasKey(key) && !it.isNull(key)) {
              val value = it.getString(key)
              if (!value.isNullOrBlank()) {
                connection!!.setRequestProperty(key, value)
              }
            }
          }
        }
        connection!!.setFixedLengthStreamingMode(chunkLength)

        input.use { stream ->
          skipFully(stream, chunkStart)
          connection!!.outputStream.use { output ->
            copyFixedLength(stream, output, chunkLength)
          }
        }

        val status = connection!!.responseCode
        val body = readResponseBody(connection!!)
        if (status in 200..299) {
          promise.resolve(body)
        } else {
          promise.reject("LANLU_UPLOAD_CHUNK_HTTP_$status", body.ifBlank { "HTTP $status" })
        }
      } catch (error: Exception) {
        promise.reject("LANLU_UPLOAD_CHUNK", error)
      } finally {
        connection?.disconnect()
      }
    }
  }

  @ReactMethod
  fun shareTextFile(extension: String, fileName: String, text: String, title: String, promise: Promise) {
    try {
      val safeExtension = sanitizeFilePart(extension, "txt")
      val safeFileName = sanitizeFilePart(fileName, "lanlu-log")
      val directory = File(reactApplicationContext.cacheDir, "lanlu_shared")
      if (!directory.exists()) {
        directory.mkdirs()
      }
      val file = File(directory, "$safeFileName-${System.currentTimeMillis()}.$safeExtension")
      file.writeText(text, Charsets.UTF_8)
      val uri = FileProvider.getUriForFile(
          reactApplicationContext,
          "${reactApplicationContext.packageName}.fileprovider",
          file,
      )
      val intent = Intent(Intent.ACTION_SEND).apply {
        type = if (safeExtension == "log" || safeExtension == "txt") "text/plain" else "application/octet-stream"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, title)
        clipData = ClipData.newUri(reactApplicationContext.contentResolver, file.name, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      }
      val chooser = Intent.createChooser(intent, title).apply {
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      }
      val activity = reactApplicationContext.currentActivity
      if (activity != null) {
        activity.startActivity(chooser)
      } else {
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        reactApplicationContext.startActivity(chooser)
      }
      promise.resolve(uri.toString())
    } catch (error: Exception) {
      promise.reject("LANLU_SHARE_TEXT_FILE", error)
    }
  }

  private fun sanitizeFilePart(value: String, fallback: String): String =
      value
          .lowercase()
          .replace(Regex("[^a-z0-9._-]"), "-")
          .trim('-', '.', '_')
          .ifBlank { fallback }

  private fun configureTlsIfNeeded(connection: HttpURLConnection) {
    if (connection !is HttpsURLConnection) return
    val trustAll = arrayOf<X509TrustManager>(
        object : X509TrustManager {
          override fun checkClientTrusted(
              chain: Array<java.security.cert.X509Certificate>?,
              authType: String?,
          ) {
          }

          override fun checkServerTrusted(
              chain: Array<java.security.cert.X509Certificate>?,
              authType: String?,
          ) {
          }

          override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> =
              emptyArray()
        },
    )
    val context = SSLContext.getInstance("TLS")
    context.init(null, trustAll, java.security.SecureRandom())
    connection.sslSocketFactory = context.socketFactory
    connection.hostnameVerifier = HostnameVerifier { _, _ -> true }
  }

  private fun encodeLocalPath(path: String): String =
      path.split("/")
          .filter { it.isNotEmpty() }
          .joinToString("/") { URLEncoder.encode(it, "UTF-8").replace("+", "%20") }

  private fun skipFully(input: InputStream, bytesToSkip: Long) {
    var remaining = bytesToSkip
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    while (remaining > 0) {
      val skipped = input.skip(remaining)
      if (skipped > 0) {
        remaining -= skipped
        continue
      }
      val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
      if (read < 0) {
        throw java.io.EOFException("Unable to skip to requested chunk offset")
      }
      remaining -= read.toLong()
    }
  }

  private fun copyFixedLength(input: InputStream, output: java.io.OutputStream, length: Long) {
    var remaining = length
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    while (remaining > 0) {
      val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
      if (read < 0) {
        throw java.io.EOFException("Selected file ended before chunk was complete")
      }
      output.write(buffer, 0, read)
      remaining -= read.toLong()
    }
  }

  private fun readResponseBody(connection: HttpURLConnection): String {
    val stream = try {
      connection.inputStream
    } catch (_: Exception) {
      connection.errorStream
    } ?: return ""
    stream.use {
      val out = ByteArrayOutputStream()
      val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
      while (true) {
        val read = it.read(buffer)
        if (read <= 0) break
        out.write(buffer, 0, read)
      }
      return out.toString("UTF-8")
    }
  }

  private data class ProxyTarget(val uri: String, val headers: Map<String, String>, val compress: Boolean = false)

  private object ProxyServer {
    private const val TAG = "LanluMediaProxy"
    private const val BUFFER_SIZE = 64 * 1024
    private const val COMPRESSED_IMAGE_MAX_WIDTH = 480
    private const val COMPRESSED_IMAGE_JPEG_QUALITY = 80
    private const val MEDIA_CACHE_SIZE_BYTES = 256L * 1024L * 1024L
    private val targets = ConcurrentHashMap<String, ProxyTarget>()
    private val trustManager = object : X509TrustManager {
      override fun checkClientTrusted(
          chain: Array<java.security.cert.X509Certificate>?,
          authType: String?,
      ) {
      }

      override fun checkServerTrusted(
          chain: Array<java.security.cert.X509Certificate>?,
          authType: String?,
      ) {
      }

      override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> =
          emptyArray()
    }
    private val sslSocketFactory: SSLSocketFactory by lazy {
      val context = SSLContext.getInstance("TLS")
      context.init(null, arrayOf<X509TrustManager>(trustManager), java.security.SecureRandom())
      context.socketFactory
    }
    private val trustAllHostnameVerifier = HostnameVerifier { _, _ -> true }
    @Volatile private var httpClient: OkHttpClient? = null

    // 同一原始 URI + 相同 compress 参数 → 相同代理路径，实现跨视图缓存共享
    fun cacheKey(uri: String, headers: ReadableMap?, compress: Boolean): String {
      val raw = buildString {
        append(uri)
        append("|")
        headers?.let {
          val iterator = it.keySetIterator()
          while (iterator.hasNextKey()) {
            val key = iterator.nextKey()
            if (it.hasKey(key) && !it.isNull(key)) append(it.getString(key))
          }
        }
        append("||compress=$compress")
      }
      val digest = MessageDigest.getInstance("SHA-256")
      return digest.digest(raw.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }

    private val executor = Executors.newCachedThreadPool()

    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var port: Int = 0

    @Synchronized
    fun register(
        context: ReactApplicationContext,
        id: String,
        uri: String,
        headers: Map<String, String>,
        compress: Boolean = false,
    ): Int {
      ensureHttpClient(context)
      ensureStarted()
      targets.putIfAbsent(id, ProxyTarget(uri, headers, compress))
      return port
    }

    @Synchronized
    private fun ensureHttpClient(context: ReactApplicationContext): OkHttpClient {
      httpClient?.let { return it }
      val cacheDir = File(context.cacheDir, "lanlu_media_proxy_okhttp")
      if (!cacheDir.exists()) {
        cacheDir.mkdirs()
      }
      val client = OkHttpClient.Builder()
          .cache(Cache(cacheDir, MEDIA_CACHE_SIZE_BYTES))
          .sslSocketFactory(sslSocketFactory, trustManager)
          .hostnameVerifier(trustAllHostnameVerifier)
          .connectTimeout(15, TimeUnit.SECONDS)
          .readTimeout(0, TimeUnit.MILLISECONDS)
          .followRedirects(true)
          .followSslRedirects(true)
          .addNetworkInterceptor { chain ->
            val response = chain.proceed(chain.request())
            val cacheControl = response.header("Cache-Control").orEmpty()
            if (cacheControl.contains("no-store", ignoreCase = true)) {
              response
            } else {
              response.newBuilder()
                  .header("Cache-Control", "public, max-age=86400")
                  .header("Vary", appendVary(response.header("Vary"), "Authorization"))
                  .build()
            }
          }
          .build()
      httpClient = client
      return client
    }

    @Synchronized
    private fun ensureStarted() {
      if (serverSocket != null) return
      val socket = ServerSocket(0)
      socket.reuseAddress = true
      serverSocket = socket
      port = socket.localPort
      executor.execute {
        while (!socket.isClosed) {
          try {
            val client = socket.accept()
            executor.execute { handleClient(client) }
          } catch (error: Exception) {
            if (!socket.isClosed) Log.e(TAG, "Accept failed", error)
          }
        }
      }
    }

    private fun handleClient(client: Socket) {
      client.use { socket ->
        try {
          socket.soTimeout = 15000
          val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.ISO_8859_1))
          val requestLine = reader.readLine() ?: return
          val parts = requestLine.split(" ")
          if (parts.size < 2) {
            writeText(socket, 400, "Bad Request")
            return
          }

          val method = parts[0].uppercase()
          val requestPath = parts[1]
          val requestHeaders = mutableMapOf<String, String>()
          while (true) {
            val line = reader.readLine() ?: break
            if (line.isEmpty()) break
            val separator = line.indexOf(':')
            if (separator > 0) {
              requestHeaders[line.substring(0, separator).trim().lowercase()] =
                  line.substring(separator + 1).trim()
            }
          }

          val isPageRequest = requestPath.startsWith("/page/")
          val encodedId = if (isPageRequest) {
            requestPath.removePrefix("/page/").substringBefore("/")
          } else {
            requestPath.substringAfter("/media/", "").substringBefore("?")
          }
          val id = URLDecoder.decode(encodedId, "UTF-8")
          val target = targets[id]
          if (target == null) {
            writeText(socket, 404, "Not Found")
            return
          }

          if (method != "GET" && method != "HEAD") {
            writeText(socket, 405, "Method Not Allowed")
            return
          }

          val pagePath = if (isPageRequest) {
            URLDecoder.decode(
                requestPath.removePrefix("/page/").substringAfter("/", "").substringBefore("?"),
                "UTF-8",
            )
          } else {
            null
          }
          proxyRequest(socket, method, target, requestHeaders, pagePath)
        } catch (error: Exception) {
          Log.e(TAG, "Proxy request failed", error)
          try {
            writeText(socket, 502, "Bad Gateway")
          } catch (_: Exception) {
          }
        }
      }
    }

    private fun proxyRequest(
        socket: Socket,
        method: String,
        target: ProxyTarget,
        requestHeaders: Map<String, String>,
    ) {
      proxyRequest(socket, method, target, requestHeaders, null)
    }

    private fun proxyRequest(
        socket: Socket,
        method: String,
        target: ProxyTarget,
        requestHeaders: Map<String, String>,
        pagePath: String?,
    ) {
      val targetUri = if (pagePath.isNullOrBlank()) {
        target.uri
      } else {
        Uri.parse(target.uri)
            .buildUpon()
            .clearQuery()
            .appendQueryParameter("path", pagePath)
            .build()
            .toString()
      }
      val client = httpClient ?: throw IllegalStateException("Proxy HTTP client is not initialized")
      val requestBuilder = Request.Builder()
          .url(targetUri)
          .method(method, null)
      target.headers.forEach { (key, value) ->
        if (value.isNotBlank()) requestBuilder.header(key, value)
      }
      requestHeaders["range"]?.let { requestBuilder.header("Range", it) }
      if (!target.headers.keys.any { it.equals("User-Agent", ignoreCase = true) }) {
        requestHeaders["user-agent"]?.let { requestBuilder.header("User-Agent", it) }
      }
      if (!pagePath.isNullOrBlank()) {
        requestBuilder.cacheControl(CacheControl.FORCE_NETWORK)
      }

      client.newCall(requestBuilder.build()).execute().use { response ->
        val status = response.code
        val output = socket.getOutputStream()
        output.write("HTTP/1.1 $status ${reasonPhrase(status)}\r\n".toByteArray(Charsets.ISO_8859_1))
        writeHeader(output, "Connection", "close")

        if (method == "HEAD") {
          copyResponseHeader(response.headers, output, "Content-Type")
          copyResponseHeader(response.headers, output, "Content-Length")
          copyResponseHeader(response.headers, output, "Content-Range")
          copyResponseHeader(response.headers, output, "Accept-Ranges")
          copyResponseHeader(response.headers, output, "ETag")
          copyResponseHeader(response.headers, output, "Cache-Control")
          output.write("\r\n".toByteArray(Charsets.ISO_8859_1))
          output.flush()
          return
        }

        val rawBody = response.body
        if (rawBody == null) {
          output.write("\r\n".toByteArray(Charsets.ISO_8859_1))
          output.flush()
          return
        }

        // 压缩：仅当 compress=true 且 Content-Type 为 image/* 时触发
        val contentType = response.header("Content-Type").orEmpty()
        val shouldCompress = target.compress && contentType.startsWith("image/", ignoreCase = true) &&
            !contentType.contains("svg", ignoreCase = true) &&
            !contentType.contains("gif", ignoreCase = true) &&
            requestHeaders["range"].isNullOrBlank()

        if (shouldCompress) {
          val sourceBytes = rawBody.bytes()
          val compressedBytes = try {
            compressImageBytes(sourceBytes)
          } catch (error: Exception) {
            Log.w(TAG, "Image recompress failed; falling back to passthrough", error)
            null
          }
          if (compressedBytes != null) {
            writeHeader(output, "Content-Type", "image/jpeg")
            writeHeader(output, "Content-Length", compressedBytes.size.toString())
            copyResponseHeader(response.headers, output, "ETag")
            copyResponseHeader(response.headers, output, "Cache-Control")
            output.write("\r\n".toByteArray(Charsets.ISO_8859_1))
            output.write(compressedBytes)
            output.flush()
            return
          } else {
            copyResponseHeader(response.headers, output, "Content-Type")
            writeHeader(output, "Content-Length", sourceBytes.size.toString())
            copyResponseHeader(response.headers, output, "ETag")
            copyResponseHeader(response.headers, output, "Cache-Control")
            output.write("\r\n".toByteArray(Charsets.ISO_8859_1))
            output.write(sourceBytes)
            output.flush()
            return
          }
        }

        // 直传
        copyResponseHeader(response.headers, output, "Content-Type")
        rawBody.contentLength().takeIf { it >= 0 }?.let { writeHeader(output, "Content-Length", it.toString()) }
        copyResponseHeader(response.headers, output, "Content-Range")
        copyResponseHeader(response.headers, output, "Accept-Ranges")
        copyResponseHeader(response.headers, output, "ETag")
        copyResponseHeader(response.headers, output, "Cache-Control")
        output.write("\r\n".toByteArray(Charsets.ISO_8859_1))
        rawBody.byteStream().use { copyStream(it, output) }
        output.flush()
      }
    }

    private fun appendVary(current: String?, name: String): String {
      val values = current
          ?.split(",")
          ?.map { it.trim() }
          ?.filter { it.isNotEmpty() }
          ?.toMutableList()
          ?: mutableListOf()
      if (values.none { it.equals(name, ignoreCase = true) }) {
        values.add(name)
      }
      return values.joinToString(", ")
    }

    private fun compressImageBytes(sourceBytes: ByteArray): ByteArray? {
      val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
      BitmapFactory.decodeByteArray(sourceBytes, 0, sourceBytes.size, bounds)
      val width = bounds.outWidth
      val height = bounds.outHeight
      if (width <= 0 || height <= 0 || width <= COMPRESSED_IMAGE_MAX_WIDTH) return null

      val sampleOptions = BitmapFactory.Options().apply {
        inSampleSize = calculateInSampleSize(width, COMPRESSED_IMAGE_MAX_WIDTH)
      }
      val decoded = BitmapFactory.decodeByteArray(sourceBytes, 0, sourceBytes.size, sampleOptions)
          ?: return null
      val scaled = if (decoded.width > COMPRESSED_IMAGE_MAX_WIDTH) {
        val ratio = COMPRESSED_IMAGE_MAX_WIDTH.toFloat() / decoded.width
        val targetHeight = maxOf(1, (decoded.height * ratio).toInt())
        Bitmap.createScaledBitmap(decoded, COMPRESSED_IMAGE_MAX_WIDTH, targetHeight, true)
      } else {
        decoded
      }
      return try {
        val compressed = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, COMPRESSED_IMAGE_JPEG_QUALITY, compressed)
        compressed.toByteArray()
      } finally {
        if (scaled !== decoded) scaled.recycle()
        decoded.recycle()
      }
    }

    private fun calculateInSampleSize(sourceWidth: Int, targetWidth: Int): Int {
      var sampleSize = 1
      while (sourceWidth / (sampleSize * 2) >= targetWidth) {
        sampleSize *= 2
      }
      return sampleSize
    }

    private fun copyStream(input: InputStream, output: java.io.OutputStream) {
      val buffer = ByteArray(BUFFER_SIZE)
      while (true) {
        val read = input.read(buffer)
        if (read <= 0) break
        output.write(buffer, 0, read)
      }
    }

    private fun copyResponseHeader(
        headers: Headers,
        output: java.io.OutputStream,
        name: String,
    ) {
      val value = headers[name] ?: return
      writeHeader(output, name, value)
    }

    private fun writeHeader(output: java.io.OutputStream, name: String, value: String) {
      output.write("$name: $value\r\n".toByteArray(Charsets.ISO_8859_1))
    }

    private fun writeText(socket: Socket, status: Int, text: String) {
      writeBytes(socket, status, "text/plain; charset=utf-8", text.toByteArray(Charsets.UTF_8), false)
    }

    private fun writeBytes(
        socket: Socket,
        status: Int,
        contentType: String,
        body: ByteArray,
        headersOnly: Boolean,
    ) {
      val output = socket.getOutputStream()
      output.write("HTTP/1.1 $status ${reasonPhrase(status)}\r\n".toByteArray(Charsets.ISO_8859_1))
      writeHeader(output, "Content-Type", contentType)
      writeHeader(output, "Content-Length", body.size.toString())
      writeHeader(output, "Connection", "close")
      output.write("\r\n".toByteArray(Charsets.ISO_8859_1))
      if (!headersOnly) {
        output.write(body)
      }
      output.flush()
    }

    private fun encodePath(path: String): String =
        path.split("/")
            .filter { it.isNotEmpty() }
            .joinToString("/") { URLEncoder.encode(it, "UTF-8").replace("+", "%20") }

    private fun reasonPhrase(status: Int): String =
        when (status) {
          200 -> "OK"
          206 -> "Partial Content"
          400 -> "Bad Request"
          401 -> "Unauthorized"
          404 -> "Not Found"
          405 -> "Method Not Allowed"
          416 -> "Range Not Satisfiable"
          502 -> "Bad Gateway"
          else -> "OK"
        }
  }
}
