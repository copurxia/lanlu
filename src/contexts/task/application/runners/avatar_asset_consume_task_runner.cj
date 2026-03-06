package lanlu.contexts.task.application.runners

import stdx.log.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.convert.*
import std.fs.*
import std.time.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.user.infrastructure.persistence.*

/**
 * avatar_asset_consume：消费 staging asset，转换并更新用户头像。
 */
public class AvatarAssetConsumeTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "avatar_asset_consume task started")

        let stagingAssetId = parseInt64Safely(parseField(parameters, "staging_asset_id"))
        let targetType = parseField(parameters, "target_type").trimAscii().toAsciiLower()
        let uploadUserId = parseInt64Safely(parseField(parameters, "upload_user_id"))
        let originalFilename = parseField(parameters, "filename")

        if (stagingAssetId <= 0) {
            fail(taskId, "staging_asset_id is required")
            return
        }
        if (targetType != "user_avatar") {
            fail(taskId, "target_type must be user_avatar")
            return
        }
        if (uploadUserId <= 0) {
            cleanupStagingAsset(context.paths.assetPath, stagingAssetId, "")
            fail(taskId, "upload_user_id is required")
            return
        }

        let user = UserDao.getById(uploadUserId)
        if (user.id <= 0) {
            cleanupStagingAsset(context.paths.assetPath, stagingAssetId, "")
            fail(taskId, "user not found")
            return
        }

        let staging = AssetDao.getById(stagingAssetId)
        if (staging.id <= 0) {
            fail(taskId, "staging asset not found")
            return
        }

        let stagingExt = resolveAssetExt(staging, originalFilename)
        let assetRoot = context.paths.assetPath
        let stagingPath = FileUtils.joinPath(assetRoot, "${stagingAssetId}.${stagingExt}")
        if (!exists(Path(stagingPath))) {
            let _ = AssetDao.deleteById(stagingAssetId)
            fail(taskId, "staging asset file missing")
            return
        }

        let cacheRoot = context.paths.cachePath
        FileUtils.ensureDirectoryExists(Path(cacheRoot))
        FileUtils.ensureDirectoryExists(Path(assetRoot))
        let ts = DateTime.now().toUnixTimeStamp().toSeconds()
        let tempDir = FileUtils.joinPath(cacheRoot, "avatar_asset_consume/${uploadUserId.toString()}_${ts.toString()}_${taskId.toString()}")
        FileUtils.ensureDirectoryExists(Path(tempDir))

        let outputAvifPath = FileUtils.joinPath(tempDir, "avatar.avif")

        TaskModel.updateTaskProgress(taskId, 60, "转换头像资源")
        let (convertRes, thumbHashFromConvert) = ArchiveUtils.convertAvatarToAvifWithThumbHash(stagingPath, outputAvifPath, tempDir)
        if (!convertRes.success) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)
            fail(taskId, "avatar conversion failed")
            return
        }

        let thumbHash = if (thumbHashFromConvert.size > 0) { thumbHashFromConvert }
            else { try { ThumbHashUtils.calculateAvifThumbHashFromFile(outputAvifPath) } catch (_: Exception) { "" } }
        let byteSize = try { Int64(FileInfo(Path(outputAvifPath)).size) } catch (_: Exception) { 0 }

        let newAssetIdOpt = AssetDao.create(Some(uploadUserId), "user_avatar", originalFilename, "image/avif", "avif", byteSize, thumbHash)
        let newAssetId = match (newAssetIdOpt) {
            case Some(id) => id
            case None =>
                let _ = FileUtils.removeFileOrDirectory(tempDir)
                cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)
                fail(taskId, "failed to create avatar asset")
                return
        }

        let finalPath = FileUtils.joinPath(assetRoot, "${newAssetId}.avif")
        try {
            FileUtils.safeReplaceFile(Path(finalPath), Path(outputAvifPath))
        } catch (e: Exception) {
            let _ = AssetDao.deleteById(newAssetId)
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)
            fail(taskId, "failed to store avatar asset: ${e.message}")
            return
        }

        if (!UserDao.updateAvatarAssetId(uploadUserId, newAssetId)) {
            try { remove(Path(finalPath)) } catch (_: Exception) {}
            let _ = AssetDao.deleteById(newAssetId)
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)
            fail(taskId, "failed to update user avatar")
            return
        }

        if (user.avatarAssetId > 0 && user.avatarAssetId != newAssetId) {
            try {
                let oldPath = FileUtils.joinPath(assetRoot, "${user.avatarAssetId}.avif")
                try { remove(Path(oldPath)) } catch (_: Exception) {}
            } catch (_: Exception) {}
            let _ = AssetDao.deleteById(user.avatarAssetId)
        }

        let _ = FileUtils.removeFileOrDirectory(tempDir)
        cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("avatarAssetId").writeValue(newAssetId)
        w.writeName("assetId").writeValue(newAssetId)
        w.endObject()
        w.flush()
        let okJson = String.fromUtf8(readToEnd(out))

        TaskModel.updateTaskProgress(taskId, 100, "头像更新完成")
        TaskModel.completeTask(taskId, "avatar_asset_consume completed")
        TaskIO.writeOutput(taskId, okJson)
        TaskIO.appendLog(taskId, "avatar_asset_consume completed: user=${uploadUserId.toString()} asset=${newAssetId.toString()}")
    }

    private static func parseField(parameters: String, key: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                if (k == key) {
                    return r.readValue<String>().trimAscii()
                } else {
                    r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return ""
    }

    private static func parseInt64Safely(value: String): Int64 {
        if (value.size == 0) {
            return 0
        }
        try {
            return Int64.parse(value)
        } catch (_: Exception) {
            return 0
        }
    }

    private static func resolveAssetExt(asset: AssetRow, filename: String): String {
        if (asset.fileExt.trimAscii().size > 0) {
            return asset.fileExt.trimAscii().toAsciiLower()
        }
        let ext = FileUtils.getFileExtensionWithoutDot(filename).trimAscii().toAsciiLower()
        if (ext.size > 0) {
            return ext
        }
        return "bin"
    }

    private static func cleanupStagingAsset(assetRoot: String, assetId: Int64, extHint: String): Unit {
        if (assetId <= 0) {
            return
        }
        let row = AssetDao.getById(assetId)
        let ext = if (extHint.size > 0) { extHint }
            else if (row.fileExt.trimAscii().size > 0) { row.fileExt.trimAscii().toAsciiLower() }
            else { "bin" }
        let path = FileUtils.joinPath(assetRoot, "${assetId}.${ext}")
        try {
            if (exists(Path(path))) {
                try { remove(Path(path)) } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        let _ = AssetDao.deleteById(assetId)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}
