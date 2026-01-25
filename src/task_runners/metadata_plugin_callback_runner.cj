package lanlu.task_runners

import std.convert.*
import std.time.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*

/**
 * metadata_plugin_callback 回调任务执行器
 * 在 deno_task 完成后被触发，负责读取插件输出并写回元数据
 */
public class MetadataPluginCallbackRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "metadata_plugin_callback task started")
        TaskModel.updateTaskProgress(taskId, 10, "开始处理元数据回调")

        // 解析参数
        let (archiveId, namespace, denoTaskId) = parseParameters(parameters)
        if (archiveId.size == 0 || denoTaskId <= 0) {
            fail(taskId, "Invalid callback parameters: missing archiveId or denoTaskId")
            return
        }

        TaskIO.appendLog(taskId, "callback params: archiveId=${archiveId}, namespace=${namespace}, denoTaskId=${denoTaskId}")

        // 读取 deno_task 输出
        TaskModel.updateTaskProgress(taskId, 30, "读取插件输出")
        let output = TaskIO.readOutput(denoTaskId)
        if (output.size == 0) {
            fail(taskId, "Deno task output is empty")
            return
        }
        TaskIO.appendLog(taskId, "plugin output: ${output}")

        // 解析元数据输出
        TaskModel.updateTaskProgress(taskId, 50, "解析元数据")
        let parsed = parseMetadataOutput(output)
        if (!parsed.success) {
            fail(taskId, parsed.error)
            return
        }

        let newTitle = parsed.title
        let newTags = parsed.tags
        let newSummary = parsed.summary

        // 写回 archives 表
        TaskModel.updateTaskProgress(taskId, 70, "写回元数据")
        var archiveToUpdate = ArchiveDao.getArchiveById(archiveId)
        if (archiveToUpdate.id.size == 0) {
            fail(taskId, "Archive not found when updating")
            return
        }

        var changed = false
        if (newTitle.size > 0) {
            archiveToUpdate.title = newTitle
            changed = true
        }
        if (newSummary.size > 0) {
            archiveToUpdate.summary = newSummary
            changed = true
        }
        if (changed) {
            archiveToUpdate.updated_at = DateTime.now().toString()
            let ok = ArchiveDao.update(archiveToUpdate)
            if (!ok) {
                fail(taskId, "Failed to update archive metadata")
                return
            }
        }

        // 写回 tags
        if (newTags.size > 0) {
            let tagOk = TagDao.updateArchiveTags(archiveId, newTags)
            if (!tagOk) {
                TaskIO.appendLog(taskId, "WARN: failed to update tags")
            }
        }

        // 完成任务
        TaskModel.updateTaskProgress(taskId, 100, "元数据回调完成")
        let resultJson = buildResultJson(archiveId, namespace, newTitle, newSummary, newTags, output)
        TaskModel.completeTask(taskId, "metadata_plugin_callback completed")
        TaskIO.writeOutput(taskId, resultJson)
    }

    private static func parseParameters(parameters: String): (String, String, Int64) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", 0)
        }

        var archiveId = ""
        var namespace = ""
        var denoTaskId: Int64 = 0

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readInt64Flexible(): Int64 {
                let s = r.readValue<String>().trimAscii()
                try { return Int64.parse(s) } catch (_: Exception) { return 0 }
            }

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                        case "namespace" => namespace = r.readValue<String>().trimAscii()
                        case "denoTaskId" => denoTaskId = readInt64Flexible()
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        return (archiveId, namespace, denoTaskId)
    }

    private static func parseMetadataOutput(output: String): ParsedMetadataResult {
        if (output.trimAscii().size == 0) {
            return ParsedMetadataResult(false, "Plugin returned empty output", "", "", "")
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            if (r.peek() != Some(BeginObject)) {
                return ParsedMetadataResult(false, "Plugin output is not a JSON object", "", "", "")
            }

            var successSeen = false
            var success = false
            var err = ""
            var title = ""
            var summary = ""
            var tags = ""

            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" =>
                        successSeen = true
                        success = readBoolFlexible()
                    case "error" =>
                        err = r.readValue<String>()
                    case "data" =>
                        match (r.peek()) {
                            case Some(BeginObject) =>
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let dk = r.readName()
                                    match (dk) {
                                        case "title" => title = r.readValue<String>()
                                        case "summary" => summary = r.readValue<String>()
                                        case "tags" => tags = r.readValue<String>()
                                        case _ => r.skip()
                                    }
                                }
                                r.endObject()
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (!successSeen || !success) {
                let msg = if (err.trimAscii().size > 0) { err.trimAscii() } else { "Plugin returned success=false" }
                return ParsedMetadataResult(false, msg, "", "", "")
            }
            return ParsedMetadataResult(true, "", title, summary, tags)
        } catch (e: Exception) {
            return ParsedMetadataResult(false, "Failed to parse plugin output: ${e.message}", "", "", "")
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

    private static func buildResultJson(archiveId: String, namespace: String, title: String, summary: String, tags: String, output: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("archive_id").writeValue(archiveId)
        w.writeName("namespace").writeValue(namespace)
        w.writeName("title").writeValue(title)
        w.writeName("summary").writeValue(summary)
        w.writeName("tags").writeValue(tags)
        w.writeName("plugin_output").writeValue(output)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

}
