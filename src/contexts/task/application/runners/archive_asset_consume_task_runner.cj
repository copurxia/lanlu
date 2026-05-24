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

        let scanArchivePath = resolveScanArchivePath(archivePath)
        if (scanArchivePath.size == 0) {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(1)
            w.writeName("scan_task_id").writeValue(0)
            w.writeName("archive_path").writeValue(archivePath)
            w.writeName("skipped").writeValue(1)
            w.endObject()
            w.flush()
            let okJson = String.fromUtf8(readToEnd(out))

            TaskModel.updateTaskProgress(taskId, 100, "分卷跟随片已落盘，等待入口分卷扫描")
            TaskModel.completeTask(taskId, "archive_asset_consume completed")
            TaskIO.writeOutput(taskId, okJson)
            TaskIO.appendLog(taskId, "archive_asset_consume completed: skipped follower volume ${archivePath}")
            return
        }

        TaskModel.updateTaskProgress(taskId, 85, "创建档案扫描任务")
        let scanOut = ByteBuffer()
        let scanW = JsonWriter(scanOut)
        scanW.startObject()
        scanW.writeName("archive_path").writeValue(scanArchivePath)
        scanW.writeName("category_id").writeValue(categoryId)
        match (VolumeArchiveUtils.detectVolume(scanArchivePath)) {
            case Some(info) =>
                scanW.writeName("archive_type").writeValue("archive")
                scanW.writeName("volume_pattern").writeValue(volumePatternToString(info.pattern))
                scanW.writeName("volume_display_name").writeValue(info.displayName)
                scanW.writeName("volume_total_size").writeValue(info.totalSize)
                scanW.writeName("volume_underlying_format").writeValue(info.underlyingFormat)
                scanW.writeName("volume_parts")
                scanW.startArray()
                for (part in info.parts) {
                    scanW.writeValue(part)
                }
                scanW.endArray()
            case None => ()
        }
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
        logger.debug("Created scan_archive task", ("scan_task_id", scanTask.id.toString()), ("archive_path", scanArchivePath))

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("scan_task_id").writeValue(scanTask.id)
        w.writeName("archive_path").writeValue(scanArchivePath)
        w.endObject()
        w.flush()
        let okJson = String.fromUtf8(readToEnd(out))

        TaskModel.updateTaskProgress(taskId, 100, "档案扫描任务已创建")
        TaskModel.completeTask(taskId, "archive_asset_consume completed")
        TaskIO.writeOutput(taskId, okJson)
        TaskIO.appendLog(taskId, "archive_asset_consume completed: scan_task_id=${scanTask.id}")
    }

    private static func resolveScanArchivePath(archivePath: String): String {
        if (!VolumeArchiveUtils.isVolumeFollower(archivePath)) {
            return archivePath
        }

        let lower = archivePath.toAsciiLower()
        if (lower.endsWith(".001")) {
            return archivePath
        }

        if (isSplitZipFollower(lower)) {
            let entryPath = archivePath[0..archivePath.size - 4] + ".z01"
            return resolveExistingVolumeEntry(entryPath)
        }

        if (isRarLegacyFollower(lower)) {
            let entryPath = archivePath[0..archivePath.size - 4] + ".rar"
            return resolveExistingVolumeEntry(entryPath)
        }

        match (resolveRarPartEntry(archivePath, lower)) {
            case Some(entryPath) => return resolveExistingVolumeEntry(entryPath)
            case None => ()
        }

        let dotPos = archivePath.lastIndexOf(".")
        match (dotPos) {
            case None => return ""
            case Some(pos) =>
                if (pos < 0 || pos >= archivePath.size - 1) {
                    return ""
                }
                let entryPath = "${archivePath[0..pos]}.001"
                return resolveExistingVolumeEntry(entryPath)
        }
    }

    private static func resolveExistingVolumeEntry(entryPath: String): String {
        if (!exists(Path(entryPath))) {
            return ""
        }
        match (VolumeArchiveUtils.detectVolume(entryPath)) {
            case Some(info) =>
                if (info.isEntry) {
                    return info.entryPath
                }
                return ""
            case None => return ""
        }
    }

    private static func isSplitZipFollower(lower: String): Bool {
        if (lower.size < 4) {
            return false
        }
        let ext = lower[lower.size - 4..lower.size]
        let dot = UInt8(UInt32(r'.'))
        let zChar = UInt8(UInt32(r'z'))
        let zero = UInt8(UInt32(r'0'))
        let nine = UInt8(UInt32(r'9'))
        if (ext[0] != dot || ext[1] != zChar || ext[2] < zero || ext[2] > nine || ext[3] < zero || ext[3] > nine) {
            return false
        }
        let num = parseDigits(ext[2..4])
        return num >= 2 && num <= 99
    }

    private static func isRarLegacyFollower(lower: String): Bool {
        if (lower.size < 4) {
            return false
        }
        let ext = lower[lower.size - 4..lower.size]
        let dot = UInt8(UInt32(r'.'))
        let rChar = UInt8(UInt32(r'r'))
        let zero = UInt8(UInt32(r'0'))
        let nine = UInt8(UInt32(r'9'))
        return ext[0] == dot && ext[1] == rChar && ext[2] >= zero && ext[2] <= nine && ext[3] >= zero && ext[3] <= nine
    }

    private static func resolveRarPartEntry(archivePath: String, lower: String): Option<String> {
        if (!lower.endsWith(".rar") && !lower.endsWith(".rev")) {
            return None
        }
        let extLen = 4
        let lowerBase = lower[0..lower.size - extLen]
        let partIdxOpt = lowerBase.lastIndexOf(".part")
        match (partIdxOpt) {
            case None => return None
            case Some(partIdx) =>
                let numStr = lowerBase[partIdx + 5..lowerBase.size]
                if (parseDigits(numStr) < 2) {
                    return None
                }
                var firstPartNumber = "1"
                if (numStr.size > 1) {
                    firstPartNumber = ""
                    for (_ in 0..(numStr.size - 1)) {
                        firstPartNumber += "0"
                    }
                    firstPartNumber += "1"
                }
                return Some(archivePath[0..partIdx] + ".part" + firstPartNumber + ".rar")
        }
    }

    private static func parseDigits(s: String): Int64 {
        var result: Int64 = 0
        for (r in s.toRuneArray()) {
            let code = UInt32(r)
            if (code < UInt32(r'0') || code > UInt32(r'9')) {
                return -1
            }
            result = result * 10 + Int64(code - UInt32(r'0'))
        }
        return result
    }

    private static func volumePatternToString(pattern: VolumePattern): String {
        match (pattern) {
            case VolumePattern.BinarySlice => return "binary_slice"
            case VolumePattern.SplitZip => return "split_zip"
            case VolumePattern.RarVolume => return "rar_volume"
            case VolumePattern.NotVolume => return ""
        }
    }

    private static func parseBool(value: String): Bool {
        let v = value.trimAscii().toAsciiLower()
        return v == "true" || v == "1" || v == "yes"
    }
}
