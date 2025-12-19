package lrr4cj.controllers

import cjoy.*
import std.convert.*
import lrr4cj.models.*
import lrr4cj.services.*
import lrr4cj.dao.*

/**
 * Shinobu控制器
 */
public class ShinobuController {
    /**
     * 获取Shinobu状态
     */
    public static func getShinobuStatus(ctx: JoyContext) {
        let service = ShinobuService.getInstance()
        let statusData = service.getStatus()
        let status = ShinobuStatus(statusData.success, statusData.isAlive, statusData.operation, statusData.pid)
        ctx.json(status.toJson())
    }
    
    /**
     * 停止Shinobu
     */
    public static func stopShinobu(ctx: JoyContext) {
        let service = ShinobuService.getInstance()
        let success = service.stop()
        if (success) {
            let response = "{\"operation\":\"shinobu_stop\",\"success\":1}"
            ctx.json(response)
        } else {
            let response = "{\"operation\":\"shinobu_stop\",\"success\":0}"
            ctx.json(response)
        }
    }
    
    /**
     * 重启Shinobu
     */
    public static func restartShinobu(ctx: JoyContext) {
        let service = ShinobuService.getInstance()
        let success = service.restart()
        let statusData = service.getStatus()
        let result = ShinobuResult(if (success) { 1 } else { 0 }, "shinobu_restart", statusData.pid)
        ctx.json(result.toJson())
    }
    
    /**
     * 启动Shinobu
     */
    public static func startShinobu(ctx: JoyContext) {
        let service = ShinobuService.getInstance()
        let success = service.start()
        if (success) {
            let response = "{\"operation\":\"shinobu_start\",\"success\":1}"
            ctx.json(response)
        } else {
            let response = "{\"operation\":\"shinobu_start\",\"success\":0}"
            ctx.json(response)
        }
    }
    
    /**
     * 扫描档案文件
     */
    public static func scanArchives(ctx: JoyContext) {
        let service = ShinobuService.getInstance()
        let result = service.scanArchives()
        let json = "{\"processed_count\":${result.processedCount},\"error_count\":${result.errorCount},\"total_found\":${result.totalFound},\"task_id\":${result.taskId}}"
        ctx.json(json)
    }
    
    /**
     * 获取Shinobu配置
     */
    public static func getShinobuConfiguration(ctx: JoyContext) {
        let service = ShinobuService.getInstance()
        let config = service.getConfiguration()
        ctx.json(config.toJson())
    }

    /**
     * 获取启动任务历史
     */
    public static func getStartupTasks(ctx: JoyContext) {
        // 获取查询参数
        let limitStr = ctx.getQuery("limit") ?? ""
        let limit = if (limitStr.size > 0) {
            try {
                let parsed = Int32.parse(limitStr)
                if (parsed > 100) { 100i32 } else if (parsed < 1) { 10i32 } else { parsed }
            } catch (_: Exception) {
                10i32
            }
        } else {
            10i32
        }

        // 查询启动任务
        let tasks = TaskDao.getTasksByTriggerSource("startup", limit)

        // 构建JSON响应
        var json = "{\"tasks\":["
        for (i in 0..tasks.size) {
            if (i > 0) {
                json = json + ","
            }
            let task = tasks[i]

            // 计算执行时长
            let durationMs = calculateDuration(task.startedAt, task.completedAt)

            json = json + """
                {
                "id":${task.id},
                "task_type":"${escapeJson(task.taskType)}",
                "status":"${escapeJson(task.status)}",
                "trigger_source":"${escapeJson(task.triggerSource)}",
                "created_at":"${escapeJson(task.createdAt)}",
                "started_at":"${escapeJson(task.startedAt)}",
                "completed_at":"${escapeJson(task.completedAt)}",
                "duration_ms":${durationMs},
                "message":"${escapeJson(task.message)}"
                }"""
        }
        json = json + "]}"

        ctx.json(json)
    }

    /**
     * 计算任务执行时长（毫秒）
     */
    private static func calculateDuration(startedAt: String, completedAt: String): Int64 {
        // 简化实现：如果两个时间戳都存在，返回一个占位值
        // 实际应该解析时间戳并计算差值
        if (startedAt.size > 0 && completedAt.size > 0) {
            return 0 // 占位值，实际需要时间戳解析
        }
        return 0
    }

    /**
     * JSON字符串转义
     */
    private static func escapeJson(s: String): String {
        var escaped = s
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }
}
