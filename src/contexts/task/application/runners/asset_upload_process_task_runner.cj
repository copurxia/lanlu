package lanlu.contexts.task.application.runners

import stdx.log.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.convert.*
import std.fs.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.task.infrastructure.persistence.TaskGroupKVDao

/**
 * asset_upload_process：将分片临时文件落为 staging asset，并分发给业务消费 runner。
 */
public class AssetUploadProcessTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("asset_upload_process_task")
        TaskIO.appendLog(taskId, "asset_upload_process task started")

        let filename = parseField(parameters, "filename")
        let categoryId = parseField(parameters, "category_id")
        let targetType = parseField(parameters, "target_type").trimAscii().toAsciiLower()
        let targetId = parseField(parameters, "target_id")
        let chunkDirStr = parseField(parameters, "chunk_dir")
        let finalPartPathStr = parseField(parameters, "final_part_path")
        let fileSize = parseInt64Safely(parseField(parameters, "file_size"))
        let overwrite = parseBool(parseField(parameters, "overwrite"))
        let uploadUserId = parseInt64Safely(parseField(parameters, "upload_user_id"))
        let contentType = parseField(parameters, "content_type")

        if (filename.size == 0) {
            fail(taskId, "filename is required")
            return
        }
        if (finalPartPathStr.size == 0) {
            fail(taskId, "final_part_path is required")
            return
        }
        if (!isSupportedTargetType(targetType)) {
            fail(taskId, "unsupported target_type")
            return
        }

        let finalPartPath = Path(finalPartPathStr)
        if (!exists(finalPartPath)) {
            fail(taskId, "final_part file not found")
            return
        }

        if (fileSize > 0) {
            let actualSize = FileInfo(finalPartPath).size
            if (actualSize != fileSize) {
                fail(taskId, "file size mismatch")
                return
            }
        }

        let ext = inferExtFromFilenameOrContentType(filename, contentType)
        let stagingKind = "upload_staging_${targetType}"
        let ownerOpt = if (uploadUserId > 0) { Some(uploadUserId) } else { Option<Int64>.None }
        let byteSize = if (fileSize > 0) { fileSize } else { try { Int64(FileInfo(finalPartPath).size) } catch (_: Exception) { 0 } }

        TaskModel.updateTaskProgress(taskId, 80, "创建暂存资产")
        let assetIdOpt = AssetDao.create(ownerOpt, stagingKind, filename, contentType, ext, byteSize, "")
        let stagingAssetId = match (assetIdOpt) {
            case Some(id) => id
            case None =>
                fail(taskId, "failed to create staging asset")
                return
        }

        let assetRoot = context.paths.assetPath
        FileUtils.ensureDirectoryExists(Path(assetRoot))
        let stagingPath = FileUtils.joinPath(assetRoot, "${stagingAssetId}.${ext}")

        try {
            try {
                rename(finalPartPath, to: Path(stagingPath))
            } catch (e: Exception) {
                if (e.message.contains("cross-device") || e.message.contains("Invalid cross-device link")) {
                    copy(finalPartPath, to: Path(stagingPath), overwrite: false)
                    remove(finalPartPath)
                } else {
                    throw e
                }
            }
            if (!exists(Path(stagingPath))) {
                throw Exception("staging file missing after move")
            }
        } catch (e: Exception) {
            try { remove(Path(stagingPath)) } catch (_: Exception) {}
            let _ = AssetDao.deleteById(stagingAssetId)
            fail(taskId, "Failed to store staging asset: ${e.message}")
            return
        }

        if (chunkDirStr.size > 0) {
            try {
                let chunkDir = Path(chunkDirStr)
                if (exists(chunkDir)) {
                    remove(chunkDir, recursive: true)
                }
            } catch (_: Exception) {}
        }

        TaskModel.updateTaskProgress(taskId, 90, "创建消费任务")
        let consumeTaskType = resolveConsumeTaskType(targetType)
        if (consumeTaskType.size == 0) {
            cleanupStagingAsset(stagingAssetId, assetRoot, ext)
            fail(taskId, "No consumer task for target_type=${targetType}")
            return
        }

        let consumeParams = buildConsumeParams(
            stagingAssetId,
            targetType,
            targetId,
            categoryId,
            filename,
            overwrite,
            uploadUserId
        )

        let groupId = "asset_upload:${taskId}"
        let consumeTask = TaskModel.createTaskWithOptions(
            resolveConsumeTaskName(targetType),
            consumeTaskType,
            consumeParams,
            20,
            groupId,
            "asset_upload"
        )

        if (consumeTask.id <= 0) {
            cleanupStagingAsset(stagingAssetId, assetRoot, ext)
            fail(taskId, "Failed to create consume task")
            return
        }

        context.notifyTaskAvailable()
        logger.debug(
            "Created consume task for asset upload",
            [("consume_task_id", consumeTask.id.toString()), ("target_type", targetType), ("staging_asset_id", stagingAssetId.toString())]
        )

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("consume_task_id").writeValue(consumeTask.id)
        w.writeName("staging_asset_id").writeValue(stagingAssetId)
        w.writeName("target_type").writeValue(targetType)
        w.endObject()
        w.flush()
        let okJson = String.fromUtf8(readToEnd(out))

        TaskModel.updateTaskProgress(taskId, 100, "资产消费任务已创建")
        TaskModel.completeTask(taskId, "asset_upload_process completed")
        TaskIO.writeOutput(taskId, okJson)
        TaskIO.appendLog(taskId, "asset_upload_process completed: consume_task_id=${consumeTask.id}")
        cleanupUploadKV(taskId)
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

    private static func parseBool(value: String): Bool {
        let v = value.trimAscii().toAsciiLower()
        return v == "true" || v == "1" || v == "yes"
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

    private static func isSupportedTargetType(targetType: String): Bool {
        return targetType == "archive" || targetType == "tag_icon" || targetType == "tag_background" || targetType == "user_avatar" || targetType == "metadata_asset" || targetType == "plugin"
    }

    private static func resolveConsumeTaskType(targetType: String): String {
        match (targetType) {
            case "archive" => return "archive_asset_consume"
            case "tag_icon" => return "tag_asset_consume"
            case "tag_background" => return "tag_asset_consume"
            case "user_avatar" => return "avatar_asset_consume"
            case "metadata_asset" => return "metadata_asset_consume"
            case "plugin" => return "plugin_asset_consume"
            case _ => return ""
        }
    }

    private static func resolveConsumeTaskName(targetType: String): String {
        match (targetType) {
            case "archive" => return "消费档案上传资产"
            case "tag_icon" => return "消费标签图标上传资产"
            case "tag_background" => return "消费标签背景上传资产"
            case "user_avatar" => return "消费头像上传资产"
            case "metadata_asset" => return "消费元数据上传资产"
            case "plugin" => return "消费插件上传资产"
            case _ => return "消费上传资产"
        }
    }

    private static func buildConsumeParams(
        stagingAssetId: Int64,
        targetType: String,
        targetId: String,
        categoryId: String,
        filename: String,
        overwrite: Bool,
        uploadUserId: Int64
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("staging_asset_id").writeValue(stagingAssetId.toString())
        w.writeName("target_type").writeValue(targetType)
        w.writeName("target_id").writeValue(targetId)
        w.writeName("category_id").writeValue(categoryId)
        w.writeName("filename").writeValue(filename)
        w.writeName("overwrite").writeValue(if (overwrite) { "true" } else { "false" })
        w.writeName("upload_user_id").writeValue(uploadUserId.toString())
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func cleanupStagingAsset(assetId: Int64, assetRoot: String, ext: String): Unit {
        if (assetId <= 0) {
            return
        }
        try {
            let filePath = FileUtils.joinPath(assetRoot, "${assetId}.${ext}")
            if (exists(Path(filePath))) {
                try { remove(Path(filePath)) } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        let _ = AssetDao.deleteById(assetId)
    }

    private static func cleanupUploadKV(taskId: Int64): Unit {
        TaskGroupKVDao.deleteGroup("asset_upload:${taskId.toString()}")
    }

    private static func fail(taskId: Int64, message: String): Unit {
        cleanupUploadKV(taskId)
        TaskRunnerOutput.fail(taskId, message)
    }
}
