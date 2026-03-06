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

}
