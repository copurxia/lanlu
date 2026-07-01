package lanlu.contexts.asset.interfaces.http

import ace_web.*
import lanlu.shared.http_ext.*
import stdx.net.http.HttpStatusCode
import std.convert.*
import std.fs.*
import std.io.SeekPosition
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.system.application.*
import lanlu.shared.utils.*
import lanlu.shared.views.*

/**
 * Asset controller: serve files stored in ASSET_PATH by asset id.
 */
public class AssetController {
    // GET /api/assets/{id}
    public static func getAsset(ctx: Context): Unit {
        let idStr = match (ctx.param("id")) {
            case Some(value) => value
            case None =>
                ctx.status = HttpStatusCode.STATUS_BAD_REQUEST
                ResponseView.json(ctx, ApiResponse<String>(400, "invalid asset id", None))
                return
        }
        let id = try {
            Int64.parse(idStr)
        } catch (_: Exception) {
            0
        }
        if (id <= 0) {
            ctx.status = HttpStatusCode.STATUS_BAD_REQUEST
            ResponseView.json(ctx, ApiResponse<String>(400, "invalid asset id", None))
            return
        }

        let asset = AssetDao.getById(id)
        if (asset.id <= 0) {
            ctx.status = HttpStatusCode.STATUS_NOT_FOUND
            ResponseView.json(ctx, ApiResponse<String>(404, "asset not found", None))
            return
        }

        let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
        let ext = if (asset.fileExt.size > 0) {
            asset.fileExt
        } else {
            "bin"
        }
        let filePath = FileUtils.joinPath(assetRoot, "${asset.id}.${ext}")

        if (!exists(Path(filePath))) {
            ctx.status = HttpStatusCode.STATUS_NOT_FOUND
            ResponseView.json(ctx, ApiResponse<String>(404, "asset file missing", None))
            return
        }

        try {
            let fileInfo = FileInfo(filePath)
            let fileSize = Int64(fileInfo.size)
            let etag = CacheUtils.generateETag("${filePath}:${fileSize}:${fileInfo.lastModificationTime}")
            if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
                CacheUtils.sendNotModified(ctx, etag)
                return
            }

            CacheUtils.setStaticCacheHeaders(ctx, etag)
            let ct = if (asset.contentType.size > 0) {
                asset.contentType
            } else {
                "application/octet-stream"
            }
            ctx.setHeader("Content-Type", ct)
            // 声明支持断点续传，供视频播放器/下载器发 Range 请求。
            ctx.setHeader("Accept-Ranges", "bytes")

            // 解析 Range 头。仅支持单一区间 bytes=start-end，兼容三种形式：
            //   bytes=0-1023   闭区间
            //   bytes=1024-    从 1024 到文件末尾
            //   bytes=-512     文件最后 512 字节
            // 多段(逗号分隔)按非法处理返回 416；越界同样 416。
            let rangeHeader = ctx.header("range")
            var start: Int64 = 0
            var end: Int64 = fileSize - 1
            var hasRange = false
            var rangeInvalid = false
            match (rangeHeader) {
                case Some(raw) =>
                    let spec = raw.trimAscii()
                    if (spec.startsWith("bytes=")) {
                        let body = spec["bytes=".size..spec.size].trimAscii()
                        // 多段区间不在此支持范围，按非法处理。
                        if (body.contains(",")) {
                            rangeInvalid = true
                        } else {
                            match (body.indexOf("-")) {
                                case None => rangeInvalid = true
                                case Some(dashIdx) =>
                                    let left = body[0..dashIdx]
                                    let right = body[dashIdx + 1..body.size]
                                    if (left.size == 0 && right.size == 0) {
                                        rangeInvalid = true
                                    } else if (left.size == 0) {
                                        // 后缀范围 bytes=-N：取文件最后 N 字节。
                                        let n = try { Int64.parse(right) } catch (_: Exception) { -1 }
                                        if (n <= 0) {
                                            rangeInvalid = true
                                        } else {
                                            start = if (n >= fileSize) { 0 } else { fileSize - n }
                                            end = fileSize - 1
                                            hasRange = true
                                        }
                                    } else if (right.size == 0) {
                                        // 开放区间 bytes=N-：从 N 到文件末尾。
                                        let s = try { Int64.parse(left) } catch (_: Exception) { -1 }
                                        if (s < 0 || s >= fileSize) {
                                            rangeInvalid = true
                                        } else {
                                            start = s
                                            end = fileSize - 1
                                            hasRange = true
                                        }
                                    } else {
                                        // 闭区间 bytes=start-end。
                                        let s = try { Int64.parse(left) } catch (_: Exception) { -1 }
                                        let e = try { Int64.parse(right) } catch (_: Exception) { -1 }
                                        if (s < 0 || e < s || s >= fileSize) {
                                            rangeInvalid = true
                                        } else {
                                            start = s
                                            end = if (e >= fileSize) { fileSize - 1 } else { e }
                                            hasRange = true
                                        }
                                    }
                            }
                        }
                    } else {
                        rangeInvalid = true
                    }
                case None => ()
            }

            if (rangeInvalid) {
                // 越界或格式非法：416，并回 Content-Range 指明合法范围供客户端修正。
                ctx.status = HttpStatusCode.STATUS_REQUESTED_RANGE_NOT_SATISFIABLE
                ctx.setHeader("Content-Range", "bytes */${fileSize}")
                ResponseView.json(ctx, ApiResponse<String>(416, "invalid range", None))
                return
            }

            if (hasRange) {
                ctx.status = HttpStatusCode.STATUS_PARTIAL_CONTENT
                ctx.setHeader("Content-Range", "bytes ${start}-${end}/${fileSize}")
            } else {
                ctx.status = HttpStatusCode.STATUS_OK
            }
            let contentLength = end - start + 1
            // 不设 Content-Length：setStreamBody 路径由 dispatch 统一加 Transfer-Encoding: chunked，
            // HTTP 规范禁止二者同时存在。区间语义已由 Content-Range 表达。

            // 用 ACE setStreamBody：producer 收到 write 闭包后分块读文件写出，由 dispatch 统一 chunked 写回。
            // Range 请求时先 seek 到 start，只读 contentLength 字节，避免把整个文件灌进响应管道。
            let path = filePath
            let readStart = start
            let readLen = contentLength
            ctx.setStreamBody({ write: (Array<UInt8>) -> Unit =>
                let f = File(path, OpenMode.Read)
                try {
                    if (readStart > 0) {
                        f.seek(SeekPosition.Begin(readStart))
                    }
                    let chunkBufSize: Int64 = 131072 // 128KB
                    let chunkBuffer = Array<UInt8>(chunkBufSize, repeat: 0u8)
                    var remaining = readLen
                    while (remaining > 0) {
                        let toRead = if (remaining < chunkBufSize) { remaining } else { chunkBufSize }
                        let bytesRead = f.read(chunkBuffer[0..toRead])
                        if (bytesRead <= 0) {
                            break
                        }
                        write(chunkBuffer[0..bytesRead])
                        remaining -= bytesRead
                    }
                } finally {
                    f.close()
                }
            })
        } catch (e: Exception) {
            ctx.status = HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR
            ResponseView.json(ctx, ApiResponse<String>(500, e.message, None))
        }
    }
}
