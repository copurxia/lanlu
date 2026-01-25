package lrr4cj.controllers

import cjoy.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lrr4cj.models.*
import lrr4cj.dao.*
import lrr4cj.services.*
import lrr4cj.utils.*

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
     * 批量取消任务（按 group_id）
     */
    public static func cancelTasksByGroup(ctx: JoyContext) {
        let groupId = ctx.getParam("groupId") ?? ""
        if (groupId.size == 0) {
            ctx.status(400)
            ctx.json("{\"error\":\"Invalid group ID\"}")
            return
        }

        let cancelledCount = TaskDao.updateTaskStatusByGroupId(groupId, "stopped", "Tasks cancelled by user")
        ctx.json("{\"success\":1,\"cancelled_count\":${cancelledCount}}")
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
     * 获取任务监控指标
     */
    public static func getMetrics(ctx: JoyContext) {
        // 获取各状态的任务数量
        let metrics = calculateMetrics()
        ctx.json(metrics)
    }

    /**
     * 按 group_id 查询任务列表
     */
    public static func getTasksByGroup(ctx: JoyContext) {
        let groupId = ctx.getParam("groupId") ?? ""
        if (groupId.size == 0) {
            ctx.status(400)
            ctx.json("{\"error\":\"Invalid group ID\"}")
            return
        }

        let tasks = TaskDao.getTasksByGroupId(groupId)
        let json = tasksArrayToJson(tasks)
        ctx.json(json)
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

    /**
     * 将任务数组转换为JSON
     */
    private static func tasksArrayToJson(tasks: Array<TaskData>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (t in tasks) {
            writeTaskDataJson(w, t)
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    /**
     * 计算任务监控指标
     */
    private static func calculateMetrics(): String {
        // 这里简化实现，实际应该从数据库查询统计信息
        // 为了性能考虑，可以考虑缓存这些指标
        return """
            {
            "message":"Metrics calculation not fully implemented yet",
            "note":"Use database queries to get real-time statistics"
            }"""
    }

}
