package lrr4cj.services

import std.sync.*
import std.time.*
import stdx.log.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*
import cjcron.*

/**
 * CronService: 定时任务调度服务
 * 负责管理和执行基于cron表达式的定时任务
 * 单实例运行，每秒检查到期任务
 */
public class CronService {
    private static var instance: Option<CronService> = Option<CronService>.None
    private static let instanceMutex: Mutex = Mutex()

    private var isRunning: Bool = false
    private let runningMutex: Mutex = Mutex()

    // 调度循环间隔（毫秒）
    private let checkIntervalMs: Int64 = 1000

    private init() {}

    public static func getInstance(): CronService {
        instanceMutex.lock()
        match (instance) {
            case Some(s) =>
                instanceMutex.unlock()
                return s
            case None =>
                let s = CronService()
                instance = Some(s)
                instanceMutex.unlock()
                return s
        }
    }

    /**
     * 启动调度服务
     */
    public func start(): Bool {
        let logger = getLogger("cron_service")

        runningMutex.lock()
        if (isRunning) {
            runningMutex.unlock()
            logger.info("CronService already running")
            return true
        }
        isRunning = true
        runningMutex.unlock()

        // 初始化数据库表
        if (!ScheduledTaskModel.initialize()) {
            logger.error("Failed to initialize scheduled_tasks table")
            runningMutex.lock()
            isRunning = false
            runningMutex.unlock()
            return false
        }

        // 初始化默认定时任务（如果没有任何定时任务）
        initializeDefaultTasks()

        logger.info("CronService starting")

        // 触发启动任务
        triggerStartupTasks()

        // 启动调度循环
        spawn {
            runScheduleLoop()
        }

        logger.info("CronService started successfully")
        return true
    }

    /**
     * 停止调度服务
     */
    public func stop(): Bool {
        let logger = getLogger("cron_service")

        runningMutex.lock()
        if (!isRunning) {
            runningMutex.unlock()
            return true
        }
        isRunning = false
        runningMutex.unlock()

        logger.info("CronService stopped")
        return true
    }

    /**
     * 检查服务是否运行中
     */
    public func isServiceRunning(): Bool {
        runningMutex.lock()
        let running = isRunning
        runningMutex.unlock()
        return running
    }

    /**
     * 调度循环：每秒检查到期任务
     */
    private func runScheduleLoop(): Unit {
        let logger = getLogger("cron_service")
        logger.info("Schedule loop started")

        while (isServiceRunning()) {
            try {
                checkAndTriggerDueTasks()
            } catch (e: Exception) {
                logger.error("Error in schedule loop", ("error", e.message))
            }

            // 等待下一次检查
            sleep(Duration.millisecond * checkIntervalMs)
        }

        logger.info("Schedule loop stopped")
    }

    /**
     * 检查并触发到期任务
     */
    private func checkAndTriggerDueTasks(): Unit {
        let logger = getLogger("cron_service")
        let dueTasks = ScheduledTaskModel.getDueTasks()

        for (task in dueTasks) {
            if (!isServiceRunning()) {
                break
            }

            logger.info("Triggering scheduled task", ("id", task.id.toString()), ("name", task.name), ("type", task.taskType))

            // 触发任务执行
            let success = triggerTask(task)

            // 更新执行结果
            if (success) {
                ScheduledTaskModel.updateRunResult(task.id, true, "")
            } else {
                ScheduledTaskModel.updateRunResult(task.id, false, "Failed to trigger task")
            }

            // 计算并更新下次执行时间
            ScheduledTaskModel.updateNextRunTime(task.id)
        }
    }

    /**
     * 触发单个定时任务
     */
    private func triggerTask(scheduledTask: ScheduledTask): Bool {
        let logger = getLogger("cron_service")

        // 根据任务类型创建对应的TaskPool任务
        let taskName = scheduledTask.name
        let taskType = scheduledTask.taskType
        let parameters = scheduledTask.taskParameters
        let priority = scheduledTask.priority
        let triggerSource = "cron:${scheduledTask.id}"

        // 创建任务
        let task = TaskModel.createTaskWithOptions(
            taskName,
            taskType,
            parameters,
            priority,
            "",  // groupId
            triggerSource
        )

        if (task.id == 0) {
            logger.error("Failed to create task for scheduled task", ("scheduled_task_id", scheduledTask.id.toString()))
            return false
        }

        // 通知TaskPool有新任务
        TaskPoolService.getInstance().notifyTaskAvailable()

        logger.info("Created task for scheduled task",
            ("task_id", task.id.toString()),
            ("scheduled_task_id", scheduledTask.id.toString()),
            ("type", taskType))

        return true
    }

    /**
     * 手动触发定时任务（立即执行一次）
     */
    public func triggerTaskNow(scheduledTaskId: Int64): Bool {
        let logger = getLogger("cron_service")

        match (ScheduledTaskModel.getById(scheduledTaskId)) {
            case Some(task) =>
                logger.info("Manually triggering scheduled task", ("id", scheduledTaskId.toString()), ("name", task.name))
                let success = triggerTask(task)
                if (success) {
                    ScheduledTaskModel.updateRunResult(scheduledTaskId, true, "")
                }
                return success
            case None =>
                logger.error("Scheduled task not found", ("id", scheduledTaskId.toString()))
                return false
        }
    }

    /**
     * 创建定时任务
     */
    public func createScheduledTask(
        name: String,
        cronExpression: String,
        taskType: String,
        taskParameters!: String = "",
        enabled!: Bool = true,
        priority!: Int32 = 50,
        maxInstances!: Int32 = 1,
        timeoutSeconds!: Int32 = 3600
    ): Option<ScheduledTask> {
        let task = ScheduledTask(
            name: name,
            cronExpression: cronExpression,
            taskType: taskType,
            taskParameters: taskParameters,
            enabled: enabled,
            priority: priority,
            maxInstances: maxInstances,
            timeoutSeconds: timeoutSeconds
        )
        return ScheduledTaskModel.create(task)
    }

    /**
     * 更新定时任务
     */
    public func updateScheduledTask(task: ScheduledTask): Bool {
        return ScheduledTaskModel.update(task)
    }

    /**
     * 删除定时任务
     */
    public func deleteScheduledTask(id: Int64): Bool {
        return ScheduledTaskModel.delete(id)
    }

    /**
     * 启用定时任务
     */
    public func enableScheduledTask(id: Int64): Bool {
        let result = ScheduledTaskModel.enable(id)
        if (result) {
            // 重新计算下次执行时间
            ScheduledTaskModel.updateNextRunTime(id)
        }
        return result
    }

    /**
     * 禁用定时任务
     */
    public func disableScheduledTask(id: Int64): Bool {
        return ScheduledTaskModel.disable(id)
    }

    /**
     * 获取定时任务
     */
    public func getScheduledTask(id: Int64): Option<ScheduledTask> {
        return ScheduledTaskModel.getById(id)
    }

    /**
     * 分页获取定时任务列表
     */
    public func getScheduledTasks(page: Int32, pageSize: Int32): ScheduledTaskPageResult {
        return ScheduledTaskModel.getWithPagination(page, pageSize)
    }

    /**
     * 获取所有启用的定时任务
     */
    public func getEnabledScheduledTasks(): Array<ScheduledTask> {
        return ScheduledTaskModel.getEnabledTasks()
    }

    /**
     * 验证cron表达式
     */
    public func validateCronExpression(expression: String): CronValidationResult {
        let (valid, error, nextRuns) = ScheduledTaskModel.validateCronExpression(expression)
        return CronValidationResult(valid, error, nextRuns)
    }

    /**
     * 获取服务状态
     */
    public func getStatus(): CronServiceStatus {
        let running = isServiceRunning()
        let taskCount = ScheduledTaskDao.getCount()
        let enabledCount = ScheduledTaskModel.getEnabledTasks().size
        return CronServiceStatus(running, taskCount, Int32(enabledCount))
    }

    /**
     * 初始化默认定时任务（迁移用）
     */
    public func initializeDefaultTasks(): Unit {
        let logger = getLogger("cron_service")

        // 检查是否已有定时任务
        if (ScheduledTaskDao.getCount() > 0) {
            logger.info("Scheduled tasks already exist, skipping default task creation")
            return
        }

        logger.info("Creating default scheduled tasks")

        // 定时目录扫描（每6小时）
        let scanTask = createScheduledTask(
            "定时目录扫描",
            "0 */6 * * *",
            "scan_directory",
            taskParameters: "{\"scan_path\":\"\",\"trigger_source\":\"cron\"}",
            enabled: false,  // 默认禁用，用户可手动启用
            priority: 30
        )
        match (scanTask) {
            case Some(t) =>
                logger.info("Created default scan_directory task", ("id", t.id.toString()))
            case None =>
                logger.error("Failed to create default scan_directory task")
        }

        // 定时数据库检查（每天凌晨2点）
        let dbCheckTask = createScheduledTask(
            "定时数据库检查",
            "0 2 * * *",
            "check_database",
            taskParameters: "{}",
            enabled: false,
            priority: 50
        )
        match (dbCheckTask) {
            case Some(t) =>
                logger.info("Created default check_database task", ("id", t.id.toString()))
            case None =>
                logger.error("Failed to create default check_database task")
        }

        // 定时插件扫描（每天凌晨1点）
        let pluginScanTask = createScheduledTask(
            "定时插件扫描",
            "0 1 * * *",
            "scan_plugins",
            taskParameters: "{}",
            enabled: false,
            priority: 50
        )
        match (pluginScanTask) {
            case Some(t) =>
                logger.info("Created default scan_plugins task", ("id", t.id.toString()))
            case None =>
                logger.error("Failed to create default scan_plugins task")
        }

        logger.info("Default scheduled tasks created")
    }

    /**
     * 触发启动任务（每次启动都执行）
     */
    private func triggerStartupTasks(): Unit {
        let logger = getLogger("cron_service")

        // 在创建启动任务之前，先清理孤儿任务
        logger.info("Cleaning up orphaned tasks before creating startup tasks")
        let recoveredCount = TaskDao.recoverOrphanedTasks()
        if (recoveredCount > 0) {
            logger.info("Recovered orphaned tasks", ("count", recoveredCount.toString()))
        }

        // 触发插件扫描任务（总是在启动时执行）
        let pluginTaskId = triggerPluginScan(priority: 50, triggerSource: "startup")
        logger.info("Triggered startup scan_plugins task", ("task_id", pluginTaskId.toString()))

        // 检查是否启用初始扫描
        let enableInitialScan = SystemSettingsService.getBoolean("ENABLE_INITIAL_SCAN")
        if (enableInitialScan) {
            logger.info("ENABLE_INITIAL_SCAN is enabled, triggering directory scan")
            let scanPath = SystemSettingsService.getPath("ARCHIVE_PATH")
            let dirExists = DirectoryScanner.directoryExists(scanPath)
            if (dirExists) {
                let scanTaskId = triggerDirectoryScan(scanPath: scanPath, priority: 30, triggerSource: "startup")
                logger.info("Triggered startup scan_directory task", ("task_id", scanTaskId.toString()), ("path", scanPath))
            } else {
                logger.warn("Archive directory does not exist, skipping initial scan", ("path", scanPath))
            }
        } else {
            logger.info("ENABLE_INITIAL_SCAN is disabled, skipping initial directory scan")
        }

        // 检查是否启用初始数据库检查
        let enableInitialDbCheck = SystemSettingsService.getBoolean("ENABLE_INITIAL_DB_CHECK")
        if (enableInitialDbCheck) {
            logger.info("ENABLE_INITIAL_DB_CHECK is enabled, triggering database check")
            let dbCheckTaskId = triggerDatabaseCheck(priority: 50, triggerSource: "startup")
            logger.info("Triggered startup check_database task", ("task_id", dbCheckTaskId.toString()))
        } else {
            logger.info("ENABLE_INITIAL_DB_CHECK is disabled, skipping initial database check")
        }
    }

    /**
     * 触发目录扫描任务
     */
    public func triggerDirectoryScan(scanPath!: String = "", priority!: Int32 = 30, triggerSource!: String = "manual"): Int64 {
        let targetPath = if (scanPath.size > 0) { scanPath } else { SystemSettingsService.getPath("ARCHIVE_PATH") }
        let source = if (triggerSource.size > 0) { triggerSource } else { "manual" }
        let params =
            "{\"scan_path\":\"${escapeJson(targetPath)}\",\"trigger_source\":\"${escapeJson(source)}\",\"child_priority\":${priority}}"
        let task = TaskModel.createTaskWithOptions("目录扫描", "scan_directory", params, priority, "", source)
        TaskPoolService.getInstance().notifyTaskAvailable()
        return task.id
    }

    /**
     * 触发数据库一致性检查任务
     */
    public func triggerDatabaseCheck(priority!: Int32 = 50, triggerSource!: String = "manual"): Int64 {
        let source = if (triggerSource.size > 0) { triggerSource } else { "manual" }
        let params = "{}"
        let task = TaskModel.createTaskWithOptions("数据库检查", "check_database", params, priority, "", source)
        TaskPoolService.getInstance().notifyTaskAvailable()
        let logger = getLogger("cron_service")
        logger.info("Enqueued check_database task", ("task_id", task.id.toString()))
        return task.id
    }

    /**
     * 触发插件扫描任务
     */
    public func triggerPluginScan(priority!: Int32 = 50, triggerSource!: String = "manual"): Int64 {
        let source = if (triggerSource.size > 0) { triggerSource } else { "manual" }
        let params = "{}"
        let task = TaskModel.createTaskWithOptions("插件扫描", "scan_plugins", params, priority, "", source)
        TaskPoolService.getInstance().notifyTaskAvailable()
        let logger = getLogger("cron_service")
        logger.info("Enqueued scan_plugins task", ("task_id", task.id.toString()))
        return task.id
    }

    /**
     * 触发压缩包文件扫描任务（API入口）
     */
    public func scanArchives(): ScanResultData {
        let logger = getLogger("cron_service")
        let scanPath = SystemSettingsService.getPath("ARCHIVE_PATH")
        let dirExists = DirectoryScanner.directoryExists(scanPath)
        if (!dirExists) {
            logger.error("Archive directory does not exist", ("path", scanPath))
            return ScanResultData(0, 0, 1, ["Archive directory does not exist: ${scanPath}"])
        }

        let taskId = triggerDirectoryScan(scanPath: scanPath, priority: 30, triggerSource: "manual")
        logger.info("Enqueued scan_directory task", ("task_id", taskId.toString()), ("path", scanPath))
        return ScanResultData(0, 0, 0, Array<String>(), taskId: taskId)
    }

    private func escapeJson(value: String): String {
        var escaped = value
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

/**
 * Cron表达式验证结果
 */
public class CronValidationResult {
    public var valid: Bool
    public var error: String
    public var nextRuns: Array<String>

    public init(valid: Bool, error: String, nextRuns: Array<String>) {
        this.valid = valid
        this.error = error
        this.nextRuns = nextRuns
    }

    public func toJson(): String {
        var json = "{"
        json += "\"valid\":${valid},"
        json += "\"error\":\"${escapeJsonString(error)}\","
        json += "\"nextRuns\":["
        for (i in 0..nextRuns.size) {
            if (i > 0) { json += "," }
            json += "\"${escapeJsonString(nextRuns[i])}\""
        }
        json += "]}"
        return json
    }

    private func escapeJsonString(str: String): String {
        var escaped = str
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }
}

/**
 * CronService状态
 */
public class CronServiceStatus {
    public var running: Bool
    public var totalTasks: Int32
    public var enabledTasks: Int32

    public init(running: Bool, totalTasks: Int32, enabledTasks: Int32) {
        this.running = running
        this.totalTasks = totalTasks
        this.enabledTasks = enabledTasks
    }

    public func toJson(): String {
        return "{\"running\":${running},\"totalTasks\":${totalTasks},\"enabledTasks\":${enabledTasks}}"
    }
}
