package lanlu.controllers

import cjoy.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.models.*
import lanlu.dao.*
import lanlu.services.*
import lanlu.task_runners.*
import lanlu.utils.*

/**
 * TaskPool控制器 - 提供任务管理API
 */
public class TaskPoolController {
    /**
     * 分页获取任务列表
     * GET /api/taskpool/tasks?page=1&pageSize=10&status=pending
     */
    public static func getTasks(ctx: JoyContext) {
        let pageStr = ctx.getQuery("page") ?? "1"
        let pageSizeStr = ctx.getQuery("pageSize") ?? "10"
        let statusRaw = ctx.getQuery("status") ?? ""

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
            if (status != "pending" && status != "running" && status != "completed" && status != "failed" && status != "stopped") {
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
    public static func getTaskDetail(ctx: JoyContext) {
        let taskIdStr = ctx.getParam("taskId") ?? ""
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
     * 取消单个任务
     */
    public static func cancelTask(ctx: JoyContext) {
        let taskIdStr = ctx.getParam("taskId") ?? ""
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
        if (task.status != "pending" && task.status != "running") {
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
    public static func retryTask(ctx: JoyContext) {
        let taskIdStr = ctx.getParam("taskId") ?? ""
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
     * 回应运行中 deno_task 发起的 rpc 选择请求
     * POST /api/admin/taskpool/{taskId}/rpc/select
     * body: { request_id: string, selected_index: number }
     */
    public static func respondRpcSelect(ctx: JoyContext) {
        let taskIdStr = ctx.getParam("taskId") ?? ""
        let taskId = try {
            Int64.parse(taskIdStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"success\":0,\"error\":\"Invalid task ID\"}")
            return
        }

        let body = ctx.readString().trimAscii()
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

        let (ok, msg) = if (abort) {
            DenoTaskRunner.abortRpcSelect(taskId, requestId)
        } else {
            DenoTaskRunner.resolveRpcSelect(taskId, requestId, selectedIndex)
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
        w.endObject()
    }

}
