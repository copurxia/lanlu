package lrr4cj.controllers

import stdx.encoding.json.*
import stdx.log.*
import cjoy.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.services.*
import lrr4cj.utils.*

/**
 * 元数据插件执行控制器
 * 负责创建 taskpool 任务并返回 job id，前端通过 /api/taskpool/{id} 查询进度与结果
 */
public class MetadataPluginController {
    private static func jsonValueToString(value: JsonValue): String {
        match (value) {
            case s: JsonString => return s.getValue()
            case _ => return value.toString()
        }
    }

    private static func getJsonString(obj: JsonObject, key: String): String {
        let fields = obj.getFields()
        if (!fields.contains(key)) {
            return ""
        }
        return jsonValueToString(fields[key]).trimAscii()
    }

    private static func escapeJsonString(str: String): String {
        var escaped = str
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }

    private static func jsonValueToBool(value: JsonValue): Bool {
        match (value) {
            case b: JsonBool => return b.getValue()
            case i: JsonInt => return i.getValue() != 0
            case s: JsonString =>
                let v = s.getValue().trimAscii().toAsciiLower()
                return v == "true" || v == "1" || v == "yes" || v == "y"
            case _ =>
                let v = value.toString().trimAscii().toAsciiLower().replace("\"", "")
                return v == "true" || v == "1" || v == "yes" || v == "y"
        }
    }

    /**
     * param 若是 JSON 对象字符串，则作为 extraParams；否则作为 oneshotParam
     */
    private static func splitParam(param: String): (Option<String>, Option<String>) {
        let trimmed = param.trimAscii()
        if (trimmed.size == 0) {
            return (Option.None, Option.None)
        }

        if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
            try {
                let jsonVal = JsonValue.fromStr(trimmed)
                match (jsonVal) {
                    case _: JsonObject =>
                        return (Option.None, Option<String>.Some(trimmed))
                    case _ => ()
                }
            } catch (_: Exception) {}
        }

        return (Option<String>.Some(trimmed), Option.None)
    }

    /**
     * POST /api/metadata_plugin
     * 请求体: { "archive_id": "xxxx", "namespace": "ehplugin", "param": "...", "write_back": 0|1, "mode": "query|write" }
     * param 可选：若为 JSON 对象字符串，会作为 --params 覆盖/补充插件配置；否则作为 --oneshot 传入
     *
     * 语义分支：
     * - write_back=0 / mode=query（默认）：只运行 Metadata 插件，返回 deno_task 的 job id；不写回 archives/tags
     * - write_back=1 / mode=write：走 metadata_plugin + callback 流程，自动写回 archives/tags
     */
    public static func runMetadataPlugin(ctx: JoyContext): Unit {
        let logger = getLogger("metadata_plugin_controller")

        try {
            let requestBody = ctx.readString()
            var archiveId = ""
            var namespace = ""
            var param = ""
            var writeBack = false  // default: query/preview

            if (requestBody.trimAscii().size > 0) {
                try {
                    let bodyJson = JsonValue.fromStr(requestBody)
                    match (bodyJson) {
                        case obj: JsonObject =>
                            archiveId = getJsonString(obj, "archive_id")
                            if (archiveId.size == 0) {
                                // 兼容：id
                                archiveId = getJsonString(obj, "id")
                            }
                            if (archiveId.size == 0) {
                                // 兼容：arcid / archiveId
                                archiveId = getJsonString(obj, "arcid")
                            }
                            if (archiveId.size == 0) {
                                archiveId = getJsonString(obj, "archiveId")
                            }
                            namespace = getJsonString(obj, "namespace")

                            // param 允许 string / object；object 则序列化为 JSON 字符串
                            let fields = obj.getFields()
                            if (fields.contains("param")) {
                                let pv = fields["param"]
                                match (pv) {
                                    case s: JsonString => param = s.getValue().trimAscii()
                                    case o: JsonObject => param = o.toString().trimAscii()
                                    case _ => param = pv.toString().trimAscii()
                                }
                            }

                            // write_back / mode（可选）
                            if (fields.contains("write_back")) {
                                writeBack = jsonValueToBool(fields["write_back"])
                            } else if (fields.contains("writeBack")) {
                                writeBack = jsonValueToBool(fields["writeBack"])
                            }
                            if (fields.contains("mode")) {
                                let mode = jsonValueToString(fields["mode"]).trimAscii().toAsciiLower().replace("\"", "")
                                if (mode == "write" || mode == "persist" || mode == "save" || mode == "apply") {
                                    writeBack = true
                                } else if (mode == "query" || mode == "preview" || mode == "dry_run" || mode == "dryrun") {
                                    writeBack = false
                                }
                            }
                        case _ => ()
                    }
                } catch (e: Exception) {
                    logger.warn("解析 metadata_plugin 请求JSON失败", ("error", e.message))
                }
            }

            // 兜底支持 query 参数（方便调试）
            if (archiveId.size == 0) {
                archiveId = ctx.getQuery("archive_id") ?? (ctx.getQuery("id") ?? "")
            }
            if (namespace.size == 0) {
                namespace = ctx.getQuery("namespace") ?? ""
            }
            if (param.size == 0) {
                param = ctx.getQuery("param") ?? ""
            }
            let writeBackQuery = ctx.getQuery("write_back") ?? (ctx.getQuery("writeBack") ?? "")
            if (writeBackQuery.trimAscii().size > 0) {
                let v = writeBackQuery.trimAscii().toAsciiLower()
                writeBack = v == "true" || v == "1" || v == "yes" || v == "y"
            }
            let modeQuery = ctx.getQuery("mode") ?? ""
            if (modeQuery.trimAscii().size > 0) {
                let mode = modeQuery.trimAscii().toAsciiLower()
                if (mode == "write" || mode == "persist" || mode == "save" || mode == "apply") {
                    writeBack = true
                } else if (mode == "query" || mode == "preview" || mode == "dry_run" || mode == "dryrun") {
                    writeBack = false
                }
            }

            if (archiveId.size == 0 || namespace.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":0,\"error\":\"archive_id and namespace are required\"}")
                return
            }

            // 校验归档存在
            let archive = ArchiveDao.getArchiveById(archiveId)
            if (archive.id.size == 0) {
                ctx.status(404)
                ctx.json("{\"success\":0,\"error\":\"archive not found\"}")
                return
            }

            if (writeBack) {
                // 写回模式：metadata_plugin + callback
                let task = TaskModel.createTask("元数据插件执行(写回)", "metadata_plugin")

                let paramsJson = if (requestBody.trimAscii().size > 0) {
                    requestBody
                } else {
                    "{" +
                    "\"archive_id\":\"${escapeJsonString(archiveId)}\"," +
                    "\"namespace\":\"${escapeJsonString(namespace)}\"," +
                    "\"param\":\"${escapeJsonString(param)}\"," +
                    "\"write_back\":1" +
                    "}"
                }

                TaskDao.updateTaskParameters(task.id, paramsJson)
                TaskIO.appendLog(task.id, "enqueued metadata_plugin(write_back=1) archive_id=${archiveId} namespace=${namespace}")

                TaskPoolService.getInstance().notifyTaskAvailable()

                let response =
                    "{" +
                    "\"job\":${task.id}," +
                    "\"operation\":\"metadata_plugin\"," +
                    "\"task_type\":\"metadata_plugin\"," +
                    "\"write_back\":1," +
                    "\"success\":1," +
                    "\"archive_id\":\"${escapeJsonString(archiveId)}\"," +
                    "\"namespace\":\"${escapeJsonString(namespace)}\"" +
                    "}"
                ctx.json(response)
                return
            }

            // 预览/查询模式：只跑 deno_task，前端直接读取 deno_task 的 output（不写库）
            let (oneshotOpt, extraParamsOpt) = splitParam(param)

            var paramsObj = JsonObject()
            let fields = paramsObj.getFields()
            fields["pluginNamespace"] = JsonString(namespace)
            fields["pluginType"] = JsonString("Metadata")
            fields["action"] = JsonString("run")
            fields["archiveId"] = JsonString(archiveId)
            match (oneshotOpt) {
                case Some(v) => fields["oneshotParam"] = JsonString(v)
                case None => ()
            }
            match (extraParamsOpt) {
                case Some(v) => fields["extraParams"] = JsonString(v)
                case None => ()
            }

            // groupId 仅用于任务运行期共享 KV（默认语义下任务结束会清理整组），这里用 archiveId 便于同归档并发共享。
            fields["groupId"] = JsonString(archiveId)
            let denoParams = paramsObj.toString()

            let denoTask = TaskModel.createTaskWithOptions(
                "元数据插件执行(预览)",
                "deno_task",
                denoParams,
                50,
                archiveId,
                "metadata_plugin_preview"
            )

            if (denoTask.id <= 0) {
                ctx.status(500)
                ctx.json("{\"success\":0,\"error\":\"failed to create deno_task\"}")
                return
            }

            TaskIO.appendLog(denoTask.id, "enqueued deno_task(metadata preview) archive_id=${archiveId} namespace=${namespace}")
            TaskPoolService.getInstance().notifyTaskAvailable()

            let response =
                "{" +
                "\"job\":${denoTask.id}," +
                "\"operation\":\"metadata_preview\"," +
                "\"task_type\":\"deno_task\"," +
                "\"write_back\":0," +
                "\"success\":1," +
                "\"archive_id\":\"${escapeJsonString(archiveId)}\"," +
                "\"namespace\":\"${escapeJsonString(namespace)}\"" +
                "}"
            ctx.json(response)
        } catch (e: Exception) {
            logger.error("metadata_plugin 处理异常", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":0,\"error\":\"${escapeJsonString(e.message)}\"}")
        }
    }
}
