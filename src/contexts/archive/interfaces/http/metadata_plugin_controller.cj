package lanlu.contexts.archive.interfaces.http
import lanlu.contexts.tankoubon.infrastructure.persistence.*

import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import ignite.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.application.*
import lanlu.shared.utils.*

/**
 * 元数据插件执行控制器
 * 负责创建 taskpool 任务并返回 job id，前端通过 /api/taskpool/{id} 查询进度与结果
 */
public class MetadataPluginController {
    private static func readRawJson(r: JsonReader): String {
        match (r.peek()) {
            case Some(BeginObject) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(BeginArray) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(_) =>
                return r.readValue<String>()
            case None =>
                return ""
        }
    }

    private static func readBoolFlexible(r: JsonReader): Bool {
        let v = r.readValue<String>().trimAscii().toAsciiLower()
        return v == "true" || v == "1" || v == "yes" || v == "y"
    }

    private static func normalizeMetadataJson(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() == Some(BeginObject)) {
                return trimmed
            }
        } catch (_: Exception) {}

        return ""
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
                var buf = ByteBuffer()
                unsafe { buf.write(trimmed.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    return (Option.None, Option<String>.Some(trimmed))
                }
            } catch (_: Exception) {}
        }

        return (Option<String>.Some(trimmed), Option.None)
    }

    /**
     * POST /api/metadata_plugin
     * 请求体: { "target_type": "archive|tankoubon", "target_id": "xxxx", "namespace": "ehplugin", "param": "...", "metadata": {...}, "write_back": 0|1 }
     * param 可选：若为 JSON 对象字符串，会作为 --params 覆盖/补充插件配置；否则作为 --oneshot 传入
     *
     * 语义分支：
     * - write_back=0（默认）：只运行 Metadata 插件，返回 deno_task 的 job id；不写回 archives/tags
     * - write_back=1：走 metadata_plugin + callback 流程，自动写回 archives/tags
     */
    public static func runMetadataPlugin(ctx: Ctx): Unit {
        let logger = getLogger("metadata_plugin_controller")

        try {
            let requestBody = ctx.bodyString()
            var targetType = ""
            var targetId = ""
            var namespace = ""
            var param = ""
            var metadataJson = ""
            var writeBack = false  // default: query/preview

            if (requestBody.trimAscii().size > 0) {
                try {
                    var buf = ByteBuffer()
                    unsafe { buf.write(requestBody.rawData()) }
                    let r = JsonReader(buf)

                    if (r.peek() == Some(BeginObject)) {
                        r.startObject()
                        while (r.peek() != EndObject) {
                            let k = r.readName()
                            match (k) {
                                case "target_type" => targetType = r.readValue<String>().trimAscii()
                                case "targetType" => targetType = r.readValue<String>().trimAscii()
                                case "target_id" => targetId = r.readValue<String>().trimAscii()
                                case "targetId" => targetId = r.readValue<String>().trimAscii()
                                case "namespace" => namespace = r.readValue<String>().trimAscii()
                                case "param" => param = readRawJson(r).trimAscii()
                                case "metadata" => metadataJson = normalizeMetadataJson(readRawJson(r))
                                case "write_back" => writeBack = readBoolFlexible(r)
                                case "writeBack" => writeBack = readBoolFlexible(r)
                                case _ => r.skip()
                            }
                        }
                        r.endObject()
                    }
                } catch (e: Exception) {
                    logger.warn("解析 metadata_plugin 请求JSON失败", ("error", e.message))
                }
            }

            // 兜底支持 query 参数（方便调试）
            if (targetType.size == 0) {
                targetType = ctx.query("target_type") ?? (ctx.query("targetType") ?? "")
            }
            if (targetId.size == 0) {
                let q1 = ctx.query("target_id") ?? ""
                let q2 = ctx.query("targetId") ?? ""
                if (q1.size > 0) { targetId = q1 }
                else if (q2.size > 0) { targetId = q2 }
                else { targetId = "" }
            }
            if (targetType.size == 0) {
                targetType = "archive"
            }
            if (namespace.size == 0) {
                namespace = ctx.query("namespace") ?? ""
            }
            if (param.size == 0) {
                param = ctx.query("param") ?? ""
            }
            if (metadataJson.size == 0) {
                let qMeta = ctx.query("metadata") ?? ""
                metadataJson = normalizeMetadataJson(qMeta)
            }
            let writeBackQuery = ctx.query("write_back") ?? (ctx.query("writeBack") ?? "")
            if (writeBackQuery.trimAscii().size > 0) {
                let v = writeBackQuery.trimAscii().toAsciiLower()
                writeBack = v == "true" || v == "1" || v == "yes" || v == "y"
            }

            if (targetId.size == 0 || namespace.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":0,\"error\":\"target_id and namespace are required\"}")
                return
            }

            let effectiveType = targetType.trimAscii().toAsciiLower()
            // 校验目标存在
            if (effectiveType == "tankoubon" || effectiveType == "tank") {
                match (TankoubonDao.getTankoubonById(targetId)) {
                    case Some(_) => ()
                    case None =>
                        ctx.status(404)
                        ctx.json("{\"success\":0,\"error\":\"tankoubon not found\"}")
                        return
                }
            } else {
                let archive = ArchiveDao.getArchiveById(targetId)
                if (archive.id.size == 0) {
                    ctx.status(404)
                    ctx.json("{\"success\":0,\"error\":\"archive not found\"}")
                    return
                }
            }

            if (writeBack) {
                // 写回模式：metadata_plugin + callback
                let task = TaskModel.createTask("元数据插件执行(写回)", "metadata_plugin")

                let paramsJson = if (requestBody.trimAscii().size > 0) {
                    requestBody
                } else {
                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    w.writeName("target_type").writeValue(effectiveType)
                    w.writeName("target_id").writeValue(targetId)
                    w.writeName("namespace").writeValue(namespace)
                    w.writeName("param").writeValue(param)
                    if (metadataJson.size > 0) {
                        w.writeName("metadata").jsonValue(metadataJson)
                    }
                    w.writeName("write_back").writeValue(1)
                    w.endObject()
                    w.flush()
                    String.fromUtf8(readToEnd(out))
                }

                TaskDao.updateTaskParameters(task.id, paramsJson)
                TaskIO.appendLog(task.id, "enqueued metadata_plugin(write_back=1) target_type=${effectiveType} target_id=${targetId} namespace=${namespace}")

                TaskPoolService.getInstance().notifyTaskAvailable()

                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("job").writeValue(task.id)
                w.writeName("operation").writeValue("metadata_plugin")
                w.writeName("task_type").writeValue("metadata_plugin")
                w.writeName("write_back").writeValue(1)
                w.writeName("success").writeValue(1)
                w.writeName("target_type").writeValue(effectiveType)
                w.writeName("target_id").writeValue(targetId)
                w.writeName("namespace").writeValue(namespace)
                w.endObject()
                w.flush()
                ctx.json(String.fromUtf8(readToEnd(out)))
                return
            }

            // 预览/查询模式：只跑 deno_task，前端直接读取 deno_task 的 output（不写库）
            let (oneshotOpt, extraParamsOpt) = splitParam(param)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("pluginNamespace").writeValue(namespace)
            w.writeName("pluginType").writeValue("Metadata")
            w.writeName("action").writeValue("run")
            w.writeName("targetType").writeValue(effectiveType)
            w.writeName("targetId").writeValue(targetId)
            match (oneshotOpt) {
                case Some(v) => w.writeName("oneshotParam").writeValue(v)
                case None => ()
            }
            match (extraParamsOpt) {
                case Some(v) => w.writeName("extraParams").writeValue(v)
                case None => ()
            }
            if (metadataJson.size > 0) {
                w.writeName("metadata").jsonValue(metadataJson)
            }
            // groupId 仅用于任务运行期共享 KV（默认语义下任务结束会清理整组），这里用 archiveId 便于同归档并发共享。
            w.writeName("groupId").writeValue(targetId)
            w.endObject()
            w.flush()
            let denoParams = String.fromUtf8(readToEnd(out))

            let denoTask = TaskModel.createTaskWithOptions(
                "元数据插件执行(预览)",
                "deno_task",
                denoParams,
                50,
                targetId,
                "metadata_plugin_preview"
            )

            if (denoTask.id <= 0) {
                ctx.status(500)
                ctx.json("{\"success\":0,\"error\":\"failed to create deno_task\"}")
                return
            }

            TaskIO.appendLog(denoTask.id, "enqueued deno_task(metadata preview) target_type=${effectiveType} target_id=${targetId} namespace=${namespace}")
            TaskPoolService.getInstance().notifyTaskAvailable()

            let out2 = ByteBuffer()
            let w2 = JsonWriter(out2)
            w2.startObject()
            w2.writeName("job").writeValue(denoTask.id)
            w2.writeName("operation").writeValue("metadata_preview")
            w2.writeName("task_type").writeValue("deno_task")
            w2.writeName("write_back").writeValue(0)
            w2.writeName("success").writeValue(1)
            w2.writeName("target_type").writeValue(effectiveType)
            w2.writeName("target_id").writeValue(targetId)
            w2.writeName("namespace").writeValue(namespace)
            w2.endObject()
            w2.flush()
            ctx.json(String.fromUtf8(readToEnd(out2)))
        } catch (e: Exception) {
            logger.error("metadata_plugin 处理异常", ("error", e.message))
            ctx.status(500)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(0)
            w.writeName("error").writeValue(e.message)
            w.endObject()
            w.flush()
            ctx.json(String.fromUtf8(readToEnd(out)))
        }
    }
}
