package lanlu.contexts.archive.interfaces.http

import stdx.net.http.HttpStatusCode
import ignite.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.task.infrastructure.persistence.TaskGroupKVDao
import lanlu.contexts.task.application.*
import lanlu.shared.views.*
import std.fs.*
import std.convert.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import std.collection.ArrayList
import stdx.log.*
import stdx.encoding.json.stream.*

/**
 * 分片上传控制器
 * 处理分片上传相关的API请求
 */
public class ChunkedUploadController {

    // 缓存目录
    private static let CACHE_DIR = "./data/cache"
    // upload 元信息文件名（放在 task 上传目录下）
    private static let UPLOAD_META_FILE = "upload_meta.json"
    // 临时大文件名（放在 task 上传目录下）
    private static let UPLOAD_PART_FILE = "final.part"
    private static let UPLOAD_IDLE_TIMEOUT_SECONDS: Int32 = 600
    // 上传状态 KV 存储 TTL（秒）
    private static let UPLOAD_KV_TTL_SECONDS: Int64 = 86400
    // 与前端分片大小对齐（10MB）
    private static let MAX_UPLOAD_CHUNK_SIZE: Int64 = 10 * 1024 * 1024

    /**
     * 初始化上传会话
     * POST /api/archives/upload/init
     * 优化：使用 createTaskFull 将 3 次数据库操作合并为 1 次
     * 新增：检查目标文件是否已存在，支持 overwrite 参数
     */
    public static func initUpload(ctx: Ctx): Unit {
        try {
            // 直接读取请求体中的JSON字符串
            let requestBody = ctx.bodyString()

            // 解析请求参数，检查文件是否已存在
            var filename = ""
            var categoryId = ""
            var overwrite = false
            // 分片上传元信息（用于写入临时大文件、校验分片）
            var fileSize: Int64 = 0
            var chunkSize: Int64 = 0
            var totalChunks: Int64 = 0

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
                                        case "filesize" =>
                                            // 兼容 number/string
                                            try {
                                                fileSize = reader.readValue<Int64>()
                                            } catch (_: Exception) {
                                                try {
                                                    fileSize = Int64.parse(reader.readValue<String>())
                                                } catch (_: Exception) {
                                                    let _ = reader.skip()
                                                }
                                            }
                                        case "chunk_size" =>
                                            // 兼容 number/string
                                            try {
                                                chunkSize = reader.readValue<Int64>()
                                            } catch (_: Exception) {
                                                try {
                                                    chunkSize = Int64.parse(reader.readValue<String>())
                                                } catch (_: Exception) {
                                                    let _ = reader.skip()
                                                }
                                            }
                                        case "total_chunks" =>
                                            // 兼容 number/string
                                            try {
                                                totalChunks = reader.readValue<Int64>()
                                            } catch (_: Exception) {
                                                try {
                                                    totalChunks = Int64.parse(reader.readValue<String>())
                                                } catch (_: Exception) {
                                                    let _ = reader.skip()
                                                }
                                            }
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

            if (chunkSize > MAX_UPLOAD_CHUNK_SIZE) {
                let errorResponse = "{\"success\":0,\"error\":\"chunk_size exceeds 10MB\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
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
                            let out = ByteBuffer()
                            let w = JsonWriter(out)
                            w.startObject()
                            w.writeName("success").writeValue(0)
                            w.writeName("fileExists").writeValue(true)
                            w.writeName("error").writeValue("文件已存在: ${filename}")
                            w.endObject()
                            w.flush()
                            ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
                            return
                        }
                    case None => ()
                }
            }

            // 使用 createTaskWithOptions 创建任务，状态为 pending，让 TaskPool 可以调度
            let task = TaskModel.createTaskWithOptions(
                "文件上传",
                "upload",
                requestBody,
                10,
                "",
                "manual"
            )

            // 检查任务创建是否成功
            if (task.id == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"创建任务失败\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // 保持 pending，让 TaskPool 实际领取后再切换到 running
            let _ = TaskDao.updateTaskStatus(task.id, "pending", "上传初始化完成，等待调度", 0)

            // 通知 TaskPool 有新任务可用，让调度机制介入
            TaskPoolService.getInstance().notifyTaskAvailable()

            // 创建临时目录，使用taskId作为目录名
            createTempDirectories()
            let uploadDir = Path("${CACHE_DIR}/task/${task.id}")
            if (!exists(uploadDir)) {
                Directory.create(uploadDir, recursive: true)
                let logger = getLogger("chunked_upload")
                logger.debug("创建上传目录", ("taskId", task.id.toString()))
            }

            // 写入 upload meta（旧前端兼容；当前分片上传改用 KV 读取）
            // 注意：chunkSize/totalChunks/fileSize 可能为 0（旧前端或异常请求），此时后续会报错
            try {
                let metaPath = Path("${uploadDir.toString()}/${UPLOAD_META_FILE}")
                let metaJson =
                    "{" +
                    "\"filesize\":${fileSize.toString()}," +
                    "\"chunk_size\":${chunkSize.toString()}," +
                    "\"total_chunks\":${totalChunks.toString()}" +
                    "}"
                let metaFile = File(metaPath, Write)
                unsafe { metaFile.write(metaJson.rawData()) }
                metaFile.flush()
                metaFile.close()

                // 确保临时大文件存在（分片写入时使用随机写入/定位写入）
                let partPath = Path("${uploadDir.toString()}/${UPLOAD_PART_FILE}")
                if (!exists(partPath)) {
                    let partFile = File(partPath, Write)
                    partFile.flush()
                    partFile.close()
                }
            } catch (e: Exception) {
                // meta/part 文件创建失败不应影响 task 创建，但会导致后续上传失败；记录日志便于排查
                getLogger("chunked_upload").warn("初始化上传文件失败", ("taskId", task.id.toString()), ("error", e.message))
            }

            // 初始化上传 KV（用于分片计数，避免扫描 marker 文件）
            let kvGroupId = "upload:${task.id}"
            TaskGroupKVDao.deleteGroup(kvGroupId)
            let _ = TaskGroupKVDao.upsert(kvGroupId, "filesize", fileSize.toString(), UPLOAD_KV_TTL_SECONDS)
            let _ = TaskGroupKVDao.upsert(kvGroupId, "chunk_size", chunkSize.toString(), UPLOAD_KV_TTL_SECONDS)
            let _ = TaskGroupKVDao.upsert(kvGroupId, "total_chunks", totalChunks.toString(), UPLOAD_KV_TTL_SECONDS)
            let _ = TaskGroupKVDao.upsert(kvGroupId, "uploaded_count", "0", UPLOAD_KV_TTL_SECONDS)

            let response = "{\"success\":1,\"taskId\":\"${task.id}\"}"
            ResponseView.json(ctx, response)
        } catch (e: Exception) {
            let errorResponse = "{\"success\":0,\"error\":\"${e.message}\"}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, errorResponse)
        }
    }

    /**
     * 上传分片
     * PUT /api/archives/upload/chunk
     */
    public static func uploadChunk(ctx: Ctx): Unit {
        try {
            // 获取查询参数
            let taskIdStr = ctx.query("taskId") ?? ""
            let chunkIndexStr = ctx.query("chunkIndex") ?? ""
            let totalChunksStr = ctx.query("totalChunks") ?? ""

            // 验证参数
            if (taskIdStr.size == 0 || chunkIndexStr.size == 0 || totalChunksStr.size == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Missing required parameters: taskId, chunkIndex, totalChunks\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }

            let chunkIndex = Int64.parse(chunkIndexStr)
            let totalChunksFromQuery = Int64.parse(totalChunksStr)
            let taskIdInt = try {
                Int64.parse(taskIdStr)
            } catch (_: Exception) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid taskId\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // 只有 TaskPool 已领取为 running 的上传任务才允许开始传分片
            let task = TaskDao.getTaskDataById(taskIdInt)
            if (task.id == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Task not found\"}"
                ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                ResponseView.json(ctx, errorResponse)
                return
            }
            if (task.status == "pending") {
                let errorResponse = "{\"success\":0,\"error\":\"任务正在排队，请等待调度\",\"status\":\"pending\"}"
                ctx.status(HttpStatusCode.STATUS_CONFLICT)
                ResponseView.json(ctx, errorResponse)
                return
            }
            if (task.status != "running") {
                let errorResponse = "{\"success\":0,\"error\":\"任务状态异常: ${task.status}\",\"status\":\"${task.status}\"}"
                ctx.status(HttpStatusCode.STATUS_CONFLICT)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // 创建上传目录，使用taskId作为目录名
            let uploadDir = Path("${CACHE_DIR}/task/${taskIdStr}")
            if (!exists(uploadDir)) {
                let errorResponse = "{\"success\":0,\"error\":\"Upload directory not found for taskId ${taskIdStr}\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // 读取 upload meta（KV）
            let kvGroupId = "upload:${taskIdStr}"
            var fileSize: Int64 = 0
            var chunkSize: Int64 = 0
            var totalChunks: Int64 = 0
            match (TaskGroupKVDao.get(kvGroupId, "filesize")) {
                case Some(v) => try { fileSize = Int64.parse(v) } catch (_: Exception) { fileSize = 0 }
                case None => fileSize = 0
            }
            match (TaskGroupKVDao.get(kvGroupId, "chunk_size")) {
                case Some(v) => try { chunkSize = Int64.parse(v) } catch (_: Exception) { chunkSize = 0 }
                case None => chunkSize = 0
            }
            match (TaskGroupKVDao.get(kvGroupId, "total_chunks")) {
                case Some(v) => try { totalChunks = Int64.parse(v) } catch (_: Exception) { totalChunks = 0 }
                case None => totalChunks = 0
            }

            if (fileSize <= 0 || chunkSize <= 0 || totalChunks <= 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid upload meta (kv): filesize/chunk_size/total_chunks\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }
            if (chunkSize > MAX_UPLOAD_CHUNK_SIZE) {
                let errorResponse = "{\"success\":0,\"error\":\"chunk_size exceeds 10MB\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }
            if (totalChunksFromQuery != totalChunks) {
                let errorResponse = "{\"success\":0,\"error\":\"totalChunks mismatch\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }
            if (chunkIndex < 0 || chunkIndex >= totalChunks) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid chunkIndex\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // 顺序写入：要求 chunkIndex 按已上传数量递增
            var uploadedCount: Int64 = 0
            match (TaskGroupKVDao.get(kvGroupId, "uploaded_count")) {
                case Some(v) =>
                    try { uploadedCount = Int64.parse(v) } catch (_: Exception) { uploadedCount = 0 }
                case None => uploadedCount = 0
            }
            if (chunkIndex < uploadedCount) {
                // 已上传，直接返回成功（避免重复写入）
                let _ = TaskDao.extendTaskTimeout(taskIdInt, UPLOAD_IDLE_TIMEOUT_SECONDS)
                let response = "{\"success\":1,\"message\":\"Chunk already uploaded\"}"
                ResponseView.json(ctx, response)
                return
            }
            if (chunkIndex > uploadedCount) {
                let errorResponse =
                    "{\"success\":0,\"error\":\"Out of order chunk: expected ${uploadedCount.toString()} got ${chunkIndex.toString()}\",\"expectedIndex\":${uploadedCount.toString()}}"
                ctx.status(HttpStatusCode.STATUS_CONFLICT)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // 读取请求体 - 二进制数据使用 requestBody()
            let bodyStream = ctx.requestBody()
            let fileDataList = ArrayList<UInt8>()
            let tmp = Array<UInt8>(8192, repeat: 0)
            while (true) {
                let n = bodyStream.read(tmp)
                if (n <= 0) {
                    break
                }
                for (i in 0..n) {
                    fileDataList.add(tmp[i])
                }
            }
            let fileData = fileDataList.toArray()

            if (fileData.size <= 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Empty body\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // 校验 chunk 长度与范围（最后一块可以小于 chunkSize）
            let expectedOffset = chunkIndex * chunkSize
            if (expectedOffset < 0 || expectedOffset >= fileSize) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid chunk offset\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }
            if (expectedOffset + fileData.size > fileSize) {
                let errorResponse = "{\"success\":0,\"error\":\"Chunk exceeds file size\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }
            if (chunkIndex != totalChunks - 1 && fileData.size != chunkSize) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid chunk size\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // 顺序写入临时大文件：按 chunkIndex 递增追加写入
            let partPath = Path("${uploadDir.toString()}/${UPLOAD_PART_FILE}")
            if (!exists(partPath)) {
                let errorResponse = "{\"success\":0,\"error\":\"Upload part file not found\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // 顺序写入：校验当前文件大小与期望偏移，防止写入错位
            try {
                let currentSize = Int64(FileInfo(partPath).size)
                if (currentSize != expectedOffset) {
                    let errorResponse =
                        "{\"success\":0,\"error\":\"Upload part size mismatch: expected ${expectedOffset.toString()} got ${currentSize.toString()}\"}"
                    ctx.status(HttpStatusCode.STATUS_CONFLICT)
                    ResponseView.json(ctx, errorResponse)
                    return
                }
            } catch (e: Exception) {
                let errorResponse = "{\"success\":0,\"error\":\"Failed to stat upload part: ${e.message}\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ResponseView.json(ctx, errorResponse)
                return
            }

            // NOTE: 顺序写入使用 append 模式，避免随机写带来的 IO 开销与并发冲突。
            try {
                let partFile = File(partPath, OpenMode.Append)
                partFile.write(fileData)
                if (chunkIndex == totalChunks - 1) {
                    partFile.flush()
                }
                partFile.close()
            } catch (e: Exception) {
                let errorResponse = "{\"success\":0,\"error\":\"Failed to write chunk: ${e.message}\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ResponseView.json(ctx, errorResponse)
                return
            }

            let logger = getLogger("chunked_upload")
            logger.debug(
                "Chunk written successfully",
                [("taskId", taskIdStr), ("chunkIndex", chunkIndexStr), ("size", fileData.size.toString())]
            )

            // 每次成功写入分片后，向后延长 upload task 的超时时间（10分钟）
            let timeoutUpdated = TaskDao.extendTaskTimeout(taskIdInt, UPLOAD_IDLE_TIMEOUT_SECONDS)
            if (!timeoutUpdated) {
                getLogger("chunked_upload").warn("Failed to extend upload timeout", ("taskId", taskIdStr))
            }

            // 记录分片完成状态（KV 计数，避免扫描 marker 文件）
            let chunkKey = "chunk_${chunkIndexStr}"
            var uploadedChunkCount: Int64 = 0
            let inserted = TaskGroupKVDao.insertIfAbsent(kvGroupId, chunkKey, "1", UPLOAD_KV_TTL_SECONDS)
            if (inserted) {
                uploadedChunkCount = TaskGroupKVDao.increment(kvGroupId, "uploaded_count", 1, UPLOAD_KV_TTL_SECONDS)
            }
            if (uploadedChunkCount <= 0) {
                match (TaskGroupKVDao.get(kvGroupId, "uploaded_count")) {
                    case Some(v) =>
                        try { uploadedChunkCount = Int64.parse(v) } catch (_: Exception) { uploadedChunkCount = 0 }
                    case None => uploadedChunkCount = 0
                }
            }

            // 计算并更新任务进度（基于已完成分片数量，避免并发分片导致进度回退）
            var uploadedProgress: Int64 = (uploadedChunkCount * 70) / totalChunks
            if (uploadedProgress < 0) { uploadedProgress = 0 }
            if (uploadedProgress > 70) { uploadedProgress = 70 }
            let progressMessage = "已上传 ${uploadedChunkCount.toString()}/${totalChunks.toString()} 个分片"
            TaskModel.updateTaskProgress(taskIdInt, Int32(uploadedProgress), progressMessage)

            if (uploadedChunkCount >= totalChunks && task.taskType == "upload") {
                let handoff = TaskGroupKVDao.insertIfAbsent(kvGroupId, "handoff", "1", UPLOAD_KV_TTL_SECONDS)
                if (!handoff) {
                    // 已经触发过交接，避免重复处理
                    let response = "{\"success\":1,\"message\":\"Chunk uploaded successfully\"}"
                    ResponseView.json(ctx, response)
                    return
                }
                var originalFileName = "archive_${taskIdStr}.zip"
                var categoryId = ""
                var overwrite = false
                if (task.parameters.size > 0) {
                    try {
                        var bas2 = ByteBuffer()
                        unsafe { bas2.write(task.parameters.rawData()) }
                        var reader2 = JsonReader(bas2)
                        while (let Some(v2) <- reader2.peek()) {
                            match (v2) {
                                case BeginObject =>
                                    reader2.startObject()
                                    while (reader2.peek() != EndObject) {
                                        let name = reader2.readName()
                                        match (name) {
                                            case "filename" =>
                                                originalFileName = reader2.readValue<String>()
                                            case "category_id" =>
                                                try {
                                                    categoryId = reader2.readValue<String>()
                                                } catch (_: Exception) {
                                                    try {
                                                        let id = reader2.readValue<Int64>()
                                                        categoryId = id.toString()
                                                    } catch (_: Exception) {
                                                        let _ = reader2.skip()
                                                    }
                                                }
                                            case "overwrite" =>
                                                let rawValue = reader2.readValue<String>()
                                                overwrite = rawValue == "true" || rawValue == "1"
                                            case _ => let _ = reader2.skip()
                                        }
                                    }
                                    reader2.endObject()
                                    break
                                case _ => throw Exception("Invalid JSON format")
                            }
                        }
                    } catch (e: Exception) {
                        getLogger("chunked_upload").warn("解析任务参数失败，使用默认文件名", ("error", e.message))
                    }
                }

                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("chunk_dir").writeValue(uploadDir.toString())
                w.writeName("final_part_path").writeValue(partPath.toString())
                w.writeName("file_size").writeValue(fileSize.toString())
                w.writeName("filename").writeValue(originalFileName)
                w.writeName("category_id").writeValue(categoryId)
                w.writeName("overwrite").writeValue(if (overwrite) { "true" } else { "false" })
                w.endObject()
                w.flush()
                let paramsJson = String.fromUtf8(readToEnd(out))
                TaskDao.updateTaskParameters(taskIdInt, paramsJson)
                TaskDao.updateTaskType(taskIdInt, "upload_process")
                TaskDao.updateTaskStatus(taskIdInt, "pending", "分片上传完成，等待处理", 70)
                TaskIO.appendLog(taskIdInt, "all chunks uploaded; handoff to upload_process")
                TaskPoolService.getInstance().notifyTaskAvailable()
            }

            // 返回成功响应
            let response = "{\"success\":1,\"message\":\"Chunk uploaded successfully\"}"
            ResponseView.json(ctx, response)
        } catch (e: Exception) {
            let errorResponse = "{\"success\":0,\"error\":\"${e.message}\"}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, errorResponse)
        }
    }

    /**
     * 取消上传
     * DELETE /api/archives/upload/:taskId
     */
    public static func cancelUpload(ctx: Ctx): Unit {
        try {
            let taskIdStr = ctx.paramsOpt("taskId") ?? ""

            if (taskIdStr.size == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Task ID is required\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }

            let taskId = try {
                Int64.parse(taskIdStr)
            } catch (_: Exception) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid taskId\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
            }

            getLogger("chunked_upload").info("Cancelling upload for taskId", ("taskId", taskIdStr))

            // 将 upload 任务置为 failed，释放 TaskPool worker 槽位
            let task = TaskDao.getTaskDataById(taskId)
            if (task.id > 0 && task.status != "completed" && task.status != "failed" && task.status != "stopped") {
                let _ = TaskDao.updateTaskStatus(taskId, "failed", "上传已取消", task.progress)
                TaskIO.appendLog(taskId, "upload canceled by client")
            }

            // 清理上传会话
            let uploadDir = Path("${CACHE_DIR}/task/${taskIdStr}")
            if (exists(uploadDir)) {
                cleanupUploadDir(uploadDir)
            }

            TaskGroupKVDao.deleteGroup("upload:${taskIdStr}")

            let response = "{\"success\":1}"
            ResponseView.json(ctx, response)
        } catch (e: Exception) {
            let errorResponse = "{\"success\":0,\"error\":\"${e.message}\"}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, errorResponse)
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



    
    // mergeChunks 已被“临时大文件 + 按 offset 写入”方案替代：
    // - uploadChunk 直接写入 final.part
}
