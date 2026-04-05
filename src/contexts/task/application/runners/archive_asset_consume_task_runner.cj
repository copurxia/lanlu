package lanlu.contexts.task.application.runners

import stdx.log.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.convert.*
import std.fs.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.asset.infrastructure.persistence.*

/**
 * archive_asset_consume：消费 staging asset，落盘为 archive 文件并触发 scan_archive。
 */
public class ArchiveAssetConsumeTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("archive_asset_consume_task")
        TaskIO.appendLog(taskId, "archive_asset_consume task started")

        let stagingAssetId = TaskRunnerUtils.parseInt64Safely(TaskRunnerUtils.parseField(parameters, "staging_asset_id"))
        let targetType = TaskRunnerUtils.parseField(parameters, "target_type").trimAscii().toAsciiLower()
        let categoryId = TaskRunnerUtils.parseField(parameters, "category_id")
        let filename = TaskRunnerUtils.parseField(parameters, "filename")
        let overwrite = parseBool(TaskRunnerUtils.parseField(parameters, "overwrite"))
        let finalPartPathStr = TaskRunnerUtils.parseField(parameters, "final_part_path")
        let chunkDirStr = TaskRunnerUtils.parseField(parameters, "chunk_dir")

        if (targetType != "archive") {
            TaskRunnerUtils.fail(taskId, "target_type must be archive")
            return
        }
        if (filename.size == 0) {
            TaskRunnerUtils.fail(taskId, "filename is required")
            return
        }
        if (categoryId.size == 0) {
            TaskRunnerUtils.fail(taskId, "category_id is required")
            return
        }

        // 确定源文件路径：直连模式 (final_part_path) 或传统 staging 模式
        var sourceFilePath: String = ""
        var usingStagingAsset = false

        if (finalPartPathStr.size > 0 && stagingAssetId <= 0) {
            // 直连落盘模式：跳过 staging，直接从 final.part 落盘
            if (!exists(Path(finalPartPathStr))) {
                TaskRunnerUtils.fail(taskId, "final_part file not found")
                return
            }
            sourceFilePath = finalPartPathStr
        } else {
            // 传统 staging asset 模式
            if (stagingAssetId <= 0) {
                TaskRunnerUtils.fail(taskId, "staging_asset_id is required")
                return
            }
            usingStagingAsset = true
            let staging = AssetDao.getById(stagingAssetId)
            if (staging.id <= 0) {
                TaskRunnerUtils.fail(taskId, "staging asset not found")
                return
            }
            let ext = TaskRunnerUtils.resolveAssetExt(staging, filename)
            let assetRoot = context.paths.assetPath
            sourceFilePath = FileUtils.joinPath(assetRoot, "${stagingAssetId}.${ext}")
            if (!exists(Path(sourceFilePath))) {
                let _ = AssetDao.deleteById(stagingAssetId)
                TaskRunnerUtils.fail(taskId, "staging asset file missing")
                return
            }
        }

        let internalId = try {
            Int64.parse(categoryId)
        } catch (_: Exception) {
            CategoryDao.getInternalId(categoryId)
        }
        let categoryOpt = CategoryDao.getCategoryByInternalId(internalId)
        let category = match (categoryOpt) {
            case Some(cat) => cat
            case None =>
                if (usingStagingAsset) {
                    TaskRunnerUtils.cleanupStagingAssetByPath(stagingAssetId, sourceFilePath)
                }
                TaskRunnerUtils.fail(taskId, "Category not found")
                return
        }

        let finalArchivePath = Path("${category.scanPath}/${filename}")
        let archiveDir = finalArchivePath.parent
        if (archiveDir.toString().size > 0 && !exists(archiveDir)) {
            Directory.create(archiveDir, recursive: true)
        }

        if (exists(finalArchivePath)) {
            if (!overwrite) {
                if (usingStagingAsset) {
                    TaskRunnerUtils.cleanupStagingAssetByPath(stagingAssetId, sourceFilePath)
                }
                TaskRunnerUtils.fail(taskId, "File already exists: ${finalArchivePath.toString()}")
                return
            }
            try {
                remove(finalArchivePath)
            } catch (e: Exception) {
                if (usingStagingAsset) {
                    TaskRunnerUtils.cleanupStagingAssetByPath(stagingAssetId, sourceFilePath)
                }
                TaskRunnerUtils.fail(taskId, "Failed to delete existing file: ${e.message}")
                return
            }
        }

        TaskModel.updateTaskProgress(taskId, 60, "写入档案文件")
        try {
            try {
                rename(Path(sourceFilePath), to: finalArchivePath)
            } catch (e: Exception) {
                if (e.message.contains("cross-device") || e.message.contains("Invalid cross-device link")) {
                    copy(Path(sourceFilePath), to: finalArchivePath, overwrite: false)
                    remove(Path(sourceFilePath))
                } else {
                    throw e
                }
            }
            if (!exists(finalArchivePath)) {
                throw Exception("final archive missing after move")
            }
        } catch (e: Exception) {
            TaskRunnerUtils.fail(taskId, "Failed to move archive file: ${e.message}")
            return
        }

        // 清理：根据模式分别处理
        if (usingStagingAsset) {
            let _ = AssetDao.deleteById(stagingAssetId)
        } else if (chunkDirStr.size > 0) {
            // 直连模式：清理上传临时目录
            try {
                let chunkDirPath = Path(chunkDirStr)
                if (exists(chunkDirPath)) {
                    remove(chunkDirPath, recursive: true)
                }
            } catch (_: Exception) {}
        }

        var archivePath = finalArchivePath.toString()
        try {
            archivePath = canonicalize(finalArchivePath.toString()).toString()
        } catch (_: Exception) {}

        TaskModel.updateTaskProgress(taskId, 85, "创建档案扫描任务")
        let scanOut = ByteBuffer()
        let scanW = JsonWriter(scanOut)
        scanW.startObject()
        scanW.writeName("archive_path").writeValue(archivePath)
        scanW.writeName("category_id").writeValue(categoryId)
        scanW.endObject()
        scanW.flush()
        let scanParams = String.fromUtf8(readToEnd(scanOut))

        let groupId = "asset_upload:${taskId}"
        let scanTask = TaskModel.createTaskWithOptions(
            "扫描上传档案",
            "scan_archive",
            scanParams,
            5,
            groupId,
            "asset_upload"
        )

        if (scanTask.id <= 0) {
            TaskRunnerUtils.fail(taskId, "Failed to create scan_archive task")
            return
        }

        context.notifyTaskAvailable()
        logger.debug("Created scan_archive task", ("scan_task_id", scanTask.id.toString()), ("archive_path", archivePath))

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("scan_task_id").writeValue(scanTask.id)
        w.writeName("archive_path").writeValue(archivePath)
        w.endObject()
        w.flush()
        let okJson = String.fromUtf8(readToEnd(out))

        TaskModel.updateTaskProgress(taskId, 100, "档案扫描任务已创建")
        TaskModel.completeTask(taskId, "archive_asset_consume completed")
        TaskIO.writeOutput(taskId, okJson)
        TaskIO.appendLog(taskId, "archive_asset_consume completed: scan_task_id=${scanTask.id}")
    }

    private static func parseBool(value: String): Bool {
        let v = value.trimAscii().toAsciiLower()
        return v == "true" || v == "1" || v == "yes"
    }
}
