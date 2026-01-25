package lanlu.task_runners

import std.collection.*
import std.convert.*
import std.fs.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.log.*
import stdx.encoding.json.stream.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*

/**
 * download_url_callback 回调任务执行器
 * 在 deno_task 结束后触发：读取下载插件输出、搬运文件、创建 scan_archive，并将结果写回到 download_url 任务
 */
public class DownloadUrlCallbackRunner {
    private static func writeErrorOutput(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.writeError(taskId, message)
    }

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("download_url_callback")
        TaskIO.appendLog(taskId, "download_url_callback task started")
        TaskModel.updateTaskProgress(taskId, 10, "开始处理下载回调")

        let (downloadTaskId, denoTaskId, categoryId, pluginNamespace) = parseParameters(parameters)
        if (downloadTaskId <= 0 || denoTaskId <= 0 || categoryId <= 0 || pluginNamespace.size == 0) {
            fail(taskId, "Invalid callback parameters")
            return
        }

        TaskIO.appendLog(
            taskId,
            "callback params: downloadTaskId=${downloadTaskId}, denoTaskId=${denoTaskId}, categoryId=${categoryId}, pluginNamespace=${pluginNamespace}"
        )

        // 读取 deno_task 状态/输出（失败时依旧会写 output JSON，但 status=failed）
        let denoTask = TaskDao.getTaskDataById(denoTaskId)
        let pluginOutput = TaskIO.readOutput(denoTaskId)

        if (denoTask.status != "completed") {
            let errMsg =
                if (denoTask.message.trimAscii().size > 0) { denoTask.message } else { "Deno task failed" }
            // 将失败写回父任务，避免前端卡在 waiting
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, "Dependency deno_task not completed: ${denoTask.status} - ${errMsg}")
            return
        }

        if (pluginOutput.trimAscii().size == 0) {
            let errMsg = "Deno task output is empty"
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }

        // 插件自行下载并回传 relative_path（相对于缓存目录）
        TaskModel.updateTaskProgress(taskId, 30, "解析插件输出")
        let downloadedRelativePaths = parseDownloadedRelativePath(pluginOutput)
        let downloadedSource = parseDownloadedSource(pluginOutput)

        if (downloadedRelativePaths.size == 0) {
            let pluginErr = parsePluginError(pluginOutput)
            let errMsg = if (pluginErr.size > 0) { pluginErr } else { "Plugin did not return relative_path" }
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }
        if (downloadedRelativePaths.size > 1) {
            let errMsg = "Multiple archives not yet supported in this version"
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }

        let downloadedRelativePath = downloadedRelativePaths.get(0).getOrThrow()
        if (downloadedRelativePath.contains("..") || downloadedRelativePath.startsWith("/") ||
            !downloadedRelativePath.startsWith("plugins/${pluginNamespace}/")) {
            let errMsg = "Plugin returned invalid relative_path"
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }

        // 获取分类信息
        let categoryOpt = CategoryDao.getCategoryByInternalId(categoryId)
        var categoryPath = ""
        match (categoryOpt) {
            case Some(cat) =>
                categoryPath = cat.scanPath
            case None =>
                let errMsg = "Category not found"
                TaskModel.failTask(downloadTaskId, errMsg)
                writeErrorOutput(downloadTaskId, errMsg)
                fail(taskId, errMsg)
                return
        }

        // 搬运文件到归档目录
        TaskModel.updateTaskProgress(taskId, 60, "搬运下载文件")
        let cachePath = context.paths.cachePath
        let pluginTarget = Path("${cachePath}/${downloadedRelativePath}")
        if (!exists(pluginTarget)) {
            let errMsg = "Plugin downloaded file not found"
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }
        let fileName = pluginTarget.fileName

        let archiveDir = Path(categoryPath)
        FileUtils.ensureDirectoryExists(archiveDir)

        let finalArchivePath = Path("${categoryPath}/${fileName}")
        let finalArchivePathStr = finalArchivePath.toString()

        try {
            // 移动文件到归档目录（支持跨设备：rename 失败时 fallback 到 copy+remove）
            try {
                rename(pluginTarget, to: finalArchivePath)
            } catch (e: Exception) {
                if (e.message.contains("cross-device") || e.message.contains("Invalid cross-device link")) {
                    copy(pluginTarget, to: finalArchivePath, overwrite: false)
                    // copy 成功后尽力删除源文件（避免缓存目录堆积）
                    try { remove(pluginTarget) } catch (_: Exception) {}
                } else {
                    throw e
                }
            }

            // 验证移动结果
            if (!exists(finalArchivePath)) {
                throw Exception("文件移动失败：目标文件不存在")
            }
        } catch (e: Exception) {
            let errMsg = "Failed to move file to archive: ${e.message}"
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }

        // 创建 scan_archive 任务
        TaskModel.updateTaskProgress(taskId, 80, "创建扫描任务")

        let cachePathStr = cachePath.toString()

        // 解析插件返回的 archive_type
        let archiveType = parseArchiveTypeFromPlugin(pluginOutput)

        // 构建包含source的tags
        var tags = ""
        if (downloadedSource.size > 0) {
            tags = "source:${downloadedSource}"
        }

        let scanOut = ByteBuffer()
        let scanW = JsonWriter(scanOut)
        scanW.startObject()
        scanW.writeName("archive_path").writeValue(finalArchivePathStr)
        scanW.writeName("category_id").writeValue(categoryId)
        scanW.writeName("cache_path").writeValue(cachePathStr)
        scanW.writeName("archive_type").writeValue(archiveType)
        scanW.writeName("tags").writeValue(tags)
        scanW.endObject()
        scanW.flush()
        let scanParams = String.fromUtf8(readToEnd(scanOut))
        let scanTask = TaskModel.createTaskWithOptions(
            "扫描档案",
            "scan_archive",
            scanParams,
            50,
            "download_url:${downloadTaskId}",
            "upload"
        )
        if (scanTask.id <= 0) {
            let errMsg = "Failed to create scan_archive task"
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }

        // 通知 TaskPool 有新任务可用（scan_archive）
        context.notifyTaskAvailable()

        // 将结果写回父任务（download_url）
        let resultOut = ByteBuffer()
        let resultW = JsonWriter(resultOut)
        resultW.startObject()
        resultW.writeName("success").writeValue(1)
        resultW.writeName("archives")
        resultW.startArray()
        resultW.startObject()
        resultW.writeName("filename").writeValue(fileName)
        resultW.endObject()
        resultW.endArray()
        resultW.writeName("task_id").writeValue(scanTask.id.toString())
        resultW.endObject()
        resultW.flush()
        let resultJson = String.fromUtf8(readToEnd(resultOut))
        TaskModel.updateTaskProgress(downloadTaskId, 100, "下载完成")
        TaskModel.completeTask(downloadTaskId, "download_url completed")
        TaskIO.writeOutput(downloadTaskId, resultJson)
        TaskIO.appendLog(downloadTaskId, "download_url task completed: scan_task_id=${scanTask.id}")

        // 完成回调任务自身
        TaskModel.updateTaskProgress(taskId, 100, "下载回调完成")
        TaskModel.completeTask(taskId, "download_url_callback completed")
        let cbOut = ByteBuffer()
        let cbW = JsonWriter(cbOut)
        cbW.startObject()
        cbW.writeName("success").writeValue(1)
        cbW.writeName("download_task_id").writeValue(downloadTaskId)
        cbW.writeName("scan_task_id").writeValue(scanTask.id)
        cbW.endObject()
        cbW.flush()
        TaskIO.writeOutput(taskId, String.fromUtf8(readToEnd(cbOut)))

        logger.debug("download_url_callback completed", ("download_task_id", downloadTaskId.toString()), ("scan_task_id", scanTask.id.toString()))
    }

    private static func parseParameters(parameters: String): (Int64, Int64, Int64, String) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return (0, 0, 0, "")
        }

        var downloadTaskId: Int64 = 0
        var denoTaskId: Int64 = 0
        var categoryId: Int64 = 0
        var pluginNamespace = ""

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readInt64Flexible(): Int64 {
                let s = r.readValue<String>().trimAscii()
                try { return Int64.parse(s) } catch (_: Exception) { return 0 }
            }

            match (r.peek()) {
                case Some(BeginObject) =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let k = r.readName()
                        match (k) {
                            case "downloadTaskId" => downloadTaskId = readInt64Flexible()
                            case "denoTaskId" => denoTaskId = readInt64Flexible()
                            case "categoryId" => categoryId = readInt64Flexible()
                            case "pluginNamespace" => pluginNamespace = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                case _ => ()
            }
        } catch (_: Exception) {}

        return (downloadTaskId, denoTaskId, categoryId, pluginNamespace)
    }

    private static func parsePluginError(output: String): String {
        if (output.trimAscii().size == 0) {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            var successSeen = false
            var success = false
            var err = ""

            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" =>
                        successSeen = true
                        success = readBoolFlexible()
                    case "error" =>
                        err = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (successSeen && !success && err.size > 0) { return err }
        } catch (_: Exception) {}
        return ""
    }

    private static func parseDownloadedRelativePath(output: String): ArrayList<String> {
        var paths = ArrayList<String>()
        if (output.size == 0) {
            return paths
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            var ok = false
            if (r.peek() != Some(BeginObject)) { return paths }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" => ok = readBoolFlexible()
                    case "data" =>
                        if (!ok) { r.skip(); continue }
                        match (r.peek()) {
                            case Some(BeginArray) =>
                                r.startArray()
                                while (r.peek() != EndArray) {
                                    match (r.peek()) {
                                        case Some(BeginObject) =>
                                            var rp = ""
                                            r.startObject()
                                            while (r.peek() != EndObject) {
                                                let fn = r.readName()
                                                match (fn) {
                                                    case "relative_path" => rp = r.readValue<String>().trimAscii()
                                                    case _ => r.skip()
                                                }
                                            }
                                            r.endObject()
                                            if (rp.size > 0) { paths.add(rp) }
                                        case Some(_) => r.skip()
                                        case None => break
                                    }
                                }
                                r.endArray()
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return paths
    }

    private static func parseDownloadedSource(output: String): String {
        if (output.size == 0) {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            var ok = false
            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" => ok = readBoolFlexible()
                    case "data" =>
                        if (!ok) { r.skip(); continue }
                        match (r.peek()) {
                            case Some(BeginArray) =>
                                r.startArray()
                                // Only look at the first element (keeps behavior).
                                match (r.peek()) {
                                    case Some(BeginObject) =>
                                        var source = ""
                                        r.startObject()
                                        while (r.peek() != EndObject) {
                                            let fn = r.readName()
                                            match (fn) {
                                                case "source" => source = r.readValue<String>().trimAscii()
                                                case _ => r.skip()
                                            }
                                        }
                                        r.endObject()
                                        // Skip the rest of the array quickly.
                                        while (r.peek() != EndArray) { r.skip() }
                                        r.endArray()
                                        return source
                                    case Some(_) =>
                                        while (r.peek() != EndArray) { r.skip() }
                                        r.endArray()
                                    case None => ()
                                }
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return ""
    }

    private static func parseArchiveTypeFromPlugin(output: String): String {
        if (output.size == 0) {
            return "archive"
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            var ok = false
            if (r.peek() != Some(BeginObject)) { return "archive" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" => ok = readBoolFlexible()
                    case "data" =>
                        if (!ok) { r.skip(); continue }
                        match (r.peek()) {
                            case Some(BeginObject) =>
                                var t = ""
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let fn = r.readName()
                                    match (fn) {
                                        case "archive_type" => t = r.readValue<String>().trimAscii()
                                        case _ => r.skip()
                                    }
                                }
                                r.endObject()
                                if (t == "archive" || t == "folder" || t == "pdf") { return t }
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return "archive"
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

}
