package lanlu.task_runners

import std.collection.*
import std.convert.*
import stdx.log.*
import std.fs.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*

/**
 * 批量重生成封面任务：
 * - 先从 DB 按条件筛选档案
 * - （可选）清理旧封面资产/字段
 * - fan-out 派发 generate_thumbnail 子任务，让 TaskPool 并发执行
 *
 * 说明：该任务本身不等待子任务完成（与 scan_archive/metadata_plugin 一致）。
 */
public class RegenerateCoverTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("regenerate_cover_task")
        TaskIO.appendLog(taskId, "regenerate_cover task started")

        let (mode, batchSize, deleteOldCover) = parseParameters(parameters)
        TaskIO.appendLog(taskId, "Parameters: mode=${mode}, batchSize=${batchSize.toString()}, deleteOldCover=${deleteOldCover}")

        try {
            var submitted: Int64 = 0
            var skipped: Int64 = 0
            var deletedAssets: Int64 = 0
            var candidates: Int64 = 0

            TaskModel.updateTaskProgress(taskId, 5, "Dispatching thumbnail jobs (mode=${mode})")

            // Cursor-based scan so "mode=all" can truly cover all archives.
            var cursorId: Int64 = 0
            while (true) {
                let rows = ArchiveDao.getArchivesForCoverRegeneration(mode, batchSize, cursorId)
                if (rows.size == 0) {
                    break
                }

                candidates += Int64(rows.size)

                for (i in 0..rows.size) {
                    let row = rows[i]
                    if (row.archiveInternalId > cursorId) {
                        cursorId = row.archiveInternalId
                    }

                    let archiveId = row.archiveId.trimAscii()
                    if (archiveId.size == 0) {
                        skipped += 1
                        continue
                    }

                    if (row.categoryScanPath.trimAscii().size == 0) {
                        TaskIO.appendLog(taskId, "SKIP archive=${archiveId}: category scan_path is empty")
                        skipped += 1
                        continue
                    }

                    // Best-effort cleanup to force a real regeneration (avoid GenerateThumbnail fast-path).
                    if (deleteOldCover) {
                        try {
                            let _ = ArchiveDao.updateThumbHash(archiveId, "")

                            if (row.coverAssetId > 0) {
                                let assetFilePath = FileUtils.joinPath(context.paths.assetPath, "${row.coverAssetId}.avif")
                                let removed = FileUtils.removeFileOrDirectory(assetFilePath)
                                if (!removed) {
                                    TaskIO.appendLog(taskId, "WARN: failed to delete cover file ${assetFilePath} (archive=${archiveId})")
                                }

                                let _ = ArchiveDao.updateCoverAssetId(archiveId, 0)
                                let deleted = AssetDao.deleteById(row.coverAssetId)
                                if (!deleted) {
                                    TaskIO.appendLog(taskId, "WARN: failed to delete asset row id=${row.coverAssetId} (archive=${archiveId})")
                                }
                                deletedAssets += 1
                            } else {
                                let _ = ArchiveDao.updateCoverAssetId(archiveId, 0)
                            }
                        } catch (e: Exception) {
                            TaskIO.appendLog(taskId, "WARN: cleanup failed for archive=${archiveId}: ${e.message}")
                        }
                    }

                    // Rebuild full file path: {category.scan_path}/{relative_path?}/{filename}
                    var baseDir = row.categoryScanPath
                    let rel = row.relativePath.trimAscii()
                    if (rel.size > 0) {
                        baseDir = FileUtils.joinPath(baseDir, rel)
                    }
                    let filePath = FileUtils.joinPath(baseDir, row.filename)

                    // If the file is gone, generating will fail; skip early for a cleaner batch run.
                    if (!exists(Path(filePath))) {
                        TaskIO.appendLog(taskId, "SKIP archive=${archiveId}: file not found at ${filePath}")
                        skipped += 1
                        continue
                    }

                    let paramsOut = ByteBuffer()
                    let paramsW = JsonWriter(paramsOut)
                    paramsW.startObject()
                    paramsW.writeName("archive_path").writeValue(filePath)
                    paramsW.writeName("archive_id").writeValue(archiveId)
                    paramsW.writeName("type").writeValue(row.archiveType)
                    paramsW.endObject()
                    paramsW.flush()
                    let params = String.fromUtf8(readToEnd(paramsOut))
                    let child = TaskModel.createTaskWithOptions(
                        "生成封面",
                        "generate_thumbnail",
                        params,
                        10i32,
                        archiveId,
                        "regenerate_cover:${taskId}"
                    )

                    if (child.id > 0) {
                        submitted += 1
                        context.notifyTaskAvailable()
                    } else {
                        TaskIO.appendLog(taskId, "WARN: failed to enqueue generate_thumbnail for archive=${archiveId}")
                        skipped += 1
                    }
                }

                // We don't know total upfront; keep it moving and always leave room for terminal 100%.
                TaskModel.updateTaskProgress(taskId, 90, "Dispatched ${submitted} thumbnail tasks (scanned=${candidates})")
            }

            let resultOut = ByteBuffer()
            let resultW = JsonWriter(resultOut)
            resultW.startObject()
            resultW.writeName("success").writeValue(1)
            resultW.writeName("mode").writeValue(mode)
            resultW.writeName("candidates").writeValue(candidates)
            resultW.writeName("submitted").writeValue(submitted)
            resultW.writeName("skipped").writeValue(skipped)
            resultW.writeName("deleted_assets").writeValue(deletedAssets)
            resultW.endObject()
            resultW.flush()
            let resultJson = String.fromUtf8(readToEnd(resultOut))
            TaskModel.updateTaskProgress(taskId, 100, "Dispatched ${submitted} thumbnail tasks")
            TaskModel.completeTask(taskId, resultJson)
            TaskIO.writeOutput(taskId, resultJson)
        } catch (e: Exception) {
            logger.error("regenerate_cover failed", ("error", e.message))
            fail(taskId, e.message)
        }
    }

    private static func parseParameters(parameters: String): (String, Int32, Bool) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            // Default for "click in cron": do a real full regeneration.
            return ("all", 200i32, true)
        }

        var mode = "missing"
        var batchSize: Int32 = 200
        var deleteOldCover = false

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }
            func readInt32Flexible(): Int32 {
                let s = r.readValue<String>().trimAscii()
                try { return Int32.parse(s) } catch (_: Exception) { return 0i32 }
            }

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "mode" => mode = r.readValue<String>().trimAscii()
                        case "batchSize" =>
                            let parsed = readInt32Flexible()
                            if (parsed > 0) { batchSize = parsed }
                        case "limit" =>
                            // Backward compat: treat limit as batchSize.
                            let parsed = readInt32Flexible()
                            if (parsed > 0) { batchSize = parsed }
                        case "deleteOldCover" => deleteOldCover = readBoolFlexible()
                        case "delete_old_cover" => deleteOldCover = readBoolFlexible()
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        // Sensible default: if the user explicitly asks for "all", assume they want a real regen.
        if (mode == "all" && !deleteOldCover) {
            deleteOldCover = true
        }
        if (batchSize < 1i32) { batchSize = 1i32 }
        if (batchSize > 5000i32) { batchSize = 5000i32 }
        if (mode.size == 0) { mode = "missing" }
        return (mode, batchSize, deleteOldCover)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(0)
        w.writeName("error").writeValue(msg)
        w.endObject()
        w.flush()
        TaskIO.writeOutput(taskId, String.fromUtf8(readToEnd(out)))
    }

}
