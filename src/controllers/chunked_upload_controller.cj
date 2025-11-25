package lrr4cj.controllers

import stdx.net.http.HttpStatusCode
import cjoy.*
import cjoy.json.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import std.random.*
import lrr4cj.services.*
import std.time.*
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import std.fs.*
import std.convert.*
import lrr4cj.config.*
import stdx.log.*
import stdx.encoding.json.*
import stdx.encoding.json.stream.*

/**
 * 分片上传控制器
 * 处理分片上传相关的API请求
 */
public class ChunkedUploadController {

    // 分片上传配置
    private static let CHUNK_SIZE = 1536 * 1024; // 1.5MB (小于2MB限制)
    private static let MAX_FILE_SIZE = 500 * 1024 * 1024; // 500MB

    // 缓存目录
    private static let CACHE_DIR = "./data/cache"

    /**
     * 初始化上传会话
     * POST /api/archives/upload/init
     */
    public static func initUpload(ctx: JoyContext): Unit {
        try {
            // 直接读取请求体中的JSON字符串并存储到任务参数中
            let requestBody = ctx.readString()

            // 创建minion任务来跟踪上传过程
            let task = MinionModel.createTask("文件上传", "upload")

            // 创建临时目录，使用taskId作为目录名
            createTempDirectories()
            let uploadDir = Path("${CACHE_DIR}/task/${task.id}")
            Directory.create(uploadDir, recursive: true)

            // 存储原始JSON到任务参数中
            if (requestBody.size > 0) {
                // 直接将原始JSON存储到任务参数中
                MinionTaskDao.updateTaskParameters(task.id, requestBody)
                getLogger("chunked_upload").info("存储原始JSON到任务参数", ("taskId", task.id.toString()), ("jsonSize", requestBody.size.toString()))
            } else {
                getLogger("chunked_upload").warn("请求体为空，无法存储JSON参数")
            }

            MinionModel.updateTaskProgress(task.id, 10, "上传初始化完成，等待分片上传")

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
            let fileName = ctx.getQuery("filename") ?? ""

            // 验证参数
            if (taskIdStr.size == 0 || chunkIndexStr.size == 0 || totalChunksStr.size == 0) {
                let errorResponse = "{\"success\":0,\"error\":\"Missing required parameters: taskId, chunkIndex, totalChunks\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            let chunkIndex = Int64.parse(chunkIndexStr)
            let totalChunks = Int64.parse(totalChunksStr)

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
            let task = MinionModel.getTaskById(taskId)
            if (task.status == "completed" || task.status == "failed") {
                let errorResponse = "{\"success\":0,\"error\":\"Task already completed or failed\"}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
                return
            }

            getLogger("chunked_upload").info("Retrieved task from database", ("taskName", task.name), ("taskStatus", task.status), ("taskParameters", task.parameters))

            // 从任务参数中使用JsonStream解析JSON获取原始文件名
            var originalFileName = "archive_${taskIdStr}.zip"  // 默认文件名
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
                                        case _ =>
                                            // 对于其他字段，读取值但不使用
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
                MinionModel.updateTaskProgress(taskId, 70, "分片合并完成，开始处理文件")
            } catch (e: Exception) {
                // 标记任务失败
                getLogger("chunked_upload").error("Failed to merge chunks", ("error", e.message))
                MinionModel.failTask(taskId, "分片合并失败: ${e.message}")

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

            // 将文件移动到归档目录，使用原始文件名
            let archivePath = "./data/archive"
            let archiveDir = Path(archivePath)
            if (!exists(archiveDir)) {
                Directory.create(archiveDir, recursive: true)
            }

            let finalArchivePath = Path("${archivePath}/${originalFileName}")

            // 移动文件到归档目录
            try {
                getLogger("chunked_upload").info("Moving file", ("from", finalFile.toString()), ("to", finalArchivePath.toString()))
                rename(finalFile, to: finalArchivePath)
                getLogger("chunked_upload").info("File move operation completed successfully")
            } catch (e: Exception) {
                getLogger("chunked_upload").error("Failed to move file to archive directory", ("from", finalFile.toString()), ("to", finalArchivePath.toString()), ("error", e.message))
                let errorResponse = "{\"success\":0,\"error\":\"Failed to move file to archive directory: ${e.message}\"}"
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

            // 调用Shinobu服务处理归档文件（入库和缩略图生成）
            let shinobuService = ShinobuService.getInstance()
            let processResult = shinobuService.processUploadedArchiveFile(absoluteArchivePath)

            if (processResult.success) {
                getLogger("chunked_upload").info("File processing completed successfully", ("archiveId", processResult.archiveId))

                // 更新任务状态为完成
                let taskResult = "文件上传处理完成\n归档ID: ${processResult.archiveId}\n文件名: ${originalFileName}\n相对路径: ${finalArchivePath.toString()}"
                MinionModel.completeTask(taskId, taskResult)

                // 清理上传目录
                cleanupUploadDir(chunkDir)

                let response = "{\"success\":1,\"id\":\"${processResult.archiveId}\"}"
                ctx.json(response)
            } else {
                // 处理失败，标记任务失败
                getLogger("chunked_upload").error("File processing failed", ("error", processResult.error))
                MinionModel.failTask(taskId, "文件处理失败: ${processResult.error}")

                // 如果处理失败，删除已移动的文件
                try {
                    remove(finalArchivePath)
                } catch (_) {
                    // 忽略删除错误
                }
                let errorResponse = "{\"success\":0,\"error\":\"${processResult.error}\"}"
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json(errorResponse)
            }
        } catch (e: Exception) {
            let errorResponse = "{\"success\":0,\"error\":\"${e.message}\"}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json(errorResponse)
        }
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
     * 解析任务参数
     */
    private static func parseTaskParameter(parameters: String, key: String): String {
        try {
            if (parameters.size == 0) {
                return ""
            }

            // 简单的JSON解析，查找key对应的值
            let keyPattern = "\"${key}\":\""

            // 手动查找key位置
            var i = 0
            var keyIndex = -1
            while (i <= parameters.size - keyPattern.size) {
                var found = true
                for (j in 0..keyPattern.size) {
                    if (i + j >= parameters.size || parameters[i + j] != keyPattern[j]) {
                        found = false
                        break
                    }
                }
                if (found) {
                    keyIndex = i
                    break
                }
                i++
            }

            if (keyIndex < 0) {
                return ""
            }

            let valueStart = keyIndex + keyPattern.size

            // 查找结束引号
            var valueEnd = valueStart
            let quoteCharValue = 34u8 // ASCII value for quote character as UInt8
            while (valueEnd < parameters.size && parameters[valueEnd] != quoteCharValue) {
                valueEnd++
            }

            if (valueEnd >= parameters.size) {
                return ""
            }

            var result = ""
            for (j in valueStart..valueEnd) {
                result += parameters[j].toString()
            }
            return result
        } catch (e: Exception) {
            getLogger("chunked_upload").warn("Failed to parse task parameter", ("key", key), ("parameters", parameters), ("error", e.message))
            return ""
        }
    }

    /**
     * 生成上传ID
     */
    private static func generateUploadId(): String {
        let content = DateTime.now().toString() + Random(3).nextBits(32).toString()

        // 使用 SHA1 算法生成哈希
        var sha1Instance = SHA1()
        sha1Instance.write(content.toArray())
        let hash: Array<Byte> = sha1Instance.finish()

        // 转换为十六进制字符串
        let result = toHexString(hash)
        return "upload_session_${toHexString(hash)}"
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
     * 处理合并后的文件
     */
    private static func processMergedFile(
        filePath: String,
        title: String,
        tags: String,
        summary: String,
        categoryId: String,
        fileChecksum: String
    ): String {
        try {
            // 获取ShinobuService实例
            let shinobu = ShinobuService.getInstance()
            let archivePath = ShinobuService.getArchivePath().toString()

            // 构建目标文件路径
            let fileName = Path(filePath).fileName
            let targetPath = FileUtils.joinPath(archivePath, fileName)

            // 移动文件到归档目录
            let sourceFile = Path(filePath)
            if (exists(sourceFile)) {
                // 简化处理：直接复制文件
                copy(sourceFile.toString(), to: targetPath, overwrite: true)
            }

            // 生成归档ID
            let archiveId = "archive_${generateUploadId()}"

            // 这里应该保存到数据库
            // 简化处理，直接返回ID

            return archiveId
        } catch (e: Exception) {
            println("Error processing merged file: ${e.message}")
            return ""
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
            let buffer = Array<Byte>(bufferSize, {i => 0})

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
