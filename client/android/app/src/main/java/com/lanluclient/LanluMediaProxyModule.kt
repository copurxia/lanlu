package com.lanluclient

import android.util.Log
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import java.io.BufferedReader
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

          val id = URLDecoder.decode(
              requestPath.substringAfter("/media/", "").substringBefore("?"),
              "UTF-8",
          )
          val target = targets[id]
          if (target == null) {
            writeText(socket, 404, "Not Found")
            return
          }

          if (method != "GET" && method != "HEAD") {
            writeText(socket, 405, "Method Not Allowed")
            return
          }

          proxyRequest(socket, method, target, requestHeaders)
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
      val connection = URL(target.uri).openConnection() as HttpURLConnection
      try {
        configureTlsIfNeeded(connection)
        connection.requestMethod = method
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 15000
        connection.readTimeout = 0
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
      val body = text.toByteArray(Charsets.UTF_8)
      val output = socket.getOutputStream()
      output.write("HTTP/1.1 $status ${reasonPhrase(status)}\r\n".toByteArray(Charsets.ISO_8859_1))
      writeHeader(output, "Content-Type", "text/plain; charset=utf-8")
      writeHeader(output, "Content-Length", body.size.toString())
      writeHeader(output, "Connection", "close")
      output.write("\r\n".toByteArray(Charsets.ISO_8859_1))
      output.write(body)
      output.flush()
    }

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
