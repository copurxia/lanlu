package lrr4cj.controllers

import cjoy.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lrr4cj.models.*
import lrr4cj.services.*
import lrr4cj.utils.*
import lrr4cj.views.*

/**
 * 定时任务控制器
 * 提供定时任务的REST API接口
 */
public class CronController {

    /**
     * 获取 TaskRunner 支持的任务类型列表
     * GET /api/cron/task-types
     */
    public static func getTaskTypes(ctx: JoyContext) {
        let types = TaskPoolService.getSupportedTaskTypes()
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(true)
        w.writeName("types")
        w.startArray()
        for (t in types) {
            w.writeValue(t)
        }
        w.endArray()
        w.endObject()
        w.flush()
        ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
    }

    /**
     * 获取定时任务列表（分页）
     * GET /api/cron/tasks?page=1&pageSize=10
     */
    public static func getTasks(ctx: JoyContext) {
        let pageStr = ctx.getQuery("page") ?? "1"
        let pageSizeStr = ctx.getQuery("pageSize") ?? "10"

        let page = try {
            let p = Int32.parse(pageStr)
            if (p < 1) { 1i32 } else { p }
        } catch (_: Exception) {
            1i32
        }

        let pageSize = try {
            let ps = Int32.parse(pageSizeStr)
            if (ps < 1) { 10i32 } else if (ps > 100) { 100i32 } else { ps }
        } catch (_: Exception) {
            10i32
        }

        let service = CronService.getInstance()
        let result = service.getScheduledTasks(page, pageSize)
        ctx.json(result.toJson())
    }

    /**
     * 获取单个定时任务
     * GET /api/cron/tasks/:id
     */
    public static func getTask(ctx: JoyContext) {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing task id\"}")
            return
        }

        let id = try {
            Int64.parse(idStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Invalid task id\"}")
            return
        }

        let service = CronService.getInstance()
        match (service.getScheduledTask(id)) {
            case Some(task) =>
                ctx.json(task.toJson())
            case None =>
                ctx.status(404)
                ctx.json("{\"success\":false,\"error\":\"Task not found\"}")
        }
    }

    /**
     * 创建定时任务
     * POST /api/cron/tasks
     * Body: { name, cronExpression, taskType, taskParameters?, enabled?, priority?, timeoutSeconds? }
     */
    public static func createTask(ctx: JoyContext) {
        let body = ctx.readString()
        if (body.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Empty request body\"}")
            return
        }

        // 解析JSON请求体
        let name = extractJsonString(body, "name")
        let cronExpression = extractJsonString(body, "cronExpression")
        let taskType = extractJsonString(body, "taskType")
        let taskParameters = extractJsonString(body, "taskParameters")
        let enabled = extractJsonBool(body, "enabled", true)
        let priority = extractJsonInt32(body, "priority", 50)
        let timeoutSeconds = extractJsonInt32(body, "timeoutSeconds", 3600)

        if (name.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing required field: name\"}")
            return
        }
        if (cronExpression.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing required field: cronExpression\"}")
            return
        }
        if (taskType.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing required field: taskType\"}")
            return
        }

        let service = CronService.getInstance()
        match (service.createScheduledTask(name, cronExpression, taskType,
            taskParameters: taskParameters, enabled: enabled, priority: priority,
            timeoutSeconds: timeoutSeconds)) {
            case Some(task) =>
                ctx.status(201)
                ctx.json("{\"success\":true,\"task\":${task.toJson()}}")
            case None =>
                ctx.status(400)
                ctx.json("{\"success\":false,\"error\":\"Failed to create task. Check cron expression.\"}")
        }
    }

    /**
     * 更新定时任务
     * PUT /api/cron/tasks/:id
     */
    public static func updateTask(ctx: JoyContext) {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing task id\"}")
            return
        }

        let id = try {
            Int64.parse(idStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Invalid task id\"}")
            return
        }

        let service = CronService.getInstance()
        let existingTask = match (service.getScheduledTask(id)) {
            case Some(t) => t
            case None =>
                ctx.status(404)
                ctx.json("{\"success\":false,\"error\":\"Task not found\"}")
                return
        }

        let body = ctx.readString()
        if (body.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Empty request body\"}")
            return
        }

        // 解析并更新字段
        var task = existingTask
        let name = extractJsonString(body, "name")
        if (!name.isEmpty()) {
            task.name = name
        }
        let cronExpression = extractJsonString(body, "cronExpression")
        if (!cronExpression.isEmpty()) {
            task.cronExpression = cronExpression
        }
        let taskType = extractJsonString(body, "taskType")
        if (!taskType.isEmpty()) {
            task.taskType = taskType
        }
        let taskParameters = extractJsonString(body, "taskParameters")
        if (!taskParameters.isEmpty()) {
            task.taskParameters = taskParameters
        }
        if (hasJsonField(body, "enabled")) {
            task.enabled = extractJsonBool(body, "enabled", task.enabled)
        }
        if (hasJsonField(body, "priority")) {
            task.priority = extractJsonInt32(body, "priority", task.priority)
        }
        if (hasJsonField(body, "timeoutSeconds")) {
            task.timeoutSeconds = extractJsonInt32(body, "timeoutSeconds", task.timeoutSeconds)
        }

        if (service.updateScheduledTask(task)) {
            ctx.json("{\"success\":true}")
        } else {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Failed to update task\"}")
        }
    }

    /**
     * 删除定时任务
     * DELETE /api/cron/tasks/:id
     */
    public static func deleteTask(ctx: JoyContext) {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing task id\"}")
            return
        }

        let id = try {
            Int64.parse(idStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Invalid task id\"}")
            return
        }

        let service = CronService.getInstance()
        if (service.deleteScheduledTask(id)) {
            ctx.json("{\"success\":true}")
        } else {
            ctx.status(404)
            ctx.json("{\"success\":false,\"error\":\"Task not found or failed to delete\"}")
        }
    }

    /**
     * 手动触发定时任务
     * POST /api/cron/tasks/:id/trigger
     */
    public static func triggerTask(ctx: JoyContext) {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing task id\"}")
            return
        }

        let id = try {
            Int64.parse(idStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Invalid task id\"}")
            return
        }

        let service = CronService.getInstance()
        if (service.triggerTaskNow(id)) {
            ctx.json("{\"success\":true,\"message\":\"Task triggered\"}")
        } else {
            ctx.status(404)
            ctx.json("{\"success\":false,\"error\":\"Task not found or failed to trigger\"}")
        }
    }

    /**
     * 启用定时任务
     * POST /api/cron/tasks/:id/enable
     */
    public static func enableTask(ctx: JoyContext) {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing task id\"}")
            return
        }

        let id = try {
            Int64.parse(idStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Invalid task id\"}")
            return
        }

        let service = CronService.getInstance()
        if (service.enableScheduledTask(id)) {
            ctx.json("{\"success\":true}")
        } else {
            ctx.status(404)
            ctx.json("{\"success\":false,\"error\":\"Task not found or failed to enable\"}")
        }
    }

    /**
     * 禁用定时任务
     * POST /api/cron/tasks/:id/disable
     */
    public static func disableTask(ctx: JoyContext) {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing task id\"}")
            return
        }

        let id = try {
            Int64.parse(idStr)
        } catch (_: Exception) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Invalid task id\"}")
            return
        }

        let service = CronService.getInstance()
        if (service.disableScheduledTask(id)) {
            ctx.json("{\"success\":true}")
        } else {
            ctx.status(404)
            ctx.json("{\"success\":false,\"error\":\"Task not found or failed to disable\"}")
        }
    }

    /**
     * 验证Cron表达式
     * POST /api/cron/validate
     * Body: { expression: "0 * * * *" }
     */
    public static func validateExpression(ctx: JoyContext) {
        let body = ctx.readString()
        if (body.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Empty request body\"}")
            return
        }

        let expression = extractJsonString(body, "expression")
        if (expression.isEmpty()) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"error\":\"Missing expression field\"}")
            return
        }

        let service = CronService.getInstance()
        let result = service.validateCronExpression(expression)
        ctx.json(result.toJson())
    }

    /**
     * 获取CronService状态
     * GET /api/cron/status
     */
    public static func getStatus(ctx: JoyContext) {
        let service = CronService.getInstance()
        let status = service.getStatus()
        ctx.json(status.toJson())
    }

    /**
     * 启动CronService
     * POST /api/cron/start
     */
    public static func startService(ctx: JoyContext) {
        let service = CronService.getInstance()
        if (service.start()) {
            ctx.json("{\"success\":true,\"message\":\"CronService started\"}")
        } else {
            ctx.status(500)
            ctx.json("{\"success\":false,\"error\":\"Failed to start CronService\"}")
        }
    }

    /**
     * 停止CronService
     * POST /api/cron/stop
     */
    public static func stopService(ctx: JoyContext) {
        let service = CronService.getInstance()
        if (service.stop()) {
            ctx.json("{\"success\":true,\"message\":\"CronService stopped\"}")
        } else {
            ctx.status(500)
            ctx.json("{\"success\":false,\"error\":\"Failed to stop CronService\"}")
        }
    }

    // ========== JSON解析辅助函数 ==========

    private static func extractJsonString(json: String, key: String): String {
        let keyIndexOpt = json.indexOf("\"${key}\"")
        let keyIndex: Int64 = match (keyIndexOpt) {
            case Some(idx) => idx
            case None => return ""
        }

        // 找到冒号后的引号
        let colonIndexOpt = json.indexOf(":", keyIndex)
        let colonIndex: Int64 = match (colonIndexOpt) {
            case Some(idx) => idx
            case None => return ""
        }

        // 找到值的开始引号
        var startQuote: Int64 = -1
        for (i in (colonIndex + 1)..json.size) {
            let c = json[i]
            if (c == 34) {  // '"'
                startQuote = Int64(i)
                break
            } else if (c != 32 && c != 9 && c != 10 && c != 13) {  // 非空白字符
                // 可能是数字或布尔值，不是字符串
                return ""
            }
        }

        if (startQuote < 0) {
            return ""
        }

        // 找到值的结束引号
        var endQuote: Int64 = -1
        var escaped = false
        for (i in (startQuote + 1)..json.size) {
            let c = json[i]
            if (escaped) {
                escaped = false
                continue
            }
            if (c == 92) {  // '\\'
                escaped = true
                continue
            }
            if (c == 34) {  // '"'
                endQuote = Int64(i)
                break
            }
        }

        if (endQuote < 0) {
            return ""
        }

        // 反转义JSON字符串
        let raw = json[(startQuote + 1)..endQuote]
        return unescapeJsonString(raw)
    }

    // 反转义JSON字符串中的转义字符
    private static func unescapeJsonString(str: String): String {
        var result = str
        result = result.replace("\\\"", "\"")
        result = result.replace("\\\\", "\\")
        result = result.replace("\\n", "\n")
        result = result.replace("\\r", "\r")
        result = result.replace("\\t", "\t")
        return result
    }

    private static func extractJsonInt32(json: String, key: String, defaultValue: Int32): Int32 {
        let keyIndexOpt = json.indexOf("\"${key}\"")
        let keyIndex: Int64 = match (keyIndexOpt) {
            case Some(idx) => idx
            case None => return defaultValue
        }

        let colonIndexOpt = json.indexOf(":", keyIndex)
        let colonIndex: Int64 = match (colonIndexOpt) {
            case Some(idx) => idx
            case None => return defaultValue
        }

        // 找到数字的开始
        var numStart: Int64 = -1
        for (i in (colonIndex + 1)..json.size) {
            let c = json[i]
            if (c >= 48 && c <= 57 || c == 45) {  // '0'-'9' or '-'
                numStart = Int64(i)
                break
            } else if (c != 32 && c != 9 && c != 10 && c != 13) {
                return defaultValue
            }
        }

        if (numStart < 0) {
            return defaultValue
        }

        // 找到数字的结束
        var numEnd = numStart
        for (i in numStart..json.size) {
            let c = json[i]
            if (c >= 48 && c <= 57) {
                numEnd = Int64(i) + 1
            } else {
                break
            }
        }

        let numStr = json[numStart..numEnd]
        try {
            return Int32.parse(numStr)
        } catch (_: Exception) {
            return defaultValue
        }
    }

    private static func extractJsonBool(json: String, key: String, defaultValue: Bool): Bool {
        let keyIndexOpt = json.indexOf("\"${key}\"")
        let keyIndex: Int64 = match (keyIndexOpt) {
            case Some(idx) => idx
            case None => return defaultValue
        }

        let colonIndexOpt = json.indexOf(":", keyIndex)
        let colonIndex: Int64 = match (colonIndexOpt) {
            case Some(idx) => idx
            case None => return defaultValue
        }

        // 查找true或false
        let afterColon = json[(colonIndex + 1)..]
        let trimmed = afterColon.trimStart()
        if (trimmed.startsWith("true")) {
            return true
        } else if (trimmed.startsWith("false")) {
            return false
        }

        return defaultValue
    }

    private static func hasJsonField(json: String, key: String): Bool {
        match (json.indexOf("\"${key}\"")) {
            case Some(_) => return true
            case None => return false
        }
    }
}
