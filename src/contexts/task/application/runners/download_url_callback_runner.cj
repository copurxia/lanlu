package lanlu.contexts.task.application.runners

import std.collection.*
import std.convert.*
import std.fs.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.log.*
import stdx.encoding.json.stream.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

/**
 * download_url_callback 回调任务执行器
 * 在下载插件任务（wasm_task）结束后触发：
 * 读取下载插件输出、搬运文件、创建 scan_archive，并将结果写回到 download_url 任务
 */
public class DownloadUrlCallbackRunner {
    private static func writeErrorOutput(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.writeError(taskId, message)
    }

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("download_url_callback")
        TaskIO.appendLog(taskId, "download_url_callback task started")
        TaskModel.updateTaskProgress(taskId, 10, "开始处理下载回调")

        let (downloadTaskId, pluginTaskId, categoryId, pluginNamespace) = parseParameters(parameters)
        if (downloadTaskId <= 0 || pluginTaskId <= 0 || categoryId <= 0 || pluginNamespace.size == 0) {
            fail(taskId, "Invalid callback parameters")
            return
        }

        TaskIO.appendLog(
            taskId,
            "callback params: downloadTaskId=${downloadTaskId}, pluginTaskId=${pluginTaskId}, categoryId=${categoryId}, pluginNamespace=${pluginNamespace}"
        )

        // 读取插件任务状态/输出（失败时依旧可能写 output JSON，但 status=failed）
        let pluginTask = TaskDao.getTaskDataById(pluginTaskId)
        let pluginOutput = TaskIO.readOutput(pluginTaskId)

        if (pluginTask.status != "completed") {
            let errMsg =
                if (pluginTask.message.trimAscii().size > 0) { pluginTask.message } else { "Plugin task failed" }
            // 将失败写回父任务，避免前端卡在 waiting
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, "Dependency plugin task not completed: ${pluginTask.status} - ${errMsg}")
            return
        }

        if (pluginOutput.trimAscii().size == 0) {
            let errMsg = "Plugin task output is empty"
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }

        // 解析插件下载结果：
        // - 优先使用 plugin_relative_path（相对于插件运行目录）
        // - 兼容旧字段 relative_path / filename
        // 最终由系统拼接到 plugins/<pluginNamespace>/ 下
        TaskModel.updateTaskProgress(taskId, 30, "解析插件输出")
        let downloadedPluginRelativePaths = parseDownloadedPluginRelativePath(pluginOutput)
        let downloadedSource = parseDownloadedSource(pluginOutput)

        if (downloadedPluginRelativePaths.size == 0) {
            let pluginErr = parsePluginError(pluginOutput)
            let errMsg = if (pluginErr.size > 0) { pluginErr } else { "Plugin did not return downloadable path" }
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }
        if (downloadedPluginRelativePaths.size > 1) {
            let errMsg = "Multiple archives not yet supported in this version"
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }

        let pluginRelativePath = downloadedPluginRelativePaths.get(0).getOrThrow()
        if (pluginRelativePath.size == 0) {
            let errMsg = "Plugin returned invalid relative_path"
            TaskModel.failTask(downloadTaskId, errMsg)
            writeErrorOutput(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }
        let downloadedRelativePath = "plugins/${pluginNamespace}/${pluginRelativePath}"

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
        TaskIO.writeOutput(downloadTaskId, resultJson)
        // Write JSON result before completion so SSE/detail readers can consistently parse task_id.
        TaskModel.completeTask(downloadTaskId, resultJson)
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
        var pluginTaskId: Int64 = 0
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
                            case "pluginTaskId" => pluginTaskId = readInt64Flexible()
                            case "categoryId" => categoryId = readInt64Flexible()
                            case "pluginNamespace" => pluginNamespace = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                case _ => ()
            }
        } catch (_: Exception) {}

        return (downloadTaskId, pluginTaskId, categoryId, pluginNamespace)
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

    private static func normalizePluginRelativePath(rawPath: String): String {
        var normalized = rawPath.trimAscii()
        if (normalized.size == 0) {
            return ""
        }
        if (normalized.startsWith("/") || normalized.startsWith("\\") || normalized.contains("\\")) {
            return ""
        }

        // 兼容旧协议：plugins/<any-namespace>/<path...>，系统统一剥离前缀并按当前 namespace 重新拼接。
        if (normalized.startsWith("plugins/")) {
            let parts = normalized.split("/")
            if (parts.size >= 3 && parts[0] == "plugins") {
                var rebuilt = ""
                var first = true
                for (i in 2..parts.size) {
                    if (!first) { rebuilt += "/" } else { first = false }
                    rebuilt += parts[i]
                }
                normalized = rebuilt
            }
        }

        let segs = normalized.split("/")
        if (segs.size == 0) {
            return ""
        }
        for (seg in segs) {
            if (seg.size == 0 || seg == "." || seg == "..") {
                return ""
            }
        }
        return normalized
    }

    private static func parseDownloadedPluginRelativePath(output: String): ArrayList<String> {
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
            var parsedPaths = ArrayList<String>()
            if (r.peek() != Some(BeginObject)) { return paths }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" => ok = readBoolFlexible()
                    case "data" =>
                        match (r.peek()) {
                            case Some(BeginArray) =>
                                r.startArray()
                                while (r.peek() != EndArray) {
                                    match (r.peek()) {
                                        case Some(BeginObject) =>
                                            var pluginRelativePath = ""
                                            var legacyRelativePath = ""
                                            var filename = ""
                                            r.startObject()
                                            while (r.peek() != EndObject) {
                                                let fn = r.readName()
                                                match (fn) {
                                                    case "plugin_relative_path" => pluginRelativePath = r.readValue<String>().trimAscii()
                                                    case "relative_path" => legacyRelativePath = r.readValue<String>().trimAscii()
                                                    case "filename" => filename = r.readValue<String>().trimAscii()
                                                    case _ => r.skip()
                                                }
                                            }
                                            r.endObject()
                                            var candidate = pluginRelativePath
                                            if (candidate.size == 0) { candidate = legacyRelativePath }
                                            if (candidate.size == 0) { candidate = filename }
                                            let normalized = normalizePluginRelativePath(candidate)
                                            if (normalized.size > 0) { parsedPaths.add(normalized) }
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
            if (ok) {
                paths = parsedPaths
            }
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
            var parsedSource = ""
            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" => ok = readBoolFlexible()
                    case "data" =>
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
                                        parsedSource = source
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
            if (ok) { return parsedSource }
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
            var parsedType = "archive"
            if (r.peek() != Some(BeginObject)) { return "archive" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" => ok = readBoolFlexible()
                    case "data" =>
                        match (r.peek()) {
                            case Some(BeginArray) =>
                                r.startArray()
                                while (r.peek() != EndArray) {
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
                                            if (t == "archive" || t == "folder" || t == "pdf") {
                                                parsedType = t
                                            }
                                        case Some(_) => r.skip()
                                        case None => break
                                    }
                                }
                                r.endArray()
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
                                if (t == "archive" || t == "folder" || t == "pdf") { parsedType = t }
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()
            if (ok) { return parsedType }
        } catch (_: Exception) {}
        return "archive"
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

}
