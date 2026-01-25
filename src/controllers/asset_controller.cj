package lrr4cj.controllers

import cjoy.*
import stdx.net.http.HttpStatusCode
import std.fs.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

/**
 * Asset controller: serve files stored in ASSET_PATH by asset id.
 */
public class AssetController {
    // GET /api/assets/{id}
    public static func getAsset(ctx: JoyContext): Unit {
        let idStr = ctx.getParam("id").getOrThrow()
        let id = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
        if (id <= 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"code\":400,\"message\":\"invalid asset id\",\"data\":null}")
            return
        }

        let asset = AssetDao.getById(id)
        if (asset.id <= 0) {
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json("{\"code\":404,\"message\":\"asset not found\",\"data\":null}")
            return
        }

        let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
        let ext = if (asset.fileExt.size > 0) { asset.fileExt } else { "bin" }
        let filePath = FileUtils.joinPath(assetRoot, "${asset.id}.${ext}")

        if (!exists(Path(filePath))) {
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json("{\"code\":404,\"message\":\"asset file missing\",\"data\":null}")
            return
        }

        try {
            let etag = if (asset.thumbhash.size > 0) {
                "\"${asset.thumbhash}\""
            } else {
                CacheUtils.generateETag("${asset.id}-${ext}")
            }
            if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
                CacheUtils.sendNotModified(ctx, etag)
                return
            }

            let bytes = File.readFrom(Path(filePath))
            CacheUtils.setStaticCacheHeaders(ctx, etag)
            let ct = if (asset.contentType.size > 0) { asset.contentType } else { "application/octet-stream" }
            ctx.header("Content-Type", ct)
            ctx.status(HttpStatusCode.STATUS_OK)
            ctx.data(bytes)
        } catch (e: Exception) {
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json("{\"code\":500,\"message\":\"${escapeJsonString(e.message)}\",\"data\":null}")
        }
    }

    /**
     * POST /api/assets
     * Body: raw bytes; optional headers: Content-Type, X-Filename; optional query: kind
     */
    public static func uploadAsset(ctx: JoyContext, userId: Int64): Unit {
        if (userId <= 0) {
            ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
            ctx.json("{\"code\":401,\"message\":\"unauthorized\",\"data\":null}")
            return
        }

        let raw = ctx.readRawData()
        if (raw.size <= 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"code\":400,\"message\":\"empty body\",\"data\":null}")
            return
        }

        let kind = (ctx.getQuery("kind") ?? "upload").trimAscii()
        let filename = (ctx.getHeader("X-Filename") ?? (ctx.getQuery("filename") ?? "")).trimAscii()
        let originalFilename = if (filename.size > 0) { filename } else { "upload" }
        let contentType = (ctx.getHeader("Content-Type") ?? "").trimAscii()
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
                    ctx.json("{\"code\":500,\"message\":\"failed to store asset: ${escapeJsonString(e.message)}\",\"data\":null}")
                    return
                }
                ctx.status(HttpStatusCode.STATUS_OK)
                ctx.json("{\"code\":200,\"message\":\"ok\",\"data\":{\"assetId\":${assetId}}}")
            case None =>
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json("{\"code\":500,\"message\":\"failed to create asset record\",\"data\":null}")
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
