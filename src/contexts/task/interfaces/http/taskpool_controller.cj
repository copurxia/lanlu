package lanlu.contexts.task.interfaces.http

import ignite.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.task.application.*
import lanlu.contexts.plugin.domain.*
import lanlu.shared.utils.*

/**
 * TaskPool控制器 - 提供任务管理API
 */
public class TaskPoolController {
    private static let taskStreamPingMillis: Int64 = 15000
    // 第一阶段性能优化：将单次日志读取上限下调到 4KB。
    private static let taskStreamLogMaxBytes: Int64 = 4 * 1024

    /**
     * 分页获取任务列表
     * GET /api/taskpool/tasks?page=1&pageSize=10&status=pending
     */
    public static func getTasks(ctx: Ctx) {
        let pageStr = ctx.query("page") ?? "1"
        let pageSizeStr = ctx.query("pageSize") ?? "10"
        let statusRaw = ctx.query("status") ?? ""

        let page = try {
            Int32.parse(pageStr)
        } catch (_: Exception) {
            1i32
        }

        let pageSize = try {
            Int32.parse(pageSizeStr)
        } catch (_: Exception) {
            10i32
        }

        // 计算偏移量
        let offset = (page - 1) * pageSize

        // 可选状态过滤（用于前端 tabs + 正确分页）
        // Frontend sends lowercase; keep strict matching to avoid relying on extra String APIs.
        let status = statusRaw
        let hasStatusFilter = status.size > 0 && status != "all"
        if (hasStatusFilter) {
            // Only allow known statuses to avoid unexpected DB usage/typos.
            if (status != "pending" && status != "running" && status != "waiting" && status != "completed" && status != "failed" && status != "stopped") {
                ctx.status(400)
                ctx.json("{\"error\":\"Invalid status\"}")
                return
            }
        }

        // 获取任务列表和总数
        let tasks = if (hasStatusFilter) {
            TaskDao.getTasksWithPaginationByStatus(offset, pageSize, status)
        } else {
            TaskDao.getTasksWithPagination(offset, pageSize)
        }
        let total = if (hasStatusFilter) {
            TaskDao.getTaskCountByStatus(status)
        } else {
            TaskDao.getTaskCount()
        }
        // 用于前端 “全部” 标签的徽章显示（即使当前在筛选状态下也可显示总量）
        let totalAll = TaskDao.getTaskCount()
        let totalPages = (total + pageSize - 1) / pageSize

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("tasks")
        w.startArray()
        for (t in tasks) {
            writeTaskDataJson(w, t)
        }
        w.endArray()
        w.writeName("total").writeValue(total)
        w.writeName("totalAll").writeValue(totalAll)
        w.writeName("page").writeValue(page)
        w.writeName("pageSize").writeValue(pageSize)
        w.writeName("totalPages").writeValue(totalPages)
        w.endObject()
        w.flush()
        ctx.json(String.fromUtf8(readToEnd(out)))
    }

    /**
     * 获取任务详情
     */
    public static func getTaskDetail(ctx: Ctx) {
        let taskIdStr = ctx.paramsOpt("taskId") ?? ""
        let taskId = try {
            Int64.parse(taskIdStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"error\":\"Invalid task ID\"}")
            return
        }

        let task = TaskDao.getTaskDataById(taskId)
        if (task.id == 0) {
            ctx.status(404)
            ctx.json("{\"error\":\"Task not found\"}")
            return
        }

        // For detail polling, prefer TaskIO output over the DB `result` field.
        // Many runners write the final JSON result to TaskIO to keep DB rows small.
        let out = TaskIO.readOutput(taskId)
        if (out.trimAscii().size > 0) {
            task.result = out
        }

        let out2 = ByteBuffer()
        let w2 = JsonWriter(out2)
        writeTaskDataJson(w2, task)
        w2.flush()
        ctx.json(String.fromUtf8(readToEnd(out2)))
    }

    /**
     * 任务详情SSE流（替代前端高频HTTP轮询）
     * GET /api/admin/taskpool/{taskId}/stream
     */
    public static func streamTask(ctx: Ctx) {
        let taskIdStr = ctx.paramsOpt("taskId") ?? ""
        let taskId = try {
            Int64.parse(taskIdStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"error\":\"Invalid task ID\"}")
            return
        }

        let initialTask = loadTaskForStreaming(taskId)
        if (initialTask.id == 0) {
            ctx.status(404)
            ctx.json("{\"error\":\"Task not found\"}")
            return
        }

        // 使用 ignite 内置 SSE（自动设置 headers）
        let sse = ctx.sse()
        let eventHub = TaskEventHub.getInstance()
        var eventId = 1i64
        var lastPayload = ""
        var lastLogTail = ""
        var revision = eventHub.currentRevision(taskId)

        while (true) {
            try {
                let task = loadTaskForStreaming(taskId)
                if (task.id == 0) {
                    sse.sendEvent("{\"error\":\"Task not found\"}", event: "error", id: "${eventId}")
                    return
                }

                // v2 stream payload: send bounded tail + delta to reduce client-side update cost.
                let logTail = TaskIO.readLog(taskId, maxBytes: taskStreamLogMaxBytes)
                let stableRevision = eventHub.currentRevision(taskId)
                if (stableRevision != revision) {
                    revision = stableRevision
                    continue
                }
                let logDelta = computeLogDelta(lastLogTail, logTail)
                let payload = buildTaskStreamData(task, logTail, logDelta, eventId == 1, if (eventId == 1) { "snapshot" } else { "task_changed" })
                if (eventId == 1 || payload != lastPayload) {
                    let eventName = if (eventId == 1) { "snapshot" } else { "task" }
                    sse.sendEvent(payload, event: eventName, id: "${eventId}")
                    lastPayload = payload
                    lastLogTail = logTail
                    eventId += 1
                }

                if (isTerminalStatus(task.status)) {
                    sse.sendEvent(payload, event: "done", id: "${eventId}")
                    return
                }

                let waitResult = eventHub.awaitNext(taskId, revision, taskStreamPingMillis)
                revision = waitResult.revision
                if (!waitResult.changed) {
                    sse.sendEvent("{\"ok\":1}", event: "ping", id: "${eventId}")
                    eventId += 1
                } else {
                    let updatedTask = loadTaskForStreaming(taskId)
                    if (updatedTask.id == 0) {
                        sse.sendEvent("{\"error\":\"Task not found\"}", event: "error", id: "${eventId}")
                        return
                    }
                    let updatedLogTail = TaskIO.readLog(taskId, maxBytes: taskStreamLogMaxBytes)
                    let updatedLogDelta = computeLogDelta(lastLogTail, updatedLogTail)
                    let eventPayload = buildTaskStreamData(updatedTask, updatedLogTail, updatedLogDelta, false, waitResult.eventType)
                    if (eventPayload != lastPayload) {
                        sse.sendEvent(eventPayload, event: "task", id: "${eventId}")
                        lastPayload = eventPayload
                        lastLogTail = updatedLogTail
                        eventId += 1
                    }
                }
            } catch (e: Exception) {
                getLogger("taskpool_stream").debug(
                    "SSE stream closed",
                    ("task_id", taskId.toString()),
                    ("reason", e.message)
                )
                break
            }
        }
    }

    /**
     * 取消单个任务
     */
    public static func cancelTask(ctx: Ctx) {
        let taskIdStr = ctx.paramsOpt("taskId") ?? ""
        let taskId = try {
            Int64.parse(taskIdStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"error\":\"Invalid task ID\"}")
            return
        }

        let task = TaskDao.getTaskDataById(taskId)
        if (task.id == 0) {
            ctx.status(404)
            ctx.json("{\"error\":\"Task not found\"}")
            return
        }

        // 只能取消 pending 或 running 状态的任务
        if (task.status != "pending" && task.status != "running" && task.status != "waiting") {
            ctx.status(400)
            ctx.json("{\"error\":\"Task cannot be cancelled (status: ${task.status})\"}")
            return
        }

        // 更新任务状态为 stopped
        let success = TaskDao.updateTaskStatus(taskId, "stopped", "Task cancelled by user", 0)
        if (success) {
            ctx.json("{\"success\":1,\"message\":\"Task cancelled successfully\"}")
        } else {
            ctx.status(500)
            ctx.json("{\"error\":\"Failed to cancel task\"}")
        }
    }

    /**
     * 重试失败的任务
     */
    public static func retryTask(ctx: Ctx) {
        let taskIdStr = ctx.paramsOpt("taskId") ?? ""
        let taskId = try {
            Int64.parse(taskIdStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"error\":\"Invalid task ID\"}")
            return
        }

        let task = TaskDao.getTaskDataById(taskId)
        if (task.id == 0) {
            ctx.status(404)
            ctx.json("{\"error\":\"Task not found\"}")
            return
        }

        // 只能重试 failed 或 stopped 状态的任务
        if (task.status != "failed" && task.status != "stopped") {
            ctx.status(400)
            ctx.json("{\"error\":\"Task cannot be retried (status: ${task.status})\"}")
            return
        }

        // 创建新任务（复制原任务的参数）
        let newTask = TaskModel.createTaskWithOptions(
            task.name,
            task.taskType,
            task.parameters,
            task.priority,
            task.groupId,
            "manual"
        )

        if (newTask.id > 0) {
            TaskPoolService.getInstance().notifyTaskAvailable()
            ctx.json("{\"success\":1,\"new_task_id\":${newTask.id}}")
        } else {
            ctx.status(500)
            ctx.json("{\"error\":\"Failed to create retry task\"}")
        }
    }

    /**
     * 回应运行中 wasm_task 发起的 rpc 选择请求
     * POST /api/admin/taskpool/{taskId}/rpc/select
     * body: { request_id: string, selected_index: number }
     */
    public static func respondRpcSelect(ctx: Ctx) {
        let taskIdStr = ctx.paramsOpt("taskId") ?? ""
        let taskId = try {
            Int64.parse(taskIdStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"success\":0,\"error\":\"Invalid task ID\"}")
            return
        }

        let body = ctx.bodyString().trimAscii()
        var requestId = ""
        var selectedIndex = -1i32
        var abort = false
        if (body.size > 0) {
            try {
                var buf = ByteBuffer()
                unsafe { buf.write(body.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "request_id" => requestId = r.readValue<String>().trimAscii()
                            case "requestId" => requestId = r.readValue<String>().trimAscii()
                            case "selected_index" => selectedIndex = Int32.parse(r.readValue<String>().trimAscii())
                            case "selectedIndex" => selectedIndex = Int32.parse(r.readValue<String>().trimAscii())
                            case "abort" =>
                                let v = r.readValue<String>().trimAscii().toAsciiLower()
                                abort = v == "1" || v == "true" || v == "yes" || v == "y"
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}
        }

        if (requestId.size == 0 || (!abort && selectedIndex < 0)) {
            ctx.status(400)
            ctx.json("{\"success\":0,\"error\":\"request_id and (selected_index or abort) are required\"}")
            return
        }

        var ok = false
        var msg = "request not found"
        if (abort) {
            let (wasmOk, wasmMsg) = WasmHostBridge.abortRpcSelect(taskId, requestId)
            ok = wasmOk
            msg = wasmMsg
        } else {
            let (wasmOk, wasmMsg) = WasmHostBridge.resolveRpcSelect(taskId, requestId, selectedIndex)
            ok = wasmOk
            msg = wasmMsg
        }
        if (!ok) {
            ctx.status(404)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(0)
            w.writeName("error").writeValue(msg)
            w.endObject()
            w.flush()
            ctx.json(String.fromUtf8(readToEnd(out)))
            return
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("message").writeValue("ok")
        w.endObject()
        w.flush()
        ctx.json(String.fromUtf8(readToEnd(out)))
    }

    /**
     * 更新任务进度
     * PUT /api/admin/taskpool/{taskId}/progress
     * body: { progress: number, message: string }
     */
    public static func updateTaskProgress(ctx: Ctx) {
        let taskIdStr = ctx.paramsOpt("taskId") ?? ""
        let taskId = try {
            Int64.parse(taskIdStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"success\":0,\"error\":\"Invalid task ID\"}")
            return
        }

        let task = TaskDao.getTaskDataById(taskId)
        if (task.id == 0) {
            ctx.status(404)
            ctx.json("{\"success\":0,\"error\":\"Task not found\"}")
            return
        }

        // 解析请求体
        let body = ctx.bodyString().trimAscii()
        var progress: Int32 = 0
        var message = ""

        if (body.size > 0) {
            try {
                var buf = ByteBuffer()
                unsafe { buf.write(body.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "progress" =>
                                try {
                                    progress = Int32.parse(r.readValue<String>())
                                } catch (_: Exception) {
                                    try {
                                        progress = r.readValue<Int32>()
                                    } catch (_: Exception) {
                                        let _ = r.skip()
                                    }
                                }
                            case "message" =>
                                message = r.readValue<String>()
                            case _ =>
                                let _ = r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}
        }

        // 限制 progress 在 0-100 范围内
        if (progress < 0) { progress = 0 }
        if (progress > 100) { progress = 100 }

        // 使用 message 作为消息，如果为空则使用默认消息
        let effectiveMessage = if (message.size > 0) { message } else { "上传中" }

        // 更新任务进度但不改变主状态，避免把 waiting/pending 任务提前写成 running。
        let success = TaskDao.updateTaskProgressPreserveStatus(taskId, progress, effectiveMessage)
        if (success) {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(1)
            w.writeName("message").writeValue("Progress updated")
            w.endObject()
            w.flush()
            ctx.json(String.fromUtf8(readToEnd(out)))
        } else {
            ctx.status(500)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(0)
            w.writeName("error").writeValue("Failed to update task progress")
            w.endObject()
            w.flush()
            ctx.json(String.fromUtf8(readToEnd(out)))
        }
    }

    /**
     * 将任务数据转换为JSON
     */
    private static func writeTaskDataJson(w: JsonWriter, task: TaskData): Unit {
        w.startObject()
        w.writeName("id").writeValue(task.id)
        w.writeName("name").writeValue(task.name)
        w.writeName("task_type").writeValue(task.taskType)
        w.writeName("status").writeValue(task.status)
        w.writeName("progress").writeValue(task.progress)
        w.writeName("message").writeValue(task.message)
        w.writeName("plugin_namespace").writeValue(task.pluginNamespace)
        w.writeName("parameters").writeValue(task.parameters)
        w.writeName("result").writeValue(task.result)
        w.writeName("priority").writeValue(task.priority)
        w.writeName("group_id").writeValue(task.groupId)
        w.writeName("timeout_at").writeValue(task.timeoutAt)
        w.writeName("trigger_source").writeValue(task.triggerSource)
        w.writeName("created_at").writeValue(task.createdAt)
        w.writeName("started_at").writeValue(task.startedAt)
        w.writeName("completed_at").writeValue(task.completedAt)
        if (task.activeKey.size > 0) {
            w.writeName("active_key").writeValue(task.activeKey)
        }
        w.writeName("phase").writeValue(computeTaskPhase(task))
        let waitingReason = computeWaitingReason(task)
        if (waitingReason.size > 0) {
            w.writeName("waiting_reason").writeValue(waitingReason)
        }
        w.endObject()
    }

    private static func loadTaskForStreaming(taskId: Int64): TaskData {
        let task = TaskDao.getTaskDataById(taskId)
        if (task.id == 0) {
            return task
        }
        // 与详情接口一致：优先使用 TaskIO 输出。
        let out = TaskIO.readOutput(taskId)
        if (out.trimAscii().size > 0) {
            task.result = out
        }
        return task
    }

    private static func buildTaskStreamData(task: TaskData, logTail: String, logDelta: String, isSnapshot: Bool, eventType: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("v").writeValue(2)
        w.writeName("event_type").writeValue(eventType)
        w.writeName("task")
        writeTaskStreamTaskJson(w, task)
        w.writeName("stream")
        w.startObject()
        w.writeName("mode").writeValue(if (isSnapshot) { "snapshot" } else { "delta" })
        w.writeName("log_tail").writeValue(logTail)
        w.writeName("log_delta").writeValue(logDelta)
        w.writeName("log_bytes").writeValue(Int64(logTail.size))
        w.endObject()
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func computeLogDelta(previous: String, current: String): String {
        if (current.size == 0) {
            return ""
        }
        if (previous.size == 0) {
            return current
        }
        if (current == previous) {
            return ""
        }
        if (current.startsWith(previous) && current.size >= previous.size) {
            return current[previous.size..current.size]
        }
        return current
    }

    private static func writeTaskStreamTaskJson(w: JsonWriter, task: TaskData): Unit {
        w.startObject()
        w.writeName("id").writeValue(task.id)
        w.writeName("name").writeValue(task.name)
        w.writeName("task_type").writeValue(task.taskType)
        w.writeName("status").writeValue(task.status)
        w.writeName("progress").writeValue(task.progress)
        w.writeName("message").writeValue(task.message)
        w.writeName("plugin_namespace").writeValue(task.pluginNamespace)
        w.writeName("parameters").writeValue(task.parameters)
        // Stream endpoint is for incremental status updates; fetch detail separately for final output.
        w.writeName("result").writeValue("")
        w.writeName("priority").writeValue(task.priority)
        w.writeName("group_id").writeValue(task.groupId)
        w.writeName("timeout_at").writeValue(task.timeoutAt)
        w.writeName("trigger_source").writeValue(task.triggerSource)
        w.writeName("created_at").writeValue(task.createdAt)
        w.writeName("started_at").writeValue(task.startedAt)
        w.writeName("completed_at").writeValue(task.completedAt)
        if (task.activeKey.size > 0) {
            w.writeName("active_key").writeValue(task.activeKey)
        }
        w.writeName("phase").writeValue(computeTaskPhase(task))
        let waitingReason = computeWaitingReason(task)
        if (waitingReason.size > 0) {
            w.writeName("waiting_reason").writeValue(waitingReason)
        }
        w.endObject()
    }

    private static func isTerminalStatus(status: String): Bool {
        return status == "completed" || status == "failed" || status == "stopped"
    }

    private static func computeTaskPhase(task: TaskData): String {
        if (task.phase.trimAscii().size > 0) {
            return task.phase
        }
        if (task.status == "waiting") {
            let waitingReason = computeWaitingReason(task)
            if (waitingReason == "rpc_select") {
                return "awaiting_selection"
            }
            if (waitingReason == "task_dependency") {
                return "awaiting_dependency"
            }
            return "waiting"
        }

        if (task.taskType == "upload" || task.taskType == "asset_upload") {
            if (task.status == "pending" && task.progress >= 70) {
                return "queued_for_processing"
            }
            if (!isTerminalStatus(task.status)) {
                return "uploading"
            }
        }

        if (task.taskType == "upload_process" || task.taskType == "asset_upload_process") {
            return if (isTerminalStatus(task.status)) { "processed" } else { "processing_upload" }
        }

        if (task.taskType == "wasm_task") {
            return if (isTerminalStatus(task.status)) { "plugin_finished" } else { "executing_plugin" }
        }

        if (task.taskType == "download_url" || task.taskType == "metadata_plugin") {
            return if (isTerminalStatus(task.status)) { "submitted" } else { "dispatching_plugin" }
        }

        if (task.status == "pending") {
            return "queued"
        }
        if (task.status == "running") {
            return "executing"
        }
        return task.status
    }

    private static func computeWaitingReason(task: TaskData): String {
        if (task.waitingReason.trimAscii().size > 0) {
            return task.waitingReason
        }
        if (task.status != "waiting") {
            return ""
        }

        if (task.message.contains("人工选择") || task.message.contains("选择结果") || task.message.contains("rpc")) {
            return "rpc_select"
        }
        if (task.taskType.contains("callback")) {
            return "task_dependency"
        }
        if (task.message.contains("依赖")) {
            return "task_dependency"
        }
        return "external_signal"
    }

}
