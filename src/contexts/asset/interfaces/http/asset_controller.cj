package lanlu.contexts.asset.interfaces.http

import ignite.*
import stdx.net.http.HttpStatusCode
import std.convert.*
import std.fs.*
import std.collection.ArrayList
import stdx.encoding.json.stream.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.system.application.*
import lanlu.shared.utils.*
import lanlu.shared.views.*

class AssetIdView <: JsonSerializable {
    public let assetId: Int64
    public init(assetId: Int64) { this.assetId = assetId }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("assetId").writeValue(assetId)
        w.endObject()
    }
}

/**
 * Asset controller: serve files stored in ASSET_PATH by asset id.
 */
public class AssetController {
    // GET /api/assets/{id}
    public static func getAsset(ctx: Ctx): Unit {
        let idStr = ctx.paramsOpt("id").getOrThrow()
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
            let etag = CacheUtils.generateETag("${filePath}:${fileInfo.size}:${fileInfo.lastModificationTime}")
            if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
                CacheUtils.sendNotModified(ctx, etag)
                return
            }

            let bytes = File.readFrom(Path(filePath))
            CacheUtils.setStaticCacheHeaders(ctx, etag)
            let ct = if (asset.contentType.size > 0) { asset.contentType } else { "application/octet-stream" }
            ctx.setHeader("Content-Type", ct)
            ctx.status(HttpStatusCode.STATUS_OK)
            ctx.send(bytes)
        } catch (e: Exception) {
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, ApiResponse<String>(500, e.message, None))
        }
    }

    /**
     * POST /api/assets
     * Body: raw bytes; optional headers: Content-Type, X-Filename; optional query: kind
     */
    public static func uploadAsset(ctx: Ctx, userId: Int64): Unit {
        if (userId <= 0) {
            ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
            ResponseView.json(ctx, ApiResponse<String>(401, "unauthorized", None))
            return
        }

        // 读取请求体 - 二进制数据使用 requestBody()
        let bodyStream = ctx.requestBody()
        let rawList = ArrayList<UInt8>()
        let tmp = Array<UInt8>(8192, repeat: 0)
        while (true) {
            let n = bodyStream.read(tmp)
            if (n <= 0) {
                break
            }
            for (i in 0..n) {
                rawList.add(tmp[i])
            }
        }
        let raw = rawList.toArray()

        if (raw.size <= 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, ApiResponse<String>(400, "empty body", None))
            return
        }

        let kind = (ctx.query("kind") ?? "upload").trimAscii()
        let filename = (ctx.header("X-Filename") ?? (ctx.query("filename") ?? "")).trimAscii()
        let originalFilename = if (filename.size > 0) { filename } else { "upload" }
        let contentType = (ctx.header("Content-Type") ?? "").trimAscii()
        let ext = inferExtFromFilenameOrContentType(originalFilename, contentType)
        let byteSize = Int64(raw.size)

        let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
        FileUtils.ensureDirectoryExists(Path(assetRoot))

        match (AssetDao.create(Some(userId), kind, originalFilename, contentType, ext, byteSize, "")) {
            case Some(assetId) =>
                let filePath = FileUtils.joinPath(assetRoot, "${assetId}.${ext}")
                try {
                    let f = File(Path(filePath), Write)
                    f.write(raw)
                    f.close()
                } catch (e: Exception) {
                    let _ = AssetDao.deleteById(assetId)
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, ApiResponse<String>(500, "failed to store asset: ${e.message}", None))
                    return
                }
                ctx.status(HttpStatusCode.STATUS_OK)
                ResponseView.json(ctx, ApiResponse<AssetIdView>(200, "ok", Some(AssetIdView(assetId))))
            case None =>
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ResponseView.json(ctx, ApiResponse<String>(500, "failed to create asset record", None))
        }
    }

    private static func inferExtFromFilenameOrContentType(filename: String, contentType: String): String {
        let ext = FileUtils.getFileExtensionWithoutDot(filename).toAsciiLower()
        if (ext.size > 0) { return ext }

        let ct = contentType.toAsciiLower()
        if (ct.contains("png")) { return "png" }
        if (ct.contains("jpeg") || ct.contains("jpg")) { return "jpg" }
        if (ct.contains("webp")) { return "webp" }
        if (ct.contains("gif")) { return "gif" }
        if (ct.contains("avif")) { return "avif" }
        if (ct.contains("pdf")) { return "pdf" }
        if (ct.contains("zip")) { return "zip" }
        return "bin"
    }
}
