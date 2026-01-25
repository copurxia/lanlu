package lrr4cj.controllers

import cjoy.*
import std.convert.*
import lrr4cj.models.*
import lrr4cj.services.*
import lrr4cj.dao.*
import lrr4cj.utils.*

/**
 * Shinobu控制器（兼容旧API，实际调用CronService）
 */
public class ShinobuController {
    /**
     * 获取Shinobu状态（返回CronService状态）
     */
    public static func getShinobuStatus(ctx: JoyContext) {
        let service = CronService.getInstance()
        let cronStatus = service.getStatus()
        let alive: Int32 = if (cronStatus.running) { 1 } else { 0 }
        let status = ShinobuStatus(1, alive, "shinobu_status", 0)
        ctx.json(status.toJson())
    }

    /**
     * 停止Shinobu（停止CronService）
     */
    public static func stopShinobu(ctx: JoyContext) {
        let service = CronService.getInstance()
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
     * 重启Shinobu（重启CronService）
     */
    public static func restartShinobu(ctx: JoyContext) {
        let service = CronService.getInstance()
        service.stop()
        let success = service.start()
        let result = ShinobuResult(if (success) { 1 } else { 0 }, "shinobu_restart", 0)
        ctx.json(result.toJson())
    }

    /**
     * 启动Shinobu（启动CronService）
     */
    public static func startShinobu(ctx: JoyContext) {
        let service = CronService.getInstance()
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
        let service = CronService.getInstance()
        let result = service.scanArchives()
        let json = "{\"processed_count\":${result.processedCount},\"error_count\":${result.errorCount},\"total_found\":${result.totalFound},\"task_id\":${result.taskId}}"
        ctx.json(json)
    }

    /**
     * 获取Shinobu配置（返回CronService状态）
     */
    public static func getShinobuConfiguration(ctx: JoyContext) {
        let service = CronService.getInstance()
        let cronStatus = service.getStatus()
        // 返回兼容格式
        let json = """
            {
            "enableAutoScan":false,
            "enableInitialScan":${SystemSettingsService.getBoolean("ENABLE_INITIAL_SCAN")},
            "scanIntervalCron":"",
            "enableAutoThumbnail":false,
            "thumbnailIntervalCron":"",
            "scanFallbackIntervalMs":0,
            "cronServiceRunning":${cronStatus.running},
            "scheduledTasksCount":${cronStatus.totalTasks},
            "enabledTasksCount":${cronStatus.enabledTasks}
            }"""
        ctx.json(json)
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

}
