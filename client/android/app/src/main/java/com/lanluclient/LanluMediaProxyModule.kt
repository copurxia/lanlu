package com.lanluclient

import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import java.io.BufferedReader
import java.io.File
import java.io.InputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

class LanluMediaProxyModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

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
  fun createUrl(uri: String, headers: ReadableMap?, promise: Promise) {
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
      val port = ProxyServer.register(id, uri, copiedHeaders)
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
      val port = ProxyServer.register(id, uri, copiedHeaders)
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

  private fun encodeLocalPath(path: String): String =
      path.split("/")
          .filter { it.isNotEmpty() }
          .joinToString("/") { URLEncoder.encode(it, "UTF-8").replace("+", "%20") }

  private data class ProxyTarget(val uri: String, val headers: Map<String, String>)

  private object ProxyServer {
    private const val TAG = "LanluMediaProxy"
    private val targets = ConcurrentHashMap<String, ProxyTarget>()
    private val executor = Executors.newCachedThreadPool()

    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var port: Int = 0

    @Synchronized
    fun register(id: String, uri: String, headers: Map<String, String>): Int {
      ensureStarted()
      targets[id] = ProxyTarget(uri, headers)
      return port
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
          if (pagePath?.endsWith(".js", ignoreCase = true) == true) {
            writeBytes(
                socket,
                200,
                "application/javascript; charset=utf-8",
                "/* EPUB scripts disabled by Lanlu reader. */\n".toByteArray(Charsets.UTF_8),
                method == "HEAD",
            )
            return
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
      val connection = URL(targetUri).openConnection() as HttpURLConnection
      try {
        configureTlsIfNeeded(connection)
        connection.requestMethod = method
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 15000
        connection.readTimeout = if (pagePath.isNullOrBlank()) 0 else 15000
        target.headers.forEach { (key, value) ->
          if (value.isNotBlank()) connection.setRequestProperty(key, value)
        }
        requestHeaders["range"]?.let { connection.setRequestProperty("Range", it) }
        if (!target.headers.keys.any { it.equals("User-Agent", ignoreCase = true) }) {
          requestHeaders["user-agent"]?.let { connection.setRequestProperty("User-Agent", it) }
        }

        val status = connection.responseCode
        val output = socket.getOutputStream()
        output.write("HTTP/1.1 $status ${reasonPhrase(status)}\r\n".toByteArray(Charsets.ISO_8859_1))
        writeHeader(output, "Connection", "close")
        copyResponseHeader(connection, output, "Content-Type")
        copyResponseHeader(connection, output, "Content-Length")
        copyResponseHeader(connection, output, "Content-Range")
        copyResponseHeader(connection, output, "Accept-Ranges")
        copyResponseHeader(connection, output, "ETag")
        copyResponseHeader(connection, output, "Cache-Control")
        output.write("\r\n".toByteArray(Charsets.ISO_8859_1))

        if (method != "HEAD") {
          val body = responseStream(connection)
          body?.use { copyStream(it, output) }
        }
        output.flush()
      } finally {
        connection.disconnect()
      }
    }

    private fun responseStream(connection: HttpURLConnection): InputStream? =
        try {
          connection.inputStream
        } catch (_: Exception) {
          connection.errorStream
        }

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

    private fun copyStream(input: InputStream, output: java.io.OutputStream) {
      val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
      while (true) {
        val read = input.read(buffer)
        if (read <= 0) break
        output.write(buffer, 0, read)
      }
    }

    private fun copyResponseHeader(
        connection: HttpURLConnection,
        output: java.io.OutputStream,
        name: String,
    ) {
      val value = connection.getHeaderField(name) ?: return
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
