package lanlu.contexts.task.application.runners

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

        let stagingAssetId = TaskRunnerUtils.parseInt64Safely(TaskRunnerUtils.parseField(parameters, "staging_asset_id"))
        let targetType = TaskRunnerUtils.parseField(parameters, "target_type").trimAscii().toAsciiLower()
        let uploadUserId = TaskRunnerUtils.parseInt64Safely(TaskRunnerUtils.parseField(parameters, "upload_user_id"))
        let originalFilename = TaskRunnerUtils.parseField(parameters, "filename")

        if (stagingAssetId <= 0) {
            TaskRunnerUtils.fail(taskId, "staging_asset_id is required")
            return
        }
        if (targetType != "user_avatar") {
            TaskRunnerUtils.fail(taskId, "target_type must be user_avatar")
            return
        }
        if (uploadUserId <= 0) {
            TaskRunnerUtils.cleanupStagingAssetInRoot(context.paths.assetPath, stagingAssetId, "")
            TaskRunnerUtils.fail(taskId, "upload_user_id is required")
            return
        }

        let user = UserDao.getById(uploadUserId)
        if (user.id <= 0) {
            TaskRunnerUtils.cleanupStagingAssetInRoot(context.paths.assetPath, stagingAssetId, "")
            TaskRunnerUtils.fail(taskId, "user not found")
            return
        }

        let staging = AssetDao.getById(stagingAssetId)
        if (staging.id <= 0) {
            TaskRunnerUtils.fail(taskId, "staging asset not found")
            return
        }

        let stagingExt = TaskRunnerUtils.resolveAssetExt(staging, originalFilename)
        let assetRoot = context.paths.assetPath
        let stagingPath = FileUtils.joinPath(assetRoot, "${stagingAssetId}.${stagingExt}")
        if (!exists(Path(stagingPath))) {
            let _ = AssetDao.deleteById(stagingAssetId)
            TaskRunnerUtils.fail(taskId, "staging asset file missing")
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
            TaskRunnerUtils.cleanupStagingAssetInRoot(assetRoot, stagingAssetId, stagingExt)
            TaskRunnerUtils.fail(taskId, "avatar conversion failed")
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
                TaskRunnerUtils.cleanupStagingAssetInRoot(assetRoot, stagingAssetId, stagingExt)
                TaskRunnerUtils.fail(taskId, "failed to create avatar asset")
                return
        }

        let finalPath = FileUtils.joinPath(assetRoot, "${newAssetId}.avif")
        try {
            FileUtils.safeReplaceFile(Path(finalPath), Path(outputAvifPath))
        } catch (e: Exception) {
            let _ = AssetDao.deleteById(newAssetId)
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            TaskRunnerUtils.cleanupStagingAssetInRoot(assetRoot, stagingAssetId, stagingExt)
            TaskRunnerUtils.fail(taskId, "failed to store avatar asset: ${e.message}")
            return
        }

        if (!UserDao.updateAvatarAssetId(uploadUserId, newAssetId)) {
            try { remove(Path(finalPath)) } catch (_: Exception) {}
            let _ = AssetDao.deleteById(newAssetId)
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            TaskRunnerUtils.cleanupStagingAssetInRoot(assetRoot, stagingAssetId, stagingExt)
            TaskRunnerUtils.fail(taskId, "failed to update user avatar")
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
        TaskRunnerUtils.cleanupStagingAssetInRoot(assetRoot, stagingAssetId, stagingExt)

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

}
