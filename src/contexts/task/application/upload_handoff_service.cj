package lanlu.contexts.task.application

import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.shared.utils.*

/**
 * Upload phase handoff service.
 *
 * Keeps the HTTP controller out of the task phase protocol: the controller only
 * validates chunk IO and delegates finalization here.
 */
public class UploadHandoffService {
    private static let uploadIdleTimeoutSeconds: Int32 = 600

    public static func completeAssetUpload(
        taskId: Int64,
        parameters: String,
        fileSize: Int64,
        uploadDir: String,
        finalPartPath: String,
        kvGroupId: String,
        kvStore: TaskKVStore,
        kvTtlSeconds: Int64
    ): Bool {
        let handoff = kvStore.insertIfAbsent(kvGroupId, "handoff", "1", kvTtlSeconds)
        if (!handoff) {
            return false
        }

        let filename = parseField(parameters, "filename")
        let categoryId = parseField(parameters, "category_id")
        let targetType = parseField(parameters, "target_type")
        let targetId = parseField(parameters, "target_id")
        let overwrite = parseField(parameters, "overwrite")
        let uploadUserId = parseField(parameters, "upload_user_id")
        let contentType = parseField(parameters, "content_type")

        let paramsJson = buildAssetUploadProcessParams(
            taskId,
            filename,
            fileSize,
            categoryId,
            targetType,
            targetId,
            overwrite,
            uploadUserId,
            contentType,
            uploadDir,
            finalPartPath
        )

        let _ = TaskDao.updateTaskParameters(taskId, paramsJson)
        let groupId = "asset_upload:${taskId}"
        let processTask = TaskModel.createTaskWithOptions(
            "处理上传资源",
            "asset_upload_process",
            paramsJson,
            5,
            groupId,
            "asset_upload"
        )
        if (processTask.id <= 0) {
            TaskIO.appendLog(taskId,
                "all chunks uploaded; failed to create asset_upload_process, waiting for timeout cleanup")
            let _ = TaskDao.extendTimeoutAndUpdateProgress(
                taskId,
                uploadIdleTimeoutSeconds,
                70,
                "分片上传完成，等待处理任务"
            )
            return true
        }

        TaskPoolService.getInstance().notifyTaskAvailable()
        TaskIO.appendLog(taskId, "all chunks uploaded; spawned asset_upload_process=${processTask.id}")
        TaskIO.writeOutput(taskId, buildAssetUploadPlaceholderOutput(processTask.id))
        TaskModel.completeTaskWithPhase(taskId, "asset_upload completed", "handoff_completed")
        return true
    }

    private static func buildAssetUploadProcessParams(
        taskId: Int64,
        filename: String,
        fileSize: Int64,
        categoryId: String,
        targetType: String,
        targetId: String,
        overwrite: String,
        uploadUserId: String,
        contentType: String,
        uploadDir: String,
        finalPartPath: String
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("upload_task_id").writeValue(taskId.toString())
        w.writeName("filename").writeValue(filename)
        w.writeName("file_size").writeValue(fileSize.toString())
        w.writeName("category_id").writeValue(categoryId)
        w.writeName("target_type").writeValue(targetType)
        w.writeName("target_id").writeValue(targetId)
        w.writeName("overwrite").writeValue(overwrite)
        w.writeName("upload_user_id").writeValue(uploadUserId)
        w.writeName("content_type").writeValue(contentType)
        w.writeName("chunk_dir").writeValue(uploadDir)
        w.writeName("final_part_path").writeValue(finalPartPath)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildAssetUploadPlaceholderOutput(processTaskId: Int64): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("process_task_id").writeValue(processTaskId)
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
            if (r.peek() != Some(BeginObject)) {
                return ""
            }
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
}
