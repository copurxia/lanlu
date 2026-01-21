package lrr4cj.task_runners

import std.collection.*
import std.convert.*
import stdx.encoding.json.*
import stdx.log.*
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

                        let params = "{\"archive_id\":\"${escapeJson(archiveId)}\",\"namespace\":\"${escapeJson(namespace)}\"}"
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
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("limit")) {
                        let v = jsonValueToString(fields["limit"]).trimAscii()
                        let parsed = try { Int32.parse(v) } catch (_: Exception) { 0i32 }
                        if (parsed > 0) { limit = parsed }
                    } else if (fields.contains("batchSize")) {
                        let v = jsonValueToString(fields["batchSize"]).trimAscii()
                        let parsed = try { Int32.parse(v) } catch (_: Exception) { 0i32 }
                        if (parsed > 0) { limit = parsed }
                    }
                    if (fields.contains("namespace")) {
                        namespaceOverride = jsonValueToString(fields["namespace"]).trimAscii()
                    } else if (fields.contains("pluginNamespace")) {
                        namespaceOverride = jsonValueToString(fields["pluginNamespace"]).trimAscii()
                    }
                case _ => ()
            }
        } catch (_: Exception) {}

        if (limit < 1i32) { limit = 1i32 }
        if (limit > 5000i32) { limit = 5000i32 }
        return (limit, namespaceOverride)
    }

    private static func parsePluginsArray(pluginsJson: String): Array<String> {
        var namespaces = ArrayList<String>()
        try {
            let jsonVal = JsonValue.fromStr(pluginsJson)
            match (jsonVal) {
                case arr: JsonArray =>
                    for (item in arr.getItems()) {
                        match (item) {
                            case s: JsonString =>
                                let v = s.getValue().trimAscii()
                                if (v.size > 0) { namespaces.add(v) }
                            case _ => ()
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {}
        return namespaces.toArray()
    }

    private static func jsonValueToString(value: JsonValue): String {
        match (value) {
            case s: JsonString => return s.getValue()
            case _ => return value.toString()
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(msg)}\"}")
    }

    private static func escapeJson(s: String): String {
        var escaped = s
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }
}
