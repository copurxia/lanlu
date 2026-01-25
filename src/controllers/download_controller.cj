package lanlu.controllers

import std.collection.*
import stdx.log.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import cjoy.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.services.*
import lanlu.utils.*
import lanlu.views.*

/**
 * 处理下载URL的控制器
 * 负责匹配下载插件、调用插件并拉取文件到归档目录
 */
public class DownloadController {
    /**
     * POST /api/download_url
     * 请求体: { "url": "https://example.com/file.zip" }
     */
    public static func downloadFromUrl(ctx: JoyContext): Unit {
        let logger = getLogger("download_controller")

        try {
            let requestBody = ctx.readString()
            var url = ""

            if (requestBody.size > 0) {
                try {
                    var buf = ByteBuffer()
                    unsafe { buf.write(requestBody.rawData()) }
                    let r = JsonReader(buf)
                    match (r.peek()) {
                        case Some(BeginObject) =>
                            r.startObject()
                            while (r.peek() != EndObject) {
                                let n = r.readName()
                                match (n) {
                                    case "url" => url = r.readValue<String>().trimAscii()
                                    case _ => r.skip()
                                }
                            }
                            r.endObject()
                        case _ => ()
                    }
                } catch (e: Exception) {
                    logger.warn("解析下载请求JSON失败", ("error", e.message))
                }
            }

            if (url.size == 0) {
                url = ctx.getQuery("url") ?? ""
            }

            if (url.size == 0) {
                ctx.status(400)
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("success").writeValue(0)
                w.writeName("error").writeValue("url is required")
                w.endObject()
                w.flush()
                ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
                return
            }

            // 进入TaskPool：创建任务并立即返回job id，前端通过 /api/taskpool/{id} 查询进度与结果
            // 任务标题不携带参数（URL等），避免在任务列表里泄露/污染标题
            let task = TaskModel.createTask("文件上传（在线下载）", "download_url")
            let paramsJson = if (requestBody.trimAscii().size > 0) {
                requestBody
            } else {
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("url").writeValue(url)
                w.endObject()
                w.flush()
                String.fromUtf8(readToEnd(out))
            }
            TaskDao.updateTaskParameters(task.id, paramsJson)
            TaskIO.appendLog(task.id, "enqueued download_url url=${url}")

            // 唤醒 TaskPool 领取 pending（无轮询）
            TaskPoolService.getInstance().notifyTaskAvailable()

            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("job").writeValue(task.id)
            w.writeName("operation").writeValue("download_url")
            w.writeName("success").writeValue(1)
            w.writeName("url").writeValue(url)
            w.endObject()
            w.flush()
            ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
        } catch (e: Exception) {
            getLogger("download_controller").error("下载处理异常", ("error", e.message))
            ctx.status(500)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(0)
            w.writeName("error").writeValue(e.message)
            w.endObject()
            w.flush()
            ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
        }
    }



}
