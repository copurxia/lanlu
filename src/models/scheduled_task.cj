package lrr4cj.models

import lrr4cj.dao.*
import lrr4cj.utils.*
import std.collection.*
import std.time.*
import cjcron.*

/**
 * 定时任务数据模型
 */
public class ScheduledTask {
    public var id: Int64
    public var name: String
    public var cronExpression: String
    public var taskType: String
    public var taskParameters: String
    public var enabled: Bool
    public var priority: Int32
    public var timeoutSeconds: Int32

    public var lastRunAt: String
    public var lastRunStatus: String
    public var lastError: String
    public var nextRunAt: String

    public var runCount: Int32
    public var successCount: Int32
    public var failureCount: Int32

    public var createdAt: String
    public var updatedAt: String
    public var createdBy: String
    public var updatedBy: String

    public init(
        id!: Int64 = 0,
        name!: String = "",
        cronExpression!: String = "",
        taskType!: String = "",
        taskParameters!: String = "",
        enabled!: Bool = true,
        priority!: Int32 = 50,
        timeoutSeconds!: Int32 = 3600,
        lastRunAt!: String = "",
        lastRunStatus!: String = "",
        lastError!: String = "",
        nextRunAt!: String = "",
        runCount!: Int32 = 0,
        successCount!: Int32 = 0,
        failureCount!: Int32 = 0,
        createdAt!: String = "",
        updatedAt!: String = "",
        createdBy!: String = "",
        updatedBy!: String = ""
    ) {
        this.id = id
        this.name = name
        this.cronExpression = cronExpression
        this.taskType = taskType
        this.taskParameters = taskParameters
        this.enabled = enabled
        this.priority = priority
        this.timeoutSeconds = timeoutSeconds
        this.lastRunAt = lastRunAt
        this.lastRunStatus = lastRunStatus
        this.lastError = lastError
        this.nextRunAt = nextRunAt
        this.runCount = runCount
        this.successCount = successCount
        this.failureCount = failureCount
        this.createdAt = createdAt
        this.updatedAt = updatedAt
        this.createdBy = createdBy
        this.updatedBy = updatedBy
    }

    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        var json = "{"
        json += "\"id\":${id},"
        json += "\"name\":\"${escapeJsonString(name)}\","
        json += "\"cronExpression\":\"${escapeJsonString(cronExpression)}\","
        json += "\"taskType\":\"${escapeJsonString(taskType)}\","
        json += "\"taskParameters\":\"${escapeJsonString(taskParameters)}\","
        json += "\"enabled\":${enabled},"
        json += "\"priority\":${priority},"
        json += "\"timeoutSeconds\":${timeoutSeconds},"
        json += "\"lastRunAt\":\"${escapeJsonString(lastRunAt)}\","
        json += "\"lastRunStatus\":\"${escapeJsonString(lastRunStatus)}\","
        json += "\"lastError\":\"${escapeJsonString(lastError)}\","
        json += "\"nextRunAt\":\"${escapeJsonString(nextRunAt)}\","
        json += "\"runCount\":${runCount},"
        json += "\"successCount\":${successCount},"
        json += "\"failureCount\":${failureCount},"
        json += "\"createdAt\":\"${escapeJsonString(createdAt)}\","
        json += "\"updatedAt\":\"${escapeJsonString(updatedAt)}\","
        json += "\"createdBy\":\"${escapeJsonString(createdBy)}\","
        json += "\"updatedBy\":\"${escapeJsonString(updatedBy)}\""
        json += "}"
        return json
    }

    /**
     * 计算下次执行时间
     */
    public func calculateNextRunAt(): Option<DateTime> {
        try {
            let cron = CronExpression.parse(cronExpression)
            return cron.next(DateTime.now())
        } catch (e: Exception) {
            return None
        }
    }

    /**
     * 从ScheduledTaskData转换
     */
    public static func fromData(data: ScheduledTaskData): ScheduledTask {
        return ScheduledTask(
            id: data.id,
            name: data.name,
            cronExpression: data.cronExpression,
            taskType: data.taskType,
            taskParameters: data.taskParameters,
            enabled: data.enabled,
            priority: data.priority,
            timeoutSeconds: data.timeoutSeconds,
            lastRunAt: data.lastRunAt,
            lastRunStatus: data.lastRunStatus,
            lastError: data.lastError,
            nextRunAt: data.nextRunAt,
            runCount: data.runCount,
            successCount: data.successCount,
            failureCount: data.failureCount,
            createdAt: data.createdAt,
            updatedAt: data.updatedAt,
            createdBy: data.createdBy,
            updatedBy: data.updatedBy
        )
    }

    /**
     * 转换为ScheduledTaskData
     */
    public func toData(): ScheduledTaskData {
        let data = ScheduledTaskData()
        data.id = this.id
        data.name = this.name
        data.cronExpression = this.cronExpression
        data.taskType = this.taskType
        data.taskParameters = this.taskParameters
        data.enabled = this.enabled
        data.priority = this.priority
        data.timeoutSeconds = this.timeoutSeconds
        data.lastRunAt = this.lastRunAt
        data.lastRunStatus = this.lastRunStatus
        data.lastError = this.lastError
        data.nextRunAt = this.nextRunAt
        data.runCount = this.runCount
        data.successCount = this.successCount
        data.failureCount = this.failureCount
        data.createdAt = this.createdAt
        data.updatedAt = this.updatedAt
        data.createdBy = this.createdBy
        data.updatedBy = this.updatedBy
        return data
    }
}

/**
 * 定时任务分页结果
 */
public class ScheduledTaskPageResult {
    public var tasks: Array<ScheduledTask>
    public var total: Int32
    public var page: Int32
    public var pageSize: Int32
    public var totalPages: Int32

    public init() {
        this.tasks = Array<ScheduledTask>()
        this.total = 0
        this.page = 1
        this.pageSize = 10
        this.totalPages = 0
    }

    public init(tasks: Array<ScheduledTask>, total: Int32, page: Int32, pageSize: Int32) {
        this.tasks = tasks
        this.total = total
        this.page = page
        this.pageSize = pageSize
        this.totalPages = (total + pageSize - 1) / pageSize
    }

    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        var json = "{"
        json += "\"tasks\":["
        for (i in 0..tasks.size) {
            if (i > 0) { json += "," }
            json += tasks[i].toJson()
        }
        json += "],"
        json += "\"total\":${total},"
        json += "\"page\":${page},"
        json += "\"pageSize\":${pageSize},"
        json += "\"totalPages\":${totalPages}"
        json += "}"
        return json
    }
}

/**
 * 定时任务数据访问层
 */
public class ScheduledTaskModel {
    /**
     * 初始化数据库表
     */
    public static func initialize(): Bool {
        let logger = getLogger("scheduled_task_model")
        logger.info("初始化定时任务数据库表")

        let tableCreated = ScheduledTaskDao.createTable()
        if (!tableCreated) {
            logger.error("创建scheduled_tasks表失败")
            return false
        }

        return true
    }

    /**
     * 根据ID获取定时任务
     */
    public static func getById(id: Int64): Option<ScheduledTask> {
        let data = ScheduledTaskDao.getById(id)
        if (data.id == 0) {
            return None
        }
        return Some(ScheduledTask.fromData(data))
    }

    /**
     * 根据名称获取定时任务
     */
    public static func getByName(name: String): Option<ScheduledTask> {
        let data = ScheduledTaskDao.getByName(name)
        if (data.id == 0) {
            return None
        }
        return Some(ScheduledTask.fromData(data))
    }

    /**
     * 获取所有启用的定时任务
     */
    public static func getEnabledTasks(): Array<ScheduledTask> {
        let dataArray = ScheduledTaskDao.getEnabledTasks()
        return convertDataArrayToTasks(dataArray)
    }

    /**
     * 获取到期的定时任务
     */
    public static func getDueTasks(): Array<ScheduledTask> {
        let dataArray = ScheduledTaskDao.getDueTasks()
        return convertDataArrayToTasks(dataArray)
    }

    /**
     * 分页获取定时任务列表
     */
    public static func getWithPagination(page: Int32, pageSize: Int32): ScheduledTaskPageResult {
        let logger = getLogger("scheduled_task_model")
        logger.debug("分页获取定时任务列表", [("page", page.toString()), ("pageSize", pageSize.toString())])

        let total = ScheduledTaskDao.getCount()
        let offset = (page - 1) * pageSize
        let dataArray = ScheduledTaskDao.getWithPagination(offset, pageSize)
        let tasks = convertDataArrayToTasks(dataArray)

        let result = ScheduledTaskPageResult(tasks, total, page, pageSize)
        logger.debug("分页查询完成", [("total", total.toString()), ("returned", tasks.size.toString())])

        return result
    }

    /**
     * 创建定时任务
     */
    public static func create(task: ScheduledTask): Option<ScheduledTask> {
        let logger = getLogger("scheduled_task_model")

        // 验证cron表达式
        try {
            let _ = CronExpression.parse(task.cronExpression)
        } catch (e: Exception) {
            logger.error("无效的cron表达式", ("expression", task.cronExpression), ("error", e.message))
            return None
        }

        // 计算下次执行时间
        var newTask = task
        match (newTask.calculateNextRunAt()) {
            case Some(nextRun) =>
                newTask.nextRunAt = nextRun.toString()
            case None =>
                logger.warn("无法计算下次执行时间", ("expression", task.cronExpression))
        }

        newTask.createdAt = DateTime.now().toString()
        newTask.updatedAt = newTask.createdAt

        let data = newTask.toData()
        if (ScheduledTaskDao.create(data)) {
            newTask.id = data.id
            return Some(newTask)
        }
        return None
    }

    /**
     * 更新定时任务
     */
    public static func update(task: ScheduledTask): Bool {
        let logger = getLogger("scheduled_task_model")

        // 验证cron表达式
        try {
            let _ = CronExpression.parse(task.cronExpression)
        } catch (e: Exception) {
            logger.error("无效的cron表达式", ("expression", task.cronExpression), ("error", e.message))
            return false
        }

        // 重新计算下次执行时间
        var updatedTask = task
        match (updatedTask.calculateNextRunAt()) {
            case Some(nextRun) =>
                updatedTask.nextRunAt = nextRun.toString()
            case None =>
                logger.warn("无法计算下次执行时间", ("expression", task.cronExpression))
        }

        updatedTask.updatedAt = DateTime.now().toString()

        return ScheduledTaskDao.update(updatedTask.toData())
    }

    /**
     * 删除定时任务
     */
    public static func delete(id: Int64): Bool {
        return ScheduledTaskDao.delete(id)
    }

    /**
     * 根据名称删除定时任务
     */
    public static func deleteByName(name: String): Bool {
        return ScheduledTaskDao.deleteByName(name)
    }

    /**
     * 启用定时任务
     */
    public static func enable(id: Int64): Bool {
        return ScheduledTaskDao.setEnabled(id, true)
    }

    /**
     * 禁用定时任务
     */
    public static func disable(id: Int64): Bool {
        return ScheduledTaskDao.setEnabled(id, false)
    }

    /**
     * 更新任务执行结果
     */
    public static func updateRunResult(id: Int64, success: Bool, errorMessage: String): Bool {
        return ScheduledTaskDao.updateRunResult(id, success, errorMessage)
    }

    /**
     * 更新下次执行时间
     */
    public static func updateNextRunTime(id: Int64): Bool {
        let data = ScheduledTaskDao.getById(id)
        if (data.id == 0) {
            return false
        }
        let task = ScheduledTask.fromData(data)
        match (task.calculateNextRunAt()) {
            case Some(nextRun) =>
                return ScheduledTaskDao.updateNextRunAt(id, nextRun.toString())
            case None =>
                return false
        }
    }

    /**
     * 验证cron表达式
     */
    public static func validateCronExpression(expression: String): (Bool, String, Array<String>) {
        try {
            let cron = CronExpression.parse(expression)
            var nextRuns = ArrayList<String>()
            var current = DateTime.now()

            // 计算接下来5次执行时间
            for (_ in 0..5) {
                match (cron.next(current)) {
                    case Some(next) =>
                        nextRuns.add(next.toString())
                        current = next
                    case None =>
                        break
                }
            }

            let size = nextRuns.size
            var result = Array<String>(size, { _ => "" })
            for (i in 0..size) {
                result[i] = nextRuns[i]
            }

            return (true, "", result)
        } catch (e: Exception) {
            return (false, e.message, Array<String>())
        }
    }

    /**
     * 转换数据数组为任务数组
     */
    private static func convertDataArrayToTasks(dataArray: Array<ScheduledTaskData>): Array<ScheduledTask> {
        let size = dataArray.size
        if (size == 0) {
            return Array<ScheduledTask>()
        }
        var tasks = Array<ScheduledTask>(size, { _ => ScheduledTask() })
        for (i in 0..size) {
            tasks[i] = ScheduledTask.fromData(dataArray[i])
        }
        return tasks
    }
}
