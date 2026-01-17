package lrr4cj.controllers

import stdx.net.http.HttpStatusCode
import cjoy.*
import cjoy.json.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import lrr4cj.services.*
import std.fs.*
import std.convert.*
import stdx.log.*
import stdx.encoding.json.stream.*

/**
 * 分片上传控制器
 * 处理分片上传相关的API请求
 */
public class ChunkedUploadController {

    // 缓存目录
    private static let CACHE_DIR = "./data/cache"

    /**
     * 初始化上传会话
     * POST /api/archives/upload/init
     * 优化：使用 createTaskFull 将 3 次数据库操作合并为 1 次
     * 新增：检查目标文件是否已存在，支持 overwrite 参数
     */
    public static func initUpload(ctx: JoyContext): Unit {
        try {
            // 直接读取请求体中的JSON字符串
            let requestBody = ctx.readString()

            // 解析请求参数，检查文件是否已存在
            var filename = ""
            var categoryId = ""
            var overwrite = false

            if (requestBody.size > 0) {
                try {
                    var bas = ByteBuffer()
                    unsafe { bas.write(requestBody.rawData()) }
                    var reader = JsonReader(bas)

                    while (let Some(v) <- reader.peek()) {
                        match (v) {
                            case BeginObject =>
                                reader.startObject()
                                while (reader.peek() != EndObject) {
                                    let name = reader.readName()
                                    match (name) {
                                        case "filename" => filename = reader.readValue<String>()
                                        case "category_id" =>
                                            // 兼容 number/string
                                            try {
                                                categoryId = reader.readValue<String>()
                                            } catch (_: Exception) {
                                                try {
                                                    let id = reader.readValue<Int64>()
                                                    categoryId = id.toString()
                                                } catch (_: Exception) {
                                                    let _ = reader.skip()
                                                }
                                            }
                                        case "overwrite" =>
                                            // 支持布尔值或字符串
                                            let rawValue = reader.readValue<String>()
                                            overwrite = rawValue == "true" || rawValue == "1"
                                        case _ => let _ = reader.skip()
                                    }
                                }
                                reader.endObject()
                                break
                            case _ => throw Exception("Invalid JSON format")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("chunked_upload").warn("解析请求参数失败", ("error", e.message))
                }
            }

            // 如果有 category_id 和 filename，检查目标文件是否已存在
            if (categoryId.size > 0 && filename.size > 0 && !overwrite) {
                let internalId = try {
                    Int64.parse(categoryId)
                } catch (_: Exception) {
                    CategoryDao.getInternalId(categoryId)
                }
                let categoryOpt = CategoryDao.getCategoryByInternalId(internalId)
                match (categoryOpt) {
                    case Some(cat) =>
                        let targetPath = Path("${cat.scanPath}/${filename}")
                        if (exists(targetPath)) {
                            // 文件已存在，返回提示信息
                            let response = "{\"success\":0,\"fileExists\":true,\"error\":\"文件已存在: ${escapeJsonString(filename)}\"}"
                            ctx.json(response)
                            return
                        }
                    case None => ()
                }
            }

            // 使用 createTaskFull 一次性创建任务并设置所有字段
            // 原来需要 3 次数据库连接，现在只需要 1 次
            let task = TaskModel.createTaskFull(
                "文件上传",
                "upload",
                requestBody,
                10,
                "上传初始化完成，等待分片上传"
            )

            // 检查任务创建是否成功
            if (task.id == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"创建任务失败\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json(errorResponse)
                return
            }

            // 创建临时目录，使用taskId作为目录名
            createTempDirectories()
            let uploadDir = Path("${CACHE_DIR}/task/${task.id}")
            if (!exists(uploadDir)) {
                Directory.create(uploadDir, recursive: true)
                getLogger("chunked_upload").debug("创建上传目录", ("taskId", task.id.toString()))
            }

            let response = "{\"success\":1,\"taskId\":\"${task.id}\"}"
            ctx.json(response)
        } catch (e: Exception) {
            let errorResponse = "{\"success\":0,\"error\":\"${e.message}\"}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json(errorResponse)
        }
    }

    /**
     * 上传分片
     * PUT /api/archives/upload/chunk
     */
    public static func uploadChunk(ctx: JoyContext): Unit {
        try {
            // 获取查询参数
            let taskIdStr = ctx.getQuery("taskId") ?? ""
            let chunkIndexStr = ctx.getQuery("chunkIndex") ?? ""
            let totalChunksStr = ctx.getQuery("totalChunks") ?? ""

            // 验证参数
            if (taskIdStr.size == 0 || chunkIndexStr.size == 0 || totalChunksStr.size == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Missing required parameters: taskId, chunkIndex, totalChunks\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            let chunkIndex = Int64.parse(chunkIndexStr)

            // 创建上传目录，使用taskId作为目录名
            let uploadDir = Path("${CACHE_DIR}/task/${taskIdStr}")
            if (!exists(uploadDir)) {
                let errorResponse = "{\"success\":0,\"error\":\"Upload directory not found for taskId ${taskIdStr}\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // 保存分片文件
            let chunkFile = Path("${uploadDir}/chunk_${chunkIndex}.bin")
            let fileData = ctx.readRawData()

            try (file = File(chunkFile, Write)) {
                file.write(fileData)
                getLogger("chunked_upload").info("Chunk saved successfully", ("taskId", taskIdStr), ("chunkIndex", chunkIndexStr), ("size", fileData.size.toString()))
            }

            // 返回成功响应
            let response = "{\"success\":1,\"message\":\"Chunk uploaded successfully\"}"
            ctx.json(response)
        } catch (e: Exception) {
            let errorResponse = "{\"success\":0,\"error\":\"${e.message}\"}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json(errorResponse)
        }
    }

    /**
     * 完成上传
     * POST /api/archives/upload/complete
     */
    public static func completeUpload(ctx: JoyContext): Unit {
        try {
            getLogger("chunked_upload").info("=== UPLOAD COMPLETE START ===")

            // 只需要从查询参数获取taskId
            let taskIdStr = ctx.getQuery("taskId") ?? ""
            if (taskIdStr.size == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"taskId is required\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            let taskId = try {
                Int64.parse(taskIdStr)
            } catch (e: Exception) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid taskId format\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            getLogger("chunked_upload").info("Processing upload completion", ("taskId", taskIdStr))

            // 从数据库获取任务信息
            let task = TaskModel.getTaskById(taskId)
            if (task.status == "completed" || task.status == "failed") {
                let errorResponse = "{\"success\":0,\"error\":\"Task already completed or failed\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            getLogger("chunked_upload").info("Retrieved task from database", ("taskName", task.name), ("taskStatus", task.status), ("taskParameters", task.parameters))

            // 从任务参数中使用JsonStream解析JSON获取原始文件名、分类ID和overwrite标志
            var originalFileName = "archive_${taskIdStr}.zip"  // 默认文件名
            var categoryId: String = ""  // 使用 catid 字符串类型
            var overwrite = false  // 是否覆盖已存在的文件
            if (task.parameters.size > 0) {
                try {
                    // 使用JsonStream解析存储的JSON
                    let jsonStr = task.parameters
                    var bas = ByteBuffer()
                    unsafe { bas.write(jsonStr.rawData()) }
                    var reader = JsonReader(bas)

                    // 解析JSON对象
                    while (let Some(v) <- reader.peek()) {
                        match (v) {
                            case BeginObject =>
                                reader.startObject()
                                while (reader.peek() != EndObject) {
                                    let name = reader.readName()
                                    match (name) {
                                        case "filename" =>
                                            originalFileName = reader.readValue<String>()
                                            getLogger("chunked_upload").info("从JSON中解析到文件名", ("originalFileName", originalFileName))
                                        case "category_id" =>
                                            // 兼容 number/string
                                            try {
                                                categoryId = reader.readValue<String>()
                                            } catch (_: Exception) {
                                                try {
                                                    let id = reader.readValue<Int64>()
                                                    categoryId = id.toString()
                                                } catch (_: Exception) {
                                                    let _ = reader.skip()
                                                }
                                            }
                                            getLogger("chunked_upload").info("从JSON中解析到分类ID", ("categoryId", categoryId))
                                        case "overwrite" =>
                                            let rawValue = reader.readValue<String>()
                                            overwrite = rawValue == "true" || rawValue == "1"
                                            getLogger("chunked_upload").info("从JSON中解析到覆盖标志", ("overwrite", overwrite.toString()))
                                        case _ =>
                                            let _ = reader.skip()
                                    }
                                }
                                reader.endObject()
                                break
                            case _ =>
                                throw Exception("Invalid JSON format")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("chunked_upload").warn("JSON解析失败，使用默认文件名", ("error", e.message))
                }
            }

            getLogger("chunked_upload").info("Using taskId as directory", ("taskId", taskIdStr), ("originalFileName", originalFileName))

            // 合并分片，先存储为final.bin
            let chunkDir = Path("${CACHE_DIR}/task/${taskIdStr}")
            let finalFile = Path("${chunkDir}/final.bin")

            if (!exists(chunkDir)) {
                let errorResponse = "{\"success\":0,\"error\":\"Upload directory not found for taskId ${taskIdStr}\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // 执行分片合并
            try {
                mergeChunks(chunkDir.toString(), finalFile.toString())
                getLogger("chunked_upload").info("Chunk merging completed successfully")

                // 更新任务进度
                TaskModel.updateTaskProgress(taskId, 70, "分片合并完成，开始处理文件")
            } catch (e: Exception) {
                // 标记任务失败
                getLogger("chunked_upload").error("Failed to merge chunks", ("error", e.message))
                TaskModel.failTask(taskId, "分片合并失败: ${e.message}")

                let errorResponse = "{\"success\":0,\"error\":\"Failed to merge chunks: ${e.message}\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json(errorResponse)
                return
            }

            // 检查合并后的文件是否存在
            if (!exists(finalFile)) {
                let errorResponse = "{\"success\":0,\"error\":\"Merged file not found at ${chunkDir}/final.bin\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // 验证 category_id 必须存在
            if (categoryId.size == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"category_id is required\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // 从分类获取归档目录（统一使用内部数字ID）
            let categoryInternalId = try {
                Int64.parse(categoryId)
            } catch (_: Exception) {
                CategoryDao.getInternalId(categoryId)
            }
            let categoryOpt = CategoryDao.getCategoryByInternalId(categoryInternalId)
            var archivePath = ""
            match (categoryOpt) {
                case Some(cat) => archivePath = cat.scanPath
                case None =>
                    let errorResponse = "{\"success\":0,\"error\":\"Category not found\"}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
            }

            let archiveDir = Path(archivePath)
            if (!exists(archiveDir)) {
                Directory.create(archiveDir, recursive: true)
            }

            let finalArchivePath = Path("${archivePath}/${originalFileName}")

            // 如果目标文件已存在且 overwrite 为 true，先删除旧文件
            if (exists(finalArchivePath)) {
                if (overwrite) {
                    try {
                        getLogger("chunked_upload").info("覆盖模式：删除已存在的文件", ("path", finalArchivePath.toString()))
                        remove(finalArchivePath)
                    } catch (e: Exception) {
                        getLogger("chunked_upload").error("删除已存在文件失败", ("path", finalArchivePath.toString()), ("error", e.message))
                        let errorResponse = "{\"success\":0,\"error\":\"删除已存在文件失败: ${e.message}\"}"
                        ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                        ctx.json(errorResponse)
                        return
                    }
                } else {
                    // 文件已存在但未设置覆盖，返回错误
                    let errorResponse = "{\"success\":0,\"fileExists\":true,\"error\":\"文件已存在: ${escapeJsonString(originalFileName)}\"}"
                    ctx.json(errorResponse)
                    return
                }
            }

            // 移动文件到归档目录（支持跨设备）
            try {
                getLogger("chunked_upload").info("Moving file", ("from", finalFile.toString()), ("to", finalArchivePath.toString()))

                // 优先尝试直接重命名（同一设备时更快）
                var moveSuccess = false
                try {
                    rename(finalFile, to: finalArchivePath)
                    moveSuccess = true
                    getLogger("chunked_upload").info("File renamed successfully (same device)")
                } catch (e: Exception) {
                    // 检查是否是跨设备错误
                    if (e.message.contains("cross-device") || e.message.contains("Invalid cross-device link")) {
                        getLogger("chunked_upload").info("Cross-device detected, using copy+remove strategy")

                        // 跨设备：先复制再删除
                        copy(finalFile, to: finalArchivePath, overwrite: false)

                        // 复制成功后删除源文件
                        remove(finalFile)
                        moveSuccess = true
                        getLogger("chunked_upload").info("File moved successfully (跨设备)")
                    } else {
                        // 其他错误，重新抛出
                        throw e
                    }
                }

                // 验证移动结果
                if (!exists(finalArchivePath)) {
                    throw Exception("文件移动失败：目标文件不存在")
                }

            } catch (e: Exception) {
                getLogger("chunked_upload").error("Failed to move file", ("from", finalFile.toString()), ("to", finalArchivePath.toString()), ("error", e.message))

                // 清理可能已创建的残缺文件
                if (exists(finalArchivePath)) {
                    try {
                        remove(finalArchivePath)
                    } catch (_) { }
                }

                let errorResponse = "{\"success\":0,\"error\":\"Failed to move file: ${e.message}\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json(errorResponse)
                return
            }

            // // 清理临时目录
            try {
                getLogger("chunked_upload").info("开始清理临时目录", ("directory", chunkDir.toString()))
                remove(chunkDir)
                getLogger("chunked_upload").info("临时文件清理完成", ("directory", chunkDir.toString()))
            } catch (e: Exception) {
                getLogger("chunked_upload").warn("清理临时目录失败，但不影响主流程", ("directory", chunkDir.toString()), ("error", e.message))
                // 清理失败不影响主要流程，只记录警告
            }

            // 确保文件移动成功后再构建绝对路径供ShinobuService使用
            var absoluteArchivePath: String
            try {
                getLogger("chunked_upload").info("Attempting to canonicalize path", ("path", "${archivePath}/${originalFileName}"))
                absoluteArchivePath = canonicalize("${archivePath}/${originalFileName}").toString()
                getLogger("chunked_upload").info("Path canonicalized successfully", ("absolute_path", absoluteArchivePath))
            } catch (e: Exception) {
                // 如果canonicalize失败，使用相对路径
                getLogger("chunked_upload").warn("Failed to canonicalize archive path, using relative path", ("path", "${archivePath}/${originalFileName}"), ("error", e.message))
                absoluteArchivePath = "${archivePath}/${originalFileName}"
            }

            // async=1 时：交给 TaskPool 处理入库/缩略图；否则保持原行为（同步处理）
            let asyncFlag = ctx.getQuery("async") ?? ""
            if (asyncFlag == "1" || asyncFlag == "true") {
                // 更新任务类型并置为pending，等待TaskPool领取
                let paramsJson =
                    "{" +
                    "\"archive_path\":\"${escapeJsonString(absoluteArchivePath)}\"," +
                    "\"relative_path\":\"${escapeJsonString(finalArchivePath.toString())}\"," +
                    "\"filename\":\"${escapeJsonString(originalFileName)}\"," +
                    "\"category_id\":${categoryInternalId}" +
                    "}"
                TaskDao.updateTaskParameters(taskId, paramsJson)
                TaskDao.updateTaskType(taskId, "upload_process")
                TaskDao.updateTaskStatus(taskId, "pending", "等待处理", 70)
                TaskIO.appendLog(taskId, "enqueued upload_process archive_path=${absoluteArchivePath}")
                TaskPoolService.getInstance().notifyTaskAvailable()

                // 立刻返回job，前端通过 /api/taskpool/{id} 查询进度与最终输出
                let response = "{\"success\":1,\"job\":${taskId},\"operation\":\"upload\",\"filename\":\"${escapeJsonString(originalFileName)}\"}"
                ctx.json(response)
                return
            }

            // 异步模式：创建 scan_archive 任务处理归档文件
            let cachePath = SystemSettingsService.getPath("CACHE_PATH")
            let thumbnailPath = SystemSettingsService.getPath("THUMBNAIL_PATH")

            let params = "{\"archive_path\":\"${escapeJsonString(absoluteArchivePath)}\",\"category_id\":${categoryInternalId},\"cache_path\":\"${escapeJsonString(cachePath)}\",\"thumbnail_path\":\"${escapeJsonString(thumbnailPath)}\"}"
            let scanTask = TaskModel.createTaskWithOptions("扫描档案", "scan_archive", params, 50, "chunked_upload:${taskId}", "upload")
            if (scanTask.id > 0) {
                TaskPoolService.getInstance().notifyTaskAvailable()
                getLogger("chunked_upload").info("File processing task created", ("taskId", scanTask.id.toString()), ("taskType", "scan_archive"))

                // 更新任务状态为完成
                let taskResult = "文件上传处理完成\n任务ID: ${scanTask.id}\n文件名: ${originalFileName}\n相对路径: ${finalArchivePath.toString()}"
                TaskModel.completeTask(taskId, taskResult)

                // 清理上传目录
                cleanupUploadDir(chunkDir)

                let response = "{\"success\":1,\"taskId\":${scanTask.id}}"
                ctx.json(response)
            } else {
                // 处理失败，标记任务失败
                getLogger("chunked_upload").error("Failed to create file processing task")
                TaskModel.failTask(taskId, "文件处理任务创建失败")

                // 如果处理失败，删除已移动的文件
                try {
                    remove(finalArchivePath)
                } catch (_) {
                    // 忽略删除错误
                }
                let errorResponse = "{\"success\":0,\"error\":\"Failed to create processing task\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json(errorResponse)
            }
        } catch (e: Exception) {
            let errorResponse = "{\"success\":0,\"error\":\"${e.message}\"}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json(errorResponse)
        }
    }

    private static func escapeJsonString(input: String): String {
        var escaped = input
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }

    /**
     * 取消上传
     * DELETE /api/archives/upload/:taskId
     */
    public static func cancelUpload(ctx: JoyContext): Unit {
        try {
            let taskIdStr = ctx.getParam("taskId") ?? ""

            if (taskIdStr.size == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Task ID is required\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            getLogger("chunked_upload").info("Cancelling upload for taskId", ("taskId", taskIdStr))

            // 清理上传会话
            let uploadDir = Path("${CACHE_DIR}/task/${taskIdStr}")
            if (exists(uploadDir)) {
                cleanupUploadDir(uploadDir)
            }

            let response = "{\"success\":1}"
            ctx.json(response)
        } catch (e: Exception) {
            let errorResponse = "{\"success\":0,\"error\":\"${e.message}\"}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json(errorResponse)
        }
    }





    /**
     * 创建临时目录
     */
    private static func createTempDirectories(): Unit {
        if (!exists(Path(CACHE_DIR))) {
            Directory.create(Path(CACHE_DIR), recursive: true)
        }
        // 创建task子目录
        let taskDir = Path("${CACHE_DIR}/task")
        if (!exists(taskDir)) {
            Directory.create(taskDir, recursive: true)
        }
    }

    /**
     * 清理上传目录
     */
    private static func cleanupUploadDir(uploadDir: Path): Unit {
        try {
            if (exists(uploadDir)) {
                try {
                    remove(uploadDir, recursive: true)
                } catch (e: Exception) {
                    println("Error removing upload directory: ${e.message}")
                }
            }
        } catch (e: Exception) {
            println("Error cleaning up upload directory: ${e.message}")
        }
    }



    
    /**
     * 合并分片文件
     */
    private static func mergeChunks(chunkDir: String, outputFile: String): Unit {
        // 获取所有分片文件并按序号排序
        let chunkFiles = ArrayList<Path>()
        let dir = Path(chunkDir)

        // 检查目录是否存在
        if (!exists(dir)) {
            throw Exception("Chunk directory does not exist: ${chunkDir}")
        }

        // 遍历目录中的所有文件
        for (entry in Directory.readFrom(dir)) {
            if (!entry.isDirectory()) {
                let fileName = entry.path.fileName.toString()
                // 检查文件名是否匹配分片模式 (chunk_0.bin, chunk_1.bin, etc.)
                if (fileName.startsWith("chunk_") && fileName.endsWith(".bin")) {
                    chunkFiles.add(entry.path)
                }
            }
        }

        // 检查是否找到了分片文件
        if (chunkFiles.size == 0) {
            throw Exception("No chunk files found in directory: ${chunkDir}")
        }

        println("Found ${chunkFiles.size} chunk files to merge")

        // 简单排序：转换为数组进行排序
        let chunkArray = Array<Path>(chunkFiles.size, {i => chunkFiles[i]})

        // 冒泡排序按分片序号排序
        for (i in 0..chunkArray.size - 1) {
            for (j in 0..chunkArray.size - i - 1) {
                let aName = chunkArray[j].fileName.toString()
                let bName = chunkArray[j + 1].fileName.toString()

                try {
                    let aIndex = Int64.parse(aName.removePrefix("chunk_").removeSuffix(".bin"))
                    let bIndex = Int64.parse(bName.removePrefix("chunk_").removeSuffix(".bin"))
                    if (aIndex > bIndex) {
                        // 交换
                        let temp = chunkArray[j]
                        chunkArray[j] = chunkArray[j + 1]
                        chunkArray[j + 1] = temp
                    }
                } catch (e: Exception) {
                    println("Failed to parse chunk index from filename: ${aName} or ${bName}")
                    throw Exception("Invalid chunk filename format: ${e.message}")
                }
            }
        }

        // 创建输出文件
        try (outputFileStream = File(Path(outputFile), Write)) {
            // 使用固定大小的缓冲区
            let bufferSize = 1024 * 1024  // 1MB
            let buffer = Array<Byte>(bufferSize, {_ => 0})

            // 逐个读取分片并写入输出文件
            for (chunkFile in chunkArray) {
                getLogger("chunked_upload").info("Merging chunk", ("chunk", chunkFile.fileName.toString()))

                // 检查分片文件是否存在
                if (!exists(chunkFile)) {
                    throw Exception("Chunk file does not exist: ${chunkFile}")
                }

                try (chunkFileStream = File(chunkFile, Read)) {
                    var bytesRead = chunkFileStream.read(buffer)
                    while (bytesRead > 0) {
                        // 创建只包含实际读取字节的子数组
                        let writeBuffer = buffer[0..bytesRead]
                        outputFileStream.write(writeBuffer)
                        bytesRead = chunkFileStream.read(buffer)
                    }
                }
            }
        }

        println("Successfully merged ${chunkArray.size} chunks into ${outputFile}")

        // 不在这里清理分片目录，让调用方负责清理
    }
}
