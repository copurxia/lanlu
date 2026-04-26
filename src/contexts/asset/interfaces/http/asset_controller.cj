package lanlu.contexts.asset.interfaces.http

import ignite.*
import stdx.net.http.HttpStatusCode
import std.convert.*
import std.fs.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.system.application.*
import lanlu.shared.utils.*
import lanlu.shared.views.*

/**
 * Asset controller: serve files stored in ASSET_PATH by asset id.
 */
public class AssetController {
    // GET /api/assets/{id}
    public static func getAsset(ctx: Ctx): Unit {
        let idStr = match (ctx.paramsOpt("id")) {
            case Some(value) => value
            case None =>
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, ApiResponse<String>(400, "invalid asset id", None))
                return
        }
        let id = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
        if (id <= 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, ApiResponse<String>(400, "invalid asset id", None))
            return
        }

        let asset = AssetDao.getById(id)
        if (asset.id <= 0) {
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ResponseView.json(ctx, ApiResponse<String>(404, "asset not found", None))
            return
        }

        let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
        let ext = if (asset.fileExt.size > 0) { asset.fileExt } else { "bin" }
        let filePath = FileUtils.joinPath(assetRoot, "${asset.id}.${ext}")

        if (!exists(Path(filePath))) {
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
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
            let ct = if (asset.contentType.size > 0) { asset.contentType } else { "application/octet-stream" }
            ctx.setHeader("Content-Type", ct)
            ctx.status(HttpStatusCode.STATUS_OK)

            // 流式发送：分块读取文件并写入响应流，避免大文件 OOM
            let streamThreshold: Int64 = 2 * 1024 * 1024 // 2MB
            if (fileSize <= streamThreshold) {
                // 小文件直接全量读取
                let bytes = File.readFrom(Path(filePath))
                ctx.setHeader("Content-Length", fileSize.toString())
                ctx.send(bytes)
            } else {
                // 大文件流式发送
                let writer = ctx.writer()
                let f = File(filePath, OpenMode.Read)
                let chunkBufSize: Int64 = 131072 // 128KB
                var remaining = fileSize
                let chunkBuffer = Array<UInt8>(chunkBufSize, repeat: 0)
                while (remaining > 0) {
                    let bytesRead = f.read(chunkBuffer)
                    if (bytesRead <= 0) {
                        break
                    }
                    if (bytesRead == chunkBufSize) {
                        writer.write(chunkBuffer)
                    } else {
                        writer.write(chunkBuffer[0..bytesRead])
                    }
                    remaining -= bytesRead
                }
                f.close()
            }
        } catch (e: Exception) {
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, ApiResponse<String>(500, e.message, None))
        }
    }

}
