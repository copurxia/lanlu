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
import std.io.*
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

            // 写入 upload meta，供 uploadChunk/completeUpload 使用，避免每个分片都查 DB
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
            let totalChunksFromQuery = Int64.parse(totalChunksStr)

            // 创建上传目录，使用taskId作为目录名
            let uploadDir = Path("${CACHE_DIR}/task/${taskIdStr}")
            if (!exists(uploadDir)) {
                let errorResponse = "{\"success\":0,\"error\":\"Upload directory not found for taskId ${taskIdStr}\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // 读取 upload meta
            let metaPath = Path("${uploadDir.toString()}/${UPLOAD_META_FILE}")
            if (!exists(metaPath)) {
                let errorResponse = "{\"success\":0,\"error\":\"Upload meta not found for taskId ${taskIdStr}\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            var fileSize: Int64 = 0
            var chunkSize: Int64 = 0
            var totalChunks: Int64 = 0
            try {
                let metaFile = File(metaPath, Read)
                let metaSize = metaFile.info.size
                let buffer = Array<Byte>(metaSize, {_ => 0})
                let bytesRead = metaFile.read(buffer)
                metaFile.close()
                let metaStr = if (bytesRead > 0) { String.fromUtf8(buffer.slice(0, bytesRead)) } else { "" }

                var bas = ByteBuffer()
                unsafe { bas.write(metaStr.rawData()) }
                var reader = JsonReader(bas)
                while (let Some(v) <- reader.peek()) {
                    match (v) {
                        case BeginObject =>
                            reader.startObject()
                            while (reader.peek() != EndObject) {
                                let name = reader.readName()
                                match (name) {
                                    case "filesize" =>
                                        try { fileSize = reader.readValue<Int64>() } catch (_: Exception) {
                                            try { fileSize = Int64.parse(reader.readValue<String>()) } catch (_: Exception) { let _ = reader.skip() }
                                        }
                                    case "chunk_size" =>
                                        try { chunkSize = reader.readValue<Int64>() } catch (_: Exception) {
                                            try { chunkSize = Int64.parse(reader.readValue<String>()) } catch (_: Exception) { let _ = reader.skip() }
                                        }
                                    case "total_chunks" =>
                                        try { totalChunks = reader.readValue<Int64>() } catch (_: Exception) {
                                            try { totalChunks = Int64.parse(reader.readValue<String>()) } catch (_: Exception) { let _ = reader.skip() }
                                        }
                                    case _ => let _ = reader.skip()
                                }
                            }
                            reader.endObject()
                            break
                        case _ => throw Exception("Invalid JSON format")
                    }
                }
            } catch (e: Exception) {
                let errorResponse = "{\"success\":0,\"error\":\"Failed to read upload meta: ${e.message}\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json(errorResponse)
                return
            }

            if (fileSize <= 0 || chunkSize <= 0 || totalChunks <= 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid upload meta: filesize/chunk_size/total_chunks\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }
            if (totalChunksFromQuery != totalChunks) {
                let errorResponse = "{\"success\":0,\"error\":\"totalChunks mismatch\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }
            if (chunkIndex < 0 || chunkIndex >= totalChunks) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid chunkIndex\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // 读取请求体
            let fileData = ctx.readRawData()

            if (fileData.size <= 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Empty body\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // 校验 chunk 长度与范围（最后一块可以小于 chunkSize）
            let expectedOffset = chunkIndex * chunkSize
            if (expectedOffset < 0 || expectedOffset >= fileSize) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid chunk offset\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }
            if (expectedOffset + fileData.size > fileSize) {
                let errorResponse = "{\"success\":0,\"error\":\"Chunk exceeds file size\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }
            if (chunkIndex != totalChunks - 1 && fileData.size != chunkSize) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid chunk size\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // 写入临时大文件：按 chunkIndex * chunkSize 定位写入
            let partPath = Path("${uploadDir.toString()}/${UPLOAD_PART_FILE}")
            if (!exists(partPath)) {
                let errorResponse = "{\"success\":0,\"error\":\"Upload part file not found\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // NOTE: 这里必须使用“不会 truncate”的打开方式 + 定位写入，否则并发会破坏文件。
            // 具体 seek/open mode 由 std.fs.File/OpenMode 提供。
            try {
                let partFile = File(partPath, OpenMode.ReadWrite)
                partFile.seek(SeekPosition.Begin(expectedOffset))
                partFile.write(fileData)
                partFile.flush()
                partFile.close()
            } catch (e: Exception) {
                let errorResponse = "{\"success\":0,\"error\":\"Failed to write chunk: ${e.message}\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json(errorResponse)
                return
            }

            // 写一个轻量级 marker 文件，complete 时用来校验缺块（避免扫描 chunk_*.bin）
            try {
                let donePath = Path("${uploadDir.toString()}/chunk_${chunkIndexStr}.done")
                let doneFile = File(donePath, Write)
                doneFile.flush()
                doneFile.close()
            } catch (e: Exception) {
                // marker 创建失败不影响数据写入，但会导致 complete 校验失败；记录日志
                getLogger("chunked_upload").warn("Failed to write chunk marker", ("taskId", taskIdStr), ("chunkIndex", chunkIndexStr), ("error", e.message))
            }

            getLogger("chunked_upload").info(
                "Chunk written successfully",
                ("taskId", taskIdStr),
                ("chunkIndex", chunkIndexStr),
                ("size", fileData.size.toString())
            )

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

            let chunkDir = Path("${CACHE_DIR}/task/${taskIdStr}")
            let finalFile = Path("${chunkDir.toString()}/${UPLOAD_PART_FILE}")

            if (!exists(chunkDir)) {
                let errorResponse = "{\"success\":0,\"error\":\"Upload directory not found for taskId ${taskIdStr}\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            // 校验分片是否齐全：读取 meta 的 total_chunks，然后检查 chunk_i.done
            let metaPath = Path("${chunkDir.toString()}/${UPLOAD_META_FILE}")
            if (!exists(metaPath)) {
                let errorResponse = "{\"success\":0,\"error\":\"Upload meta not found for taskId ${taskIdStr}\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            var totalChunks: Int64 = 0
            var fileSize: Int64 = 0
            try {
                let metaFile = File(metaPath, Read)
                let metaSize = metaFile.info.size
                let buffer = Array<Byte>(metaSize, {_ => 0})
                let bytesRead = metaFile.read(buffer)
                metaFile.close()
                let metaStr = if (bytesRead > 0) { String.fromUtf8(buffer.slice(0, bytesRead)) } else { "" }

                var bas = ByteBuffer()
                unsafe { bas.write(metaStr.rawData()) }
                var reader = JsonReader(bas)
                while (let Some(v) <- reader.peek()) {
                    match (v) {
                        case BeginObject =>
                            reader.startObject()
                            while (reader.peek() != EndObject) {
                                let name = reader.readName()
                                match (name) {
                                    case "total_chunks" =>
                                        try { totalChunks = reader.readValue<Int64>() } catch (_: Exception) {
                                            try { totalChunks = Int64.parse(reader.readValue<String>()) } catch (_: Exception) { let _ = reader.skip() }
                                        }
                                    case "filesize" =>
                                        try { fileSize = reader.readValue<Int64>() } catch (_: Exception) {
                                            try { fileSize = Int64.parse(reader.readValue<String>()) } catch (_: Exception) { let _ = reader.skip() }
                                        }
                                    case _ => let _ = reader.skip()
                                }
                            }
                            reader.endObject()
                            break
                        case _ => throw Exception("Invalid JSON format")
                    }
                }
            } catch (e: Exception) {
                let errorResponse = "{\"success\":0,\"error\":\"Failed to read upload meta: ${e.message}\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json(errorResponse)
                return
            }

            if (totalChunks <= 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Invalid total_chunks\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            for (i in 0..totalChunks) {
                let donePath = Path("${chunkDir.toString()}/chunk_${Int64(i).toString()}.done")
                if (!exists(donePath)) {
                    let errorResponse = "{\"success\":0,\"error\":\"missing chunk ${Int64(i).toString()}\"}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }
            }

            // 更新任务进度（不再进行 merge，直接进入文件处理阶段）
            TaskModel.updateTaskProgress(taskId, 70, "分片上传完成，开始处理文件")

            // 检查合并后的文件是否存在
            if (!exists(finalFile)) {
                let errorResponse = "{\"success\":0,\"error\":\"Uploaded file not found at ${chunkDir.toString()}/${UPLOAD_PART_FILE}\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }
            if (fileSize > 0) {
                let actualSize = FileInfo(finalFile).size
                if (actualSize != fileSize) {
                    let errorResponse = "{\"success\":0,\"error\":\"file size mismatch\"}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }
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

                try {
                    rename(finalFile, to: finalArchivePath)
                    getLogger("chunked_upload").info("File renamed successfully (same device)")
                } catch (e: Exception) {
                    // 检查是否是跨设备错误
                    if (e.message.contains("cross-device") || e.message.contains("Invalid cross-device link")) {
                        getLogger("chunked_upload").info("Cross-device detected, using copy+remove strategy")

                        // 跨设备：先复制再删除
                        copy(finalFile, to: finalArchivePath, overwrite: false)

                        // 复制成功后删除源文件
                        remove(finalFile)
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
                remove(chunkDir, recursive: true)
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



    
    // mergeChunks 已被“临时大文件 + 按 offset 写入”方案替代：
    // - uploadChunk 直接写入 final.part
    // - completeUpload 只做缺块校验与后续移动/入库
}
