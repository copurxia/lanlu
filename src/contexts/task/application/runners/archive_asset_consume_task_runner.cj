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

        let stagingAssetId = parseInt64Safely(parseField(parameters, "staging_asset_id"))
        let targetType = parseField(parameters, "target_type").trimAscii().toAsciiLower()
        let categoryId = parseField(parameters, "category_id")
        let filename = parseField(parameters, "filename")
        let overwrite = parseBool(parseField(parameters, "overwrite"))

        if (targetType != "archive") {
            fail(taskId, "target_type must be archive")
            return
        }
        if (stagingAssetId <= 0) {
            fail(taskId, "staging_asset_id is required")
            return
        }
        if (filename.size == 0) {
            fail(taskId, "filename is required")
            return
        }
        if (categoryId.size == 0) {
            fail(taskId, "category_id is required")
            return
        }

        let staging = AssetDao.getById(stagingAssetId)
        if (staging.id <= 0) {
            fail(taskId, "staging asset not found")
            return
        }

        let ext = resolveAssetExt(staging, filename)
        let assetRoot = context.paths.assetPath
        let stagingPath = FileUtils.joinPath(assetRoot, "${stagingAssetId}.${ext}")
        if (!exists(Path(stagingPath))) {
            let _ = AssetDao.deleteById(stagingAssetId)
            fail(taskId, "staging asset file missing")
            return
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
                cleanupStagingAsset(stagingAssetId, stagingPath)
                fail(taskId, "Category not found")
                return
        }

        let finalArchivePath = Path("${category.scanPath}/${filename}")
        let archiveDir = finalArchivePath.parent
        if (archiveDir.toString().size > 0 && !exists(archiveDir)) {
            Directory.create(archiveDir, recursive: true)
        }

        if (exists(finalArchivePath)) {
            if (!overwrite) {
                cleanupStagingAsset(stagingAssetId, stagingPath)
                fail(taskId, "File already exists: ${finalArchivePath.toString()}")
                return
            }
            try {
                remove(finalArchivePath)
            } catch (e: Exception) {
                cleanupStagingAsset(stagingAssetId, stagingPath)
                fail(taskId, "Failed to delete existing file: ${e.message}")
                return
            }
        }

        TaskModel.updateTaskProgress(taskId, 60, "写入档案文件")
        try {
            try {
                rename(Path(stagingPath), to: finalArchivePath)
            } catch (e: Exception) {
                if (e.message.contains("cross-device") || e.message.contains("Invalid cross-device link")) {
                    copy(Path(stagingPath), to: finalArchivePath, overwrite: false)
                    remove(Path(stagingPath))
                } else {
                    throw e
                }
            }
            if (!exists(finalArchivePath)) {
                throw Exception("final archive missing after move")
            }
        } catch (e: Exception) {
            fail(taskId, "Failed to move archive file: ${e.message}")
            return
        }

        let _ = AssetDao.deleteById(stagingAssetId)

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
            20,
            groupId,
            "asset_upload"
        )

        if (scanTask.id <= 0) {
            fail(taskId, "Failed to create scan_archive task")
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

    private static func cleanupStagingAsset(assetId: Int64, stagingPath: String): Unit {
        try {
            if (exists(Path(stagingPath))) {
                try { remove(Path(stagingPath)) } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        let _ = AssetDao.deleteById(assetId)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}
