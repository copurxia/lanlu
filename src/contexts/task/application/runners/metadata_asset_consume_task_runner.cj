package lanlu.contexts.task.application.runners

import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.convert.*
import std.fs.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*
import lanlu.contexts.asset.infrastructure.persistence.*

/**
 * metadata_asset_consume：消费 staging asset，落盘为可复用的 metadata 资产。
 */
public class MetadataAssetConsumeTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "metadata_asset_consume task started")

        let stagingAssetId = TaskRunnerUtils.parseInt64Safely(TaskRunnerUtils.parseField(parameters, "staging_asset_id"))
        let targetType = TaskRunnerUtils.parseField(parameters, "target_type").trimAscii().toAsciiLower()
        let uploadUserId = TaskRunnerUtils.parseInt64Safely(TaskRunnerUtils.parseField(parameters, "upload_user_id"))
        let originalFilenameRaw = TaskRunnerUtils.parseField(parameters, "filename")

        if (stagingAssetId <= 0) {
            TaskRunnerUtils.fail(taskId, "staging_asset_id is required")
            return
        }
        if (targetType != "metadata_asset") {
            TaskRunnerUtils.fail(taskId, "target_type must be metadata_asset")
            return
        }
        if (uploadUserId <= 0) {
            TaskRunnerUtils.cleanupStagingAssetInRoot(context.paths.assetPath, stagingAssetId, "")
            TaskRunnerUtils.fail(taskId, "upload_user_id is required")
            return
        }

        let staging = AssetDao.getById(stagingAssetId)
        if (staging.id <= 0) {
            TaskRunnerUtils.fail(taskId, "staging asset not found")
            return
        }

        let ext = TaskRunnerUtils.resolveAssetExt(staging, originalFilenameRaw)
        let assetRoot = context.paths.assetPath
        let stagingPath = FileUtils.joinPath(assetRoot, "${stagingAssetId}.${ext}")
        if (!exists(Path(stagingPath))) {
            let _ = AssetDao.deleteById(stagingAssetId)
            TaskRunnerUtils.fail(taskId, "staging asset file missing")
            return
        }

        let originalFilename = if (originalFilenameRaw.trimAscii().size > 0) { originalFilenameRaw.trimAscii() } else { staging.originalFilename }
        let contentType = if (staging.contentType.trimAscii().size > 0) { staging.contentType.trimAscii() } else { "application/octet-stream" }
        let byteSize = if (staging.byteSize > 0) { staging.byteSize } else { try { Int64(FileInfo(Path(stagingPath)).size) } catch (_: Exception) { 0 } }

        TaskModel.updateTaskProgress(taskId, 60, "持久化元数据资产")
        let newAssetIdOpt = AssetDao.create(Some(uploadUserId), "metadata_asset", originalFilename, contentType, ext, byteSize, staging.thumbhash)
        let newAssetId = match (newAssetIdOpt) {
            case Some(id) => id
            case None =>
                TaskRunnerUtils.cleanupStagingAssetInRoot(assetRoot, stagingAssetId, ext)
                TaskRunnerUtils.fail(taskId, "failed to create metadata asset")
                return
        }

        let finalPath = FileUtils.joinPath(assetRoot, "${newAssetId}.${ext}")
        try {
            try {
                rename(Path(stagingPath), to: Path(finalPath))
            } catch (e: Exception) {
                if (e.message.contains("cross-device") || e.message.contains("Invalid cross-device link")) {
                    copy(Path(stagingPath), to: Path(finalPath), overwrite: false)
                    remove(Path(stagingPath))
                } else {
                    throw e
                }
            }
            if (!exists(Path(finalPath))) {
                throw Exception("metadata asset file missing after move")
            }
        } catch (e: Exception) {
            try { remove(Path(finalPath)) } catch (_: Exception) {}
            let _ = AssetDao.deleteById(newAssetId)
            TaskRunnerUtils.cleanupStagingAssetInRoot(assetRoot, stagingAssetId, ext)
            TaskRunnerUtils.fail(taskId, "failed to store metadata asset: ${e.message}")
            return
        }

        let _ = AssetDao.deleteById(stagingAssetId)

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("assetId").writeValue(newAssetId)
        w.endObject()
        w.flush()
        let okJson = String.fromUtf8(readToEnd(out))

        TaskModel.updateTaskProgress(taskId, 100, "元数据资产已保存")
        TaskModel.completeTask(taskId, "metadata_asset_consume completed")
        TaskIO.writeOutput(taskId, okJson)
        TaskIO.appendLog(taskId, "metadata_asset_consume completed: asset=${newAssetId.toString()}")
    }

}
