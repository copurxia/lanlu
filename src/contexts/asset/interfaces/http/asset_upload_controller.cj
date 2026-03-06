package lanlu.contexts.asset.interfaces.http

import ignite.*
import stdx.net.http.HttpStatusCode
import std.fs.*
import std.convert.*
import std.collection.ArrayList
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import stdx.log.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.task.infrastructure.persistence.TaskGroupKVDao
import lanlu.contexts.task.application.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.shared.utils.*
import lanlu.shared.views.*

private class InitPayload {
    public var filename: String = ""
    public var categoryId: String = ""
    public var targetType: String = "archive"
    public var targetId: String = ""
    public var overwrite: Bool = false
    public var fileSize: Int64 = 0
    public var chunkSize: Int64 = 0
    public var totalChunks: Int64 = 0
    public var contentType: String = ""
}

/**
 * 统一 Asset 分片上传控制器
 * 所有上传请求统一进入该控制器，由任务链处理业务消费。
 */
public class AssetUploadController {
    private static let CACHE_DIR = "./data/cache"
    private static let UPLOAD_PART_FILE = "final.part"
    private static let UPLOAD_IDLE_TIMEOUT_SECONDS: Int32 = 600
    private static let UPLOAD_KV_TTL_SECONDS: Int64 = 86400
    private static let MAX_UPLOAD_CHUNK_SIZE: Int64 = 10 * 1024 * 1024

    /**
     * POST /api/assets/upload/init
     */
    public static func initUpload(ctx: Ctx, userId: Int64): Unit {
        if (userId <= 0) {
            ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
            ResponseView.errorJson(ctx, "unauthorized", 401)
            return
        }

        try {
            let requestBody = ctx.bodyString()

            let payload = parseInitJson(requestBody)
            var filename = payload.filename
            var categoryId = payload.categoryId
            var targetType = payload.targetType
            var targetId = payload.targetId
            let overwrite = payload.overwrite
            let fileSize = payload.fileSize
            let chunkSize = payload.chunkSize
            let totalChunks = payload.totalChunks
            let contentType = payload.contentType

            targetType = normalizeTargetType(targetType)
            if (!isSupportedTargetType(targetType)) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "unsupported target_type", 400)
                return
            }

            if (chunkSize <= 0 || totalChunks <= 0 || fileSize <= 0) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "invalid upload meta", 400)
                return
            }
            if (chunkSize > MAX_UPLOAD_CHUNK_SIZE) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "chunk_size exceeds 10MB", 400)
                return
            }

            if (filename.trimAscii().size == 0) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "filename is required", 400)
                return
            }

            if (!validateInitTarget(ctx, userId, targetType, targetId, categoryId, filename, overwrite)) {
                return
            }

            let taskName = resolveTaskName(targetType)
            let taskParams = buildInitTaskParameters(
                filename,
                fileSize,
                chunkSize,
                totalChunks,
                categoryId,
                targetType,
                targetId,
                overwrite,
                userId,
                contentType
            )

            let task = TaskModel.createTaskWithOptions(
                taskName,
                "asset_upload",
                taskParams,
                10,
                "",
                "manual"
            )

            if (task.id == 0) {
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ResponseView.errorJson(ctx, "创建任务失败", 500)
                return
            }

            let _ = TaskDao.updateTaskStatus(task.id, "pending", "上传初始化完成，等待调度", 0)
            TaskPoolService.getInstance().notifyTaskAvailable()

            createTempDirectories()
            let uploadDir = Path("${CACHE_DIR}/task/${task.id}")
            if (!exists(uploadDir)) {
                Directory.create(uploadDir, recursive: true)
            }

            try {
                let partPath = Path("${uploadDir.toString()}/${UPLOAD_PART_FILE}")
                if (!exists(partPath)) {
                    let partFile = File(partPath, Write)
                    partFile.flush()
                    partFile.close()
                }
            } catch (e: Exception) {
                getLogger("asset_upload").warn("初始化上传文件失败", ("taskId", task.id.toString()), ("error", e.message))
            }

            let kvGroupId = "asset_upload:${task.id}"
            TaskGroupKVDao.deleteGroup(kvGroupId)
            let _ = TaskGroupKVDao.upsert(kvGroupId, "filesize", fileSize.toString(), UPLOAD_KV_TTL_SECONDS)
            let _ = TaskGroupKVDao.upsert(kvGroupId, "chunk_size", chunkSize.toString(), UPLOAD_KV_TTL_SECONDS)
            let _ = TaskGroupKVDao.upsert(kvGroupId, "total_chunks", totalChunks.toString(), UPLOAD_KV_TTL_SECONDS)
            let _ = TaskGroupKVDao.upsert(kvGroupId, "uploaded_count", "0", UPLOAD_KV_TTL_SECONDS)

            ResponseView.successJson(ctx, "{\"taskId\":\"${task.id}\"}", "ok")
        } catch (e: Exception) {
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.errorJson(ctx, e.message, 500)
        }
    }

    /**
     * PUT /api/assets/upload/chunk
     */
    public static func uploadChunk(ctx: Ctx): Unit {
        try {
            let taskIdStr = ctx.query("taskId") ?? ""
            let chunkIndexStr = ctx.query("chunkIndex") ?? ""
            let totalChunksStr = ctx.query("totalChunks") ?? ""

            if (taskIdStr.size == 0 || chunkIndexStr.size == 0 || totalChunksStr.size == 0) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Missing required parameters: taskId, chunkIndex, totalChunks", 400)
                return
            }

            let chunkIndex = Int64.parse(chunkIndexStr)
            let totalChunksFromQuery = Int64.parse(totalChunksStr)
            let taskIdInt = try {
                Int64.parse(taskIdStr)
            } catch (_: Exception) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Invalid taskId", 400)
                return
            }

            let task = TaskDao.getTaskDataById(taskIdInt)
            if (task.id == 0) {
                ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                ResponseView.errorJson(ctx, "Task not found", 404)
                return
            }
            if (task.status == "pending") {
                ctx.status(HttpStatusCode.STATUS_CONFLICT)
                ResponseView.errorJson(ctx, "任务正在排队，请等待调度", 409)
                return
            }
            if (task.status != "running") {
                ctx.status(HttpStatusCode.STATUS_CONFLICT)
                ResponseView.errorJson(ctx, "任务状态异常: ${task.status}", 409)
                return
            }

            let uploadDir = Path("${CACHE_DIR}/task/${taskIdStr}")
            if (!exists(uploadDir)) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Upload directory not found for taskId ${taskIdStr}", 400)
                return
            }

            let kvGroupId = "asset_upload:${taskIdStr}"
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
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Invalid upload meta (kv)", 400)
                return
            }
            if (chunkSize > MAX_UPLOAD_CHUNK_SIZE) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "chunk_size exceeds 10MB", 400)
                return
            }
            if (totalChunksFromQuery != totalChunks) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "totalChunks mismatch", 400)
                return
            }
            if (chunkIndex < 0 || chunkIndex >= totalChunks) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Invalid chunkIndex", 400)
                return
            }

            var uploadedCount: Int64 = 0
            match (TaskGroupKVDao.get(kvGroupId, "uploaded_count")) {
                case Some(v) =>
                    try { uploadedCount = Int64.parse(v) } catch (_: Exception) { uploadedCount = 0 }
                case None => uploadedCount = 0
            }
            if (chunkIndex < uploadedCount) {
                let _ = TaskDao.extendTaskTimeout(taskIdInt, UPLOAD_IDLE_TIMEOUT_SECONDS)
                ResponseView.successJson(ctx, "{}", "Chunk already uploaded")
                return
            }
            if (chunkIndex > uploadedCount) {
                ctx.status(HttpStatusCode.STATUS_CONFLICT)
                ResponseView.errorJson(
                    ctx,
                    "Out of order chunk: expected ${uploadedCount.toString()} got ${chunkIndex.toString()}",
                    409
                )
                return
            }

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
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }

            let expectedOffset = chunkIndex * chunkSize
            if (expectedOffset < 0 || expectedOffset >= fileSize) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Invalid chunk offset", 400)
                return
            }
            if (expectedOffset + fileData.size > fileSize) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Chunk exceeds file size", 400)
                return
            }
            if (chunkIndex != totalChunks - 1 && fileData.size != chunkSize) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Invalid chunk size", 400)
                return
            }

            let partPath = Path("${uploadDir.toString()}/${UPLOAD_PART_FILE}")
            if (!exists(partPath)) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Upload part file not found", 400)
                return
            }

            try {
                let currentSize = Int64(FileInfo(partPath).size)
                if (currentSize != expectedOffset) {
                    ctx.status(HttpStatusCode.STATUS_CONFLICT)
                    ResponseView.errorJson(
                        ctx,
                        "Upload part size mismatch: expected ${expectedOffset.toString()} got ${currentSize.toString()}",
                        409
                    )
                    return
                }
            } catch (e: Exception) {
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ResponseView.errorJson(ctx, "Failed to stat upload part: ${e.message}", 500)
                return
            }

            try {
                let partFile = File(partPath, OpenMode.Append)
                partFile.write(fileData)
                if (chunkIndex == totalChunks - 1) {
                    partFile.flush()
                }
                partFile.close()
            } catch (e: Exception) {
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ResponseView.errorJson(ctx, "Failed to write chunk: ${e.message}", 500)
                return
            }

            let timeoutUpdated = TaskDao.extendTaskTimeout(taskIdInt, UPLOAD_IDLE_TIMEOUT_SECONDS)
            if (!timeoutUpdated) {
                getLogger("asset_upload").warn("Failed to extend upload timeout", ("taskId", taskIdStr))
            }

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

            var uploadedProgress: Int64 = (uploadedChunkCount * 70) / totalChunks
            if (uploadedProgress < 0) { uploadedProgress = 0 }
            if (uploadedProgress > 70) { uploadedProgress = 70 }
            TaskModel.updateTaskProgress(taskIdInt, Int32(uploadedProgress), "已上传 ${uploadedChunkCount.toString()}/${totalChunks.toString()} 个分片")

            if (uploadedChunkCount >= totalChunks && task.taskType == "asset_upload") {
                let handoff = TaskGroupKVDao.insertIfAbsent(kvGroupId, "handoff", "1", UPLOAD_KV_TTL_SECONDS)
                if (!handoff) {
                    ResponseView.successJson(ctx, "{}", "Chunk uploaded successfully")
                    return
                }

                let filename = parseField(task.parameters, "filename")
                let categoryId = parseField(task.parameters, "category_id")
                let targetType = parseField(task.parameters, "target_type")
                let targetId = parseField(task.parameters, "target_id")
                let overwrite = parseField(task.parameters, "overwrite")
                let uploadUserId = parseField(task.parameters, "upload_user_id")
                let contentType = parseField(task.parameters, "content_type")

                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("filename").writeValue(filename)
                w.writeName("file_size").writeValue(fileSize.toString())
                w.writeName("category_id").writeValue(categoryId)
                w.writeName("target_type").writeValue(targetType)
                w.writeName("target_id").writeValue(targetId)
                w.writeName("overwrite").writeValue(overwrite)
                w.writeName("upload_user_id").writeValue(uploadUserId)
                w.writeName("content_type").writeValue(contentType)
                w.writeName("chunk_dir").writeValue(uploadDir.toString())
                w.writeName("final_part_path").writeValue(partPath.toString())
                w.endObject()
                w.flush()
                let paramsJson = String.fromUtf8(readToEnd(out))

                TaskDao.updateTaskParameters(taskIdInt, paramsJson)
                TaskDao.updateTaskType(taskIdInt, "asset_upload_process")
                TaskDao.updateTaskStatus(taskIdInt, "pending", "分片上传完成，等待处理", 70)
                TaskIO.appendLog(taskIdInt, "all chunks uploaded; handoff to asset_upload_process")
                TaskPoolService.getInstance().notifyTaskAvailable()
            }

            ResponseView.successJson(ctx, "{}", "Chunk uploaded successfully")
        } catch (e: Exception) {
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.errorJson(ctx, e.message, 500)
        }
    }

    /**
     * DELETE /api/assets/upload/:taskId
     */
    public static func cancelUpload(ctx: Ctx): Unit {
        try {
            let taskIdStr = ctx.paramsOpt("taskId") ?? ""
            if (taskIdStr.size == 0) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Task ID is required", 400)
                return
            }

            let taskId = try {
                Int64.parse(taskIdStr)
            } catch (_: Exception) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "Invalid taskId", 400)
                return
            }

            let task = TaskDao.getTaskDataById(taskId)
            if (task.id > 0 && task.status != "completed" && task.status != "failed" && task.status != "stopped") {
                let _ = TaskDao.updateTaskStatus(taskId, "failed", "上传已取消", task.progress)
                TaskIO.appendLog(taskId, "upload canceled by client")
            }

            let uploadDir = Path("${CACHE_DIR}/task/${taskIdStr}")
            if (exists(uploadDir)) {
                cleanupUploadDir(uploadDir)
            }

            TaskGroupKVDao.deleteGroup("asset_upload:${taskIdStr}")
            ResponseView.successJson(ctx, "{}", "ok")
        } catch (e: Exception) {
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.errorJson(ctx, e.message, 500)
        }
    }

    private static func parseInitJson(requestBody: String): InitPayload {
        let payload = InitPayload()
        if (requestBody.size == 0) {
            return payload
        }
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
                                case "filename" =>
                                    try {
                                        payload.filename = reader.readValue<String>().trimAscii()
                                    } catch (_: Exception) { let _ = reader.skip() }
                                case "filesize" =>
                                    try {
                                        payload.fileSize = reader.readValue<Int64>()
                                    } catch (_: Exception) {
                                        try { payload.fileSize = Int64.parse(reader.readValue<String>()) } catch (_: Exception) { let _ = reader.skip() }
                                    }
                                case "chunk_size" =>
                                    try {
                                        payload.chunkSize = reader.readValue<Int64>()
                                    } catch (_: Exception) {
                                        try { payload.chunkSize = Int64.parse(reader.readValue<String>()) } catch (_: Exception) { let _ = reader.skip() }
                                    }
                                case "total_chunks" =>
                                    try {
                                        payload.totalChunks = reader.readValue<Int64>()
                                    } catch (_: Exception) {
                                        try { payload.totalChunks = Int64.parse(reader.readValue<String>()) } catch (_: Exception) { let _ = reader.skip() }
                                    }
                                case "category_id" =>
                                    try {
                                        payload.categoryId = reader.readValue<String>().trimAscii()
                                    } catch (_: Exception) {
                                        try { payload.categoryId = reader.readValue<Int64>().toString() } catch (_: Exception) { let _ = reader.skip() }
                                    }
                                case "target_type" =>
                                    try {
                                        payload.targetType = reader.readValue<String>().trimAscii()
                                    } catch (_: Exception) { let _ = reader.skip() }
                                case "target_id" =>
                                    try {
                                        payload.targetId = reader.readValue<String>().trimAscii()
                                    } catch (_: Exception) {
                                        try { payload.targetId = reader.readValue<Int64>().toString() } catch (_: Exception) { let _ = reader.skip() }
                                    }
                                case "content_type" =>
                                    try {
                                        payload.contentType = reader.readValue<String>().trimAscii()
                                    } catch (_: Exception) { let _ = reader.skip() }
                                case "overwrite" =>
                                    try {
                                        payload.overwrite = reader.readValue<Bool>()
                                    } catch (_: Exception) {
                                        try {
                                            let raw = reader.readValue<String>().trimAscii().toAsciiLower()
                                            payload.overwrite = raw == "true" || raw == "1" || raw == "yes"
                                        } catch (_: Exception) {
                                            let _ = reader.skip()
                                        }
                                    }
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
            getLogger("asset_upload").warn("解析请求参数失败", ("error", e.message))
        }
        return payload
    }

    private static func normalizeTargetType(raw: String): String {
        let normalized = raw.trimAscii().toAsciiLower()
        if (normalized.size == 0) {
            return "archive"
        }
        return normalized
    }

    private static func isSupportedTargetType(targetType: String): Bool {
        return targetType == "archive" || targetType == "tag_icon" || targetType == "tag_background" || targetType == "user_avatar"
    }

    private static func validateInitTarget(
        ctx: Ctx,
        userId: Int64,
        targetType: String,
        targetId: String,
        categoryId: String,
        filename: String,
        overwrite: Bool
    ): Bool {
        if (targetType == "archive") {
            if (categoryId.trimAscii().size == 0) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "category_id is required", 400)
                return false
            }
            if (!overwrite) {
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
                            ctx.status(HttpStatusCode.STATUS_CONFLICT)
                            ResponseView.errorJson(ctx, "文件已存在: ${filename}", 409)
                            return false
                        }
                    case None =>
                        ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                        ResponseView.errorJson(ctx, "category not found", 400)
                        return false
                }
            }
            return true
        }

        if (targetType == "tag_icon" || targetType == "tag_background") {
            if (!UserDao.isAdmin(userId)) {
                ctx.status(HttpStatusCode.STATUS_FORBIDDEN)
                ResponseView.errorJson(ctx, "Administrator privileges required.", 403)
                return false
            }
            var tagId: Int64 = 0
            try { tagId = Int64.parse(targetId) } catch (_: Exception) { tagId = 0 }
            if (tagId <= 0) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.errorJson(ctx, "target_id(tag id) is required", 400)
                return false
            }
            if (TagDao.getById(tagId).isNone()) {
                ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                ResponseView.errorJson(ctx, "tag not found", 404)
                return false
            }
            return true
        }

        if (targetType == "user_avatar") {
            return true
        }

        return false
    }

    private static func resolveTaskName(targetType: String): String {
        match (targetType) {
            case "archive" => return "上传档案资源"
            case "tag_icon" => return "上传标签图标资源"
            case "tag_background" => return "上传标签背景资源"
            case "user_avatar" => return "上传头像资源"
            case _ => return "上传资源"
        }
    }

    private static func buildInitTaskParameters(
        filename: String,
        fileSize: Int64,
        chunkSize: Int64,
        totalChunks: Int64,
        categoryId: String,
        targetType: String,
        targetId: String,
        overwrite: Bool,
        userId: Int64,
        contentType: String
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("filename").writeValue(filename)
        w.writeName("filesize").writeValue(fileSize.toString())
        w.writeName("chunk_size").writeValue(chunkSize.toString())
        w.writeName("total_chunks").writeValue(totalChunks.toString())
        w.writeName("category_id").writeValue(categoryId)
        w.writeName("target_type").writeValue(targetType)
        w.writeName("target_id").writeValue(targetId)
        w.writeName("overwrite").writeValue(if (overwrite) { "true" } else { "false" })
        w.writeName("upload_user_id").writeValue(userId.toString())
        w.writeName("content_type").writeValue(contentType)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func parseField(parameters: String, key: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                if (k == key) {
                    return r.readValue<String>().trimAscii()
                } else {
                    r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return ""
    }

    private static func createTempDirectories(): Unit {
        if (!exists(Path(CACHE_DIR))) {
            Directory.create(Path(CACHE_DIR), recursive: true)
        }
        let taskDir = Path("${CACHE_DIR}/task")
        if (!exists(taskDir)) {
            Directory.create(taskDir, recursive: true)
        }
    }

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
}
