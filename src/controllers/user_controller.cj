package lrr4cj.controllers

import cjoy.*
import stdx.net.http.HttpStatusCode
import std.fs.*
import std.time.*
import stdx.encoding.json.stream.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.views.*

class AvatarAssetIdView <: JsonSerializable {
    public let avatarAssetId: Int64
    public init(avatarAssetId: Int64) { this.avatarAssetId = avatarAssetId }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("avatarAssetId").writeValue(avatarAssetId)
        w.endObject()
    }
}

/**
 * User profile APIs (avatar, etc.)
 */
public class UserController {
    /**
     * PUT /api/user/avatar
     * Body: raw bytes of the uploaded image file.
     * Headers (optional): Content-Type, X-Filename.
     */
    public static func uploadAvatar(ctx: JoyContext, userId: Int64): Unit {
        if (userId <= 0) {
            ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
            ResponseView.json(ctx, ApiResponse<String>(401, "unauthorized", None))
            return
        }

        let raw = ctx.readRawData()
        if (raw.size <= 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, ApiResponse<String>(400, "empty body", None))
            return
        }

        let filenameHeader = ctx.getHeader("X-Filename") ?? ""
        let filenameQuery = ctx.getQuery("filename") ?? ""
        let originalFilename = if (filenameHeader.trimAscii().size > 0) { filenameHeader.trimAscii() }
            else if (filenameQuery.trimAscii().size > 0) { filenameQuery.trimAscii() }
            else { "avatar" }

        let contentType = (ctx.getHeader("Content-Type") ?? "").trimAscii()
        let inferredExt = inferExtFromFilenameOrContentType(originalFilename, contentType)

        let cacheRoot = SystemSettingsService.getPath("CACHE_PATH")
        let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
        FileUtils.ensureDirectoryExists(Path(cacheRoot))
        FileUtils.ensureDirectoryExists(Path(assetRoot))

        let ts = DateTime.now().toUnixTimeStamp().toSeconds()
        let tempDir = FileUtils.joinPath(cacheRoot, "avatar/${userId.toString()}_${ts.toString()}")
        FileUtils.ensureDirectoryExists(Path(tempDir))

        let inputPath = FileUtils.joinPath(tempDir, "input.${inferredExt}")
        let outputAvifPath = FileUtils.joinPath(tempDir, "avatar.avif")

        try {
            let f = File(Path(inputPath), Write)
            f.write(raw)
            f.close()
        } catch (e: Exception) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, ApiResponse<String>(500, "failed to write temp file: ${e.message}", None))
            return
        }

        let convertRes = ArchiveUtils.convertAvatarToAvif(inputPath, outputAvifPath, tempDir)
        if (!convertRes.success) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            ctx.status(HttpStatusCode.STATUS_UNPROCESSABLE_ENTITY)
            ResponseView.json(ctx, ApiResponse<String>(422, "avatar conversion failed: ${convertRes.error}", None))
            return
        }

        let thumbHash = try { ThumbHashUtils.calculateAvifThumbHashFromFile(outputAvifPath) } catch (_: Exception) { "" }
        let byteSize = try { Int64(FileInfo(Path(outputAvifPath)).size) } catch (_: Exception) { 0 }

        match (AssetDao.create(Some(userId), "user_avatar", originalFilename, "image/avif", "avif", byteSize, thumbHash)) {
            case Some(assetId) =>
                let finalPath = FileUtils.joinPath(assetRoot, "${assetId}.avif")
                try {
                    FileUtils.safeReplaceFile(Path(finalPath), Path(outputAvifPath))
                } catch (e: Exception) {
                    let _ = FileUtils.removeFileOrDirectory(tempDir)
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, ApiResponse<String>(500, "failed to store avatar: ${e.message}", None))
                    return
                }

                if (!UserDao.updateAvatarAssetId(userId, assetId)) {
                    // File is already written; keep it, but report DB error.
                    let _ = FileUtils.removeFileOrDirectory(tempDir)
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, ApiResponse<String>(500, "failed to update user avatar", None))
                    return
                }

                let _ = FileUtils.removeFileOrDirectory(tempDir)
                ctx.status(HttpStatusCode.STATUS_OK)
                ResponseView.json(ctx, ApiResponse<AvatarAssetIdView>(200, "ok", Some(AvatarAssetIdView(assetId))))
            case None =>
                let _ = FileUtils.removeFileOrDirectory(tempDir)
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
        return "tmp"
    }
}
