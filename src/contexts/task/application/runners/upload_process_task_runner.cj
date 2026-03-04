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
import lanlu.contexts.task.infrastructure.persistence.TaskGroupKVDao

/**
 * upload_process 任务执行器：对已落盘的archive文件进行入库/缩略图处理
 * 重构后：创建 scan_archive 子任务，由 TaskPool 异步处理
 */
public class UploadProcessTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("upload_process_task")
        TaskIO.appendLog(taskId, "upload_process task started")

        var archivePath = parseField(parameters, "archive_path")
        var relativePath = parseField(parameters, "relative_path")
        var fileName = parseField(parameters, "filename")
        let categoryId = parseField(parameters, "category_id")
        let chunkDirStr = parseField(parameters, "chunk_dir")
        let finalPartPathStr = parseField(parameters, "final_part_path")
        let fileSize = parseInt64Safely(parseField(parameters, "file_size"))
        let overwrite = parseBool(parseField(parameters, "overwrite"))

        let finalizeMode = finalPartPathStr.size > 0

        // 异步落盘：当传入 final_part_path 时，在 TaskPool 内完成移动/拷贝
        if (finalizeMode) {
            TaskModel.updateTaskProgress(taskId, 75, "文件落盘中")
            TaskIO.appendLog(taskId, "upload_process finalize start: ${finalPartPathStr}")

            if (fileName.size == 0) {
                fail(taskId, "filename is required for finalize")
                return
            }

            if (archivePath.size == 0) {
                if (categoryId.size == 0) {
                    fail(taskId, "category_id is required for finalize")
                    return
                }
                let internalId = try {
                    Int64.parse(categoryId)
                } catch (_: Exception) {
                    CategoryDao.getInternalId(categoryId)
                }
                let categoryOpt = CategoryDao.getCategoryByInternalId(internalId)
                match (categoryOpt) {
                    case Some(cat) => archivePath = "${cat.scanPath}/${fileName}"
                    case None =>
                        fail(taskId, "Category not found")
                        return
                }
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

            let finalArchivePath = Path(archivePath)
            let archiveDir = finalArchivePath.parent
            if (archiveDir.toString().size > 0 && !exists(archiveDir)) {
                Directory.create(archiveDir, recursive: true)
            }

            if (exists(finalArchivePath)) {
                if (overwrite) {
                    try {
                        remove(finalArchivePath)
                    } catch (e: Exception) {
                        fail(taskId, "Failed to delete existing file: ${e.message}")
                        return
                    }
                } else {
                    fail(taskId, "File already exists: ${finalArchivePath.toString()}")
                    return
                }
            }

            try {
                try {
                    rename(finalPartPath, to: finalArchivePath)
                } catch (e: Exception) {
                    if (e.message.contains("cross-device") || e.message.contains("Invalid cross-device link")) {
                        copy(finalPartPath, to: finalArchivePath, overwrite: false)
                        remove(finalPartPath)
                    } else {
                        throw e
                    }
                }
                if (!exists(finalArchivePath)) {
                    throw Exception("final file missing after move")
                }
            } catch (e: Exception) {
                if (exists(finalArchivePath)) {
                    try { remove(finalArchivePath) } catch (_) {}
                }
                fail(taskId, "Failed to move file: ${e.message}")
                return
            }

            // 清理上传临时目录
            if (chunkDirStr.size > 0) {
                try {
                    let chunkDir = Path(chunkDirStr)
                    if (exists(chunkDir)) {
                        remove(chunkDir, recursive: true)
                    }
                } catch (_: Exception) {}
            }

            // canonicalize 失败时回退到相对路径
            try {
                archivePath = canonicalize(finalArchivePath.toString()).toString()
            } catch (_: Exception) {
                archivePath = finalArchivePath.toString()
            }
            relativePath = finalArchivePath.toString()
            TaskModel.updateTaskProgress(taskId, 85, "文件落盘完成")
        }

        if (archivePath.size == 0) {
            fail(taskId, "archive_path is required")
            return
        }
        if (categoryId.size == 0) {
            fail(taskId, "category_id is required")
            return
        }

        try {
            let scanProgress = if (finalizeMode) { 90i32 } else { 50i32 }
            TaskModel.updateTaskProgress(taskId, scanProgress, "创建档案扫描任务")

            // 创建 scan_archive 子任务（优先级 20，高于定时扫描）
            let scanOut = ByteBuffer()
            let scanW = JsonWriter(scanOut)
            scanW.startObject()
            scanW.writeName("archive_path").writeValue(archivePath)
            // category_id is passed as string sometimes; keep as raw string value.
            scanW.writeName("category_id").writeValue(categoryId)
            scanW.endObject()
            scanW.flush()
            let scanParams = String.fromUtf8(readToEnd(scanOut))
            let groupId = "upload:${taskId}"
            let scanTask = TaskModel.createTaskWithOptions(
                "扫描上传档案",
                "scan_archive",
                scanParams,
                20, // 上传任务优先级为 20
                groupId,
                "upload"
            )

            if (scanTask.id > 0) {
                context.notifyTaskAvailable()
                logger.debug("Created scan_archive task for upload", ("scan_task_id", scanTask.id.toString()), ("archive_path", archivePath))

                let okOut = ByteBuffer()
                let okW = JsonWriter(okOut)
                okW.startObject()
                okW.writeName("success").writeValue(1)
                okW.writeName("scan_task_id").writeValue(scanTask.id)
                okW.writeName("relative_path").writeValue(relativePath)
                okW.writeName("filename").writeValue(fileName)
                okW.writeName("message").writeValue("Archive scan task created")
                okW.endObject()
                okW.flush()
                let okJson = String.fromUtf8(readToEnd(okOut))
                TaskModel.updateTaskProgress(taskId, 100, "档案扫描任务已创建")
                TaskModel.completeTask(taskId, "upload_process completed, scan_archive task created")
                TaskIO.writeOutput(taskId, okJson)
                TaskIO.appendLog(taskId, "upload_process task completed: scan_task_id=${scanTask.id}")
                cleanupUploadKV(taskId)
            } else {
                fail(taskId, "Failed to create scan_archive task")
            }
        } catch (e: Exception) {
            logger.error("upload_process exception", ("error", e.message))
            fail(taskId, e.message)
        }
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

    private static func cleanupUploadKV(taskId: Int64): Unit {
        TaskGroupKVDao.deleteGroup("upload:${taskId.toString()}")
    }

    private static func fail(taskId: Int64, message: String): Unit {
        cleanupUploadKV(taskId)
        TaskRunnerOutput.fail(taskId, message)
    }
}
