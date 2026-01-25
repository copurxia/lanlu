package lrr4cj.task_runners

import std.collection.*
import std.convert.*
import stdx.log.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

/**
 * 批量补全元数据任务：
 * - 筛选“只有 source 标签 / 完全无标签”的档案
 * - 按分类 plugins 配置 fan-out 派发 metadata_plugin 子任务
 *
 * 说明：该任务本身不等待子任务完成（与 scan_archive/metadata_plugin 一致）。
 */
public class BackfillMetadataTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("backfill_metadata_task")
        TaskIO.appendLog(taskId, "backfill_metadata task started")

        let (batchSize, namespaceOverride) = parseParameters(parameters)
        TaskIO.appendLog(taskId, "Parameters: batchSize=${batchSize.toString()}, namespaceOverride=${namespaceOverride}")

        try {
            var submitted: Int64 = 0
            var skipped: Int64 = 0
            var candidates: Int64 = 0

            TaskModel.updateTaskProgress(taskId, 5, "Dispatching metadata jobs")

            var cursorId: Int64 = 0
            while (true) {
                let rows = ArchiveDao.getArchivesNeedingMetadataBackfill(batchSize, cursorId)
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

                    let namespaces = if (namespaceOverride.size > 0) {
                        Array<String>(1, { _ => namespaceOverride })
                    } else {
                        // Default behavior: run ALL plugins selected in the category.
                        parsePluginsArray(row.categoryPlugins)
                    }

                    if (namespaces.size == 0) {
                        TaskIO.appendLog(taskId, "SKIP archive=${archiveId}: no metadata plugins configured for category_id=${row.categoryId.toString()}")
                        skipped += 1
                        continue
                    }

                    for (ns in namespaces) {
                        let namespace = ns.trimAscii()
                        if (namespace.size == 0) { continue }

                        let out = ByteBuffer()
                        let w = JsonWriter(out)
                        w.startObject()
                        w.writeName("archive_id").writeValue(archiveId)
                        w.writeName("namespace").writeValue(namespace)
                        w.endObject()
                        w.flush()
                        let params = String.fromUtf8(readToEnd(out))
                        let child = TaskModel.createTaskWithOptions(
                            "元数据补全: ${namespace}",
                            "metadata_plugin",
                            params,
                            15i32,
                            archiveId,
                            "backfill_metadata:${taskId}"
                        )

                        if (child.id > 0) {
                            submitted += 1
                            context.notifyTaskAvailable()
                        } else {
                            TaskIO.appendLog(taskId, "WARN: failed to enqueue metadata_plugin archive=${archiveId} namespace=${namespace}")
                            skipped += 1
                        }
                    }
                }

                TaskModel.updateTaskProgress(taskId, 90, "Dispatched ${submitted} metadata tasks (scanned=${candidates})")
            }

            let resultJson = "{\"success\":1,\"candidates\":${candidates},\"submitted\":${submitted},\"skipped\":${skipped}}"
            TaskModel.updateTaskProgress(taskId, 100, "Dispatched ${submitted} metadata tasks")
            TaskModel.completeTask(taskId, resultJson)
            TaskIO.writeOutput(taskId, resultJson)
        } catch (e: Exception) {
            logger.error("backfill_metadata failed", ("error", e.message))
            fail(taskId, e.message)
        }
    }

    private static func parseParameters(parameters: String): (Int32, String) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return (200i32, "")
        }

        var limit: Int32 = 200
        var namespaceOverride = ""

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readInt32Flexible(): Int32 {
                let s = r.readValue<String>().trimAscii()
                try { return Int32.parse(s) } catch (_: Exception) { return 0i32 }
            }

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "limit" =>
                            let parsed = readInt32Flexible()
                            if (parsed > 0) { limit = parsed }
                        case "batchSize" =>
                            let parsed = readInt32Flexible()
                            if (parsed > 0) { limit = parsed }
                        case "namespace" => namespaceOverride = r.readValue<String>().trimAscii()
                        case "pluginNamespace" => namespaceOverride = r.readValue<String>().trimAscii()
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        if (limit < 1i32) { limit = 1i32 }
        if (limit > 5000i32) { limit = 5000i32 }
        return (limit, namespaceOverride)
    }

    private static func parsePluginsArray(pluginsJson: String): Array<String> {
        var namespaces = ArrayList<String>()
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(pluginsJson.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginArray)) { return namespaces.toArray() }
            r.startArray()
            while (r.peek() != EndArray) {
                match (r.peek()) {
                    case Some(_) =>
                        let v = r.readValue<String>().trimAscii()
                        if (v.size > 0) { namespaces.add(v) }
                    case None => break
                }
            }
            r.endArray()
        } catch (_: Exception) {}
        return namespaces.toArray()
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
