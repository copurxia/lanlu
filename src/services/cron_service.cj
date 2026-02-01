package lanlu.services

import std.sync.*
import std.time.*
import std.collection.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*

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

    // 调度循环基础间隔（毫秒）
    private let baseCheckIntervalMs: Int64 = 1000

    // 任务缓存机制 - 减少数据库查询频率
    private var taskCache: Array<ScheduledTask> = Array<ScheduledTask>()
    private let cacheMutex: Mutex = Mutex()
    private var cacheLastRefreshTime: String = ""
    // 缓存刷新间隔（5分钟）
    private let cacheRefreshIntervalMs: Int64 = 300000
    // 最近任务执行时间（用于动态调整等待间隔）
    private var nearestTaskRunAt: String = ""

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
            logger.debug("CronService already running")
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

        logger.debug("CronService starting")

        // 触发启动任务
        triggerStartupTasks()

        // 启动调度循环
        spawn {
            runScheduleLoop()
        }

        logger.debug("CronService started successfully")
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

        logger.debug("CronService stopped")
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
     * 调度循环：使用动态间隔检查到期任务，减少数据库查询
     */
    private func runScheduleLoop(): Unit {
        let logger = getLogger("cron_service")
        logger.debug("Schedule loop started with dynamic interval optimization")

        // 初始加载任务缓存
        refreshTaskCache()

        while (isServiceRunning()) {
            try {
                // 计算动态等待间隔
                let waitTime = calculateNextWaitTime()
                
                if (waitTime > 0) {
                    // 等待直到下一个任务到期或达到最小检查间隔
                    sleep(Duration.millisecond * waitTime)
                }

                // 检查缓存是否需要刷新
                if (shouldRefreshCache()) {
                    refreshTaskCache()
                }

                // 检查并触发到期的任务
                checkAndTriggerDueTasksFromCache()
            } catch (e: Exception) {
                logger.error("Error in schedule loop", ("error", e.message))
            }
        }

        logger.debug("Schedule loop stopped")
    }

    /**
     * 刷新任务缓存
     */
    private func refreshTaskCache(): Unit {
        cacheMutex.lock()
        try {
            taskCache = ScheduledTaskModel.getEnabledTasks()
            cacheLastRefreshTime = DateTime.now().toString()
            
            // 计算最近任务执行时间
            nearestTaskRunAt = calculateNearestTaskRunAt()
            
            let logger = getLogger("cron_service")
            logger.debug("Task cache refreshed", ("task_count", taskCache.size.toString()))
        } finally {
            cacheMutex.unlock()
        }
    }

    /**
     * 计算最近的任务执行时间（使用 DateTime 精确计算）
     */
    private func calculateNearestTaskRunAt(): String {
        let now = DateTime.now()
        var nearest: String = ""

        for (task in taskCache) {
            if (task.nextRunAt.size > 0) {
                // 尝试解析任务时间，如果解析失败则跳过
                match (DateTime.tryParse(task.nextRunAt)) {
                    case Some(taskTime) =>
                        // 如果任务时间在当前时间之后，且比当前最近时间更近，则更新
                        if (taskTime > now) {
                            if (nearest.size == 0) {
                                nearest = task.nextRunAt
                            } else {
                                match (DateTime.tryParse(nearest)) {
                                    case Some(nearestTime) =>
                                        if (taskTime < nearestTime) {
                                            nearest = task.nextRunAt
                                        }
                                    case None => ()
                                }
                            }
                        }
                    case None =>
                        // 时间解析失败，跳过该任务
                        ()
                }
            }
        }
        return nearest
    }

    /**
     * 计算下一次等待时间（使用 DateTime 精确计算）
     */
    private func calculateNextWaitTime(): Int64 {
        let now = DateTime.now()

        cacheMutex.lock()
        try {
            // 如果没有任务，等待较长时间
            if (nearestTaskRunAt.size == 0) {
                return cacheRefreshIntervalMs / 2  // 等待2.5分钟
            }

            // 解析最近任务时间
            match (DateTime.tryParse(nearestTaskRunAt)) {
                case Some(taskTime) =>
                    // 如果最近任务已到期，立即检查
                    if (taskTime <= now) {
                        return baseCheckIntervalMs  // 1秒
                    }

                    // 计算到任务执行的时间差
                    let timeDiff = taskTime - now
                    // 转换为毫秒
                    let waitMillis = timeDiff.toMilliseconds()

                    // 根据时间差动态调整等待间隔
                    let minWait: Int64 = baseCheckIntervalMs  // 最少1秒
                    let maxWait: Int64 = 60000  // 最多等1分钟

                    // 如果任务很快就要执行（< 30秒），使用短间隔
                    // 否则根据实际时间差计算，但不超过maxWait
                    if (waitMillis <= 30000) {
                        return minWait
                    } else {
                        // 返回较小值，确保及时检查但不超过最大间隔
                        return min(minWait, maxWait, Array<Int64>())
                    }
                case None =>
                    // 时间解析失败，返回默认间隔
                    return baseCheckIntervalMs
            }
        } finally {
            cacheMutex.unlock()
        }
    }

    /**
     * 检查是否需要刷新缓存（使用 DateTime 精确计算）
     */
    private func shouldRefreshCache(): Bool {
        // 如果缓存时间为空，需要刷新
        if (cacheLastRefreshTime.size == 0) {
            return true
        }

        // 解析缓存刷新时间
        match (DateTime.tryParse(cacheLastRefreshTime)) {
            case Some(lastRefresh) =>
                // 计算当前时间与上次刷新时间的时间差
                let now = DateTime.now()
                let timeDiff = now - lastRefresh
                let diffMillis = timeDiff.toMilliseconds()

                // 如果超过缓存刷新间隔，需要刷新
                return diffMillis >= cacheRefreshIntervalMs
            case None =>
                // 时间解析失败，需要刷新
                return true
        }
    }

    /**
     * 从缓存检查并触发到期任务（使用 DateTime 精确计算）
     */
    private func checkAndTriggerDueTasksFromCache(): Unit {
        let logger = getLogger("cron_service")
        let now = DateTime.now()

        cacheMutex.lock()
        let tasksToTrigger = ArrayList<ScheduledTask>()

        try {
            // 找出所有到期的任务
            for (task in taskCache) {
                if (task.nextRunAt.size > 0) {
                    // 使用 DateTime 精确比较任务时间
                    match (DateTime.tryParse(task.nextRunAt)) {
                        case Some(taskTime) =>
                            if (taskTime <= now) {
                                tasksToTrigger.add(task)
                            }
                        case None =>
                            // 时间解析失败，跳过该任务
                            logger.debug("Failed to parse task time", ("task_id", task.id.toString()), ("time", task.nextRunAt))
                    }
                }
            }
        } finally {
            cacheMutex.unlock()
        }

        // 在缓存锁外执行实际触发逻辑
        for (i in 0..tasksToTrigger.size) {
            let task = tasksToTrigger[i]
            if (!isServiceRunning()) {
                break
            }

            logger.debug("Triggering scheduled task from cache", ("id", task.id.toString()), ("name", task.name), ("type", task.taskType))

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

            // 更新缓存中的下次执行时间
            updateTaskInCache(task.id)
        }

        // 更新最近任务时间
        cacheMutex.lock()
        try {
            nearestTaskRunAt = calculateNearestTaskRunAt()
        } finally {
            cacheMutex.unlock()
        }
    }

    /**
     * 更新缓存中的任务信息
     */
    private func updateTaskInCache(taskId: Int64): Unit {
        let logger = getLogger("cron_service")
        cacheMutex.lock()
        try {
            for (i in 0..taskCache.size) {
                if (taskCache[i].id == taskId) {
                    match (ScheduledTaskModel.getById(taskId)) {
                        case Some(updatedTask) =>
                            taskCache[i] = updatedTask
                        case None =>
                            // 任务可能已被删除，从缓存中移除该任务
                            // 由于Array没有remove方法，标记缓存需要刷新
                            logger.debug("Task deleted, cache will be refreshed")
                    }
                    break
                }
            }
        } finally {
            cacheMutex.unlock()
        }
    }

    /**
     * 使缓存失效（任务变更时调用）
     */
    private func invalidateCache(): Unit {
        cacheMutex.lock()
        try {
            taskCache = Array<ScheduledTask>()
            cacheLastRefreshTime = ""
            nearestTaskRunAt = ""
        } finally {
            cacheMutex.unlock()
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

        logger.debug("Created task for scheduled task",
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
                logger.debug("Manually triggering scheduled task", ("id", scheduledTaskId.toString()), ("name", task.name))
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
        timeoutSeconds!: Int32 = 3600
    ): Option<ScheduledTask> {
        let task = ScheduledTask(
            name: name,
            cronExpression: cronExpression,
            taskType: taskType,
            taskParameters: taskParameters,
            enabled: enabled,
            priority: priority,
            timeoutSeconds: timeoutSeconds
        )
        let result = ScheduledTaskModel.create(task)

        // 创建任务后刷新缓存
        match (result) {
            case Some(_) => invalidateCache()
            case None => ()
        }

        return result
    }

    /**
     * 更新定时任务
     */
    public func updateScheduledTask(task: ScheduledTask): Bool {
        let result = ScheduledTaskModel.update(task)

        // 更新任务后刷新缓存
        if (result) {
            invalidateCache()
        }

        return result
    }

    /**
     * 删除定时任务
     */
    public func deleteScheduledTask(id: Int64): Bool {
        let result = ScheduledTaskModel.delete(id)

        // 删除任务后刷新缓存
        if (result) {
            invalidateCache()
        }

        return result
    }

    /**
     * 启用定时任务
     */
    public func enableScheduledTask(id: Int64): Bool {
        let result = ScheduledTaskModel.enable(id)
        if (result) {
            // 重新计算下次执行时间
            ScheduledTaskModel.updateNextRunTime(id)

            // 启用任务后刷新缓存
            invalidateCache()
        }
        return result
    }

    /**
     * 禁用定时任务
     */
    public func disableScheduledTask(id: Int64): Bool {
        let result = ScheduledTaskModel.disable(id)

        // 禁用任务后刷新缓存
        if (result) {
            invalidateCache()
        }

        return result
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

        logger.debug("Ensuring default scheduled tasks")

        // Create only if missing (by name). Never overwrite user-modified tasks.
        let ensure = { name: String, cron: String, taskType: String, params: String, enabled: Bool, priority: Int32 =>
            match (ScheduledTaskModel.getByName(name)) {
                case Some(_) => ()
                case None =>
                    let created = createScheduledTask(
                        name,
                        cron,
                        taskType,
                        taskParameters: params,
                        enabled: enabled,
                        priority: priority
                    )
                    match (created) {
                        case Some(t) => logger.debug("Created default ${taskType} task", ("id", t.id.toString()))
                        case None => logger.error("Failed to create default ${taskType} task", ("name", name))
                    }
            }
        }

        // 定时扫描所有分类（每6小时）- 已禁用，改用分类系统手动触发扫描
        ensure(
            "定时扫描所有分类",
            "0 */6 * * *",
            "scan_all_categories",
            "{}",  // 扫描所有启用分类
            false,  // 默认禁用，用户应通过分类管理界面触发扫描
            30
        )

        // 定时生成分类封面（每天凌晨0:30）- 默认禁用，按需在任务管理里启用
        // 参数为空/{} 表示对所有启用分类生成封面。
        ensure(
            "定时生成分类封面",
            "30 0 * * *",
            "generate_category_cover",
            "{}",
            false,
            40
        )

        // 定时数据库检查（每天凌晨2点）
        ensure(
            "定时数据库检查",
            "0 2 * * *",
            "check_database",
            "",  // 不需要参数
            false,
            50
        )

        // 定时插件扫描（每天凌晨1点）
        ensure(
            "定时插件扫描",
            "0 1 * * *",
            "scan_plugins",
            "",  // 不需要参数
            false,
            50
        )

        // 定时清理缓存（每天凌晨3点）
        ensure(
            "定时清理缓存",
            "0 3 * * *",
            "clear_cache",
            "{\"maxAgeDays\":7}",  // 清理7天前的缓存
            true,  // 默认启用，缓存清理是安全的维护操作
            40
        )

        // 定时清理日志（每天凌晨4点）
        ensure(
            "定时清理日志",
            "0 4 * * *",
            "clear_log",
            "{\"maxAgeDays\":7}",  // 清理7天前的任务日志
            true,  // 默认启用，日志清理是安全的维护操作
            40
        )

        // 批量重生成封面（默认禁用，属于维护/重建操作）
        ensure(
            "重生成封面",
            "0 5 * * *",
            "regenerate_cover",
            "{\"mode\":\"all\",\"deleteOldCover\":true,\"batchSize\":200}",  // 点击执行=全量重建，使用 batchSize 分页派发
            false,
            50
        )

        // 批量补全元数据（默认禁用，可能触发大量插件调用）
        ensure(
            "补全元数据",
            "30 5 * * *",
            "backfill_metadata",
            "{\"batchSize\":200}",  // 点击执行=全量扫描（按 batchSize 分页），对每个档案跑分类勾选的所有 plugins
            false,
            50
        )

        logger.debug("Default scheduled tasks ensured")
    }

    /**
     * 触发启动任务（每次启动都执行）
     */
    private func triggerStartupTasks(): Unit {
        let logger = getLogger("cron_service")

        // 在创建启动任务之前，先清理孤儿任务
        logger.debug("Cleaning up orphaned tasks before creating startup tasks")
        let recoveredCount = TaskDao.recoverOrphanedTasks()
        if (recoveredCount > 0) {
            logger.debug("Recovered orphaned tasks", ("count", recoveredCount.toString()))
        }

        // 检查是否启用初始插件扫描
        let enableInitialPluginScan = SystemSettingsService.getBoolean("ENABLE_INITIAL_PLUGIN_SCAN")
        if (enableInitialPluginScan) {
            logger.debug("ENABLE_INITIAL_PLUGIN_SCAN is enabled, triggering plugin scan")
            let pluginTaskId = triggerPluginScan(priority: 50, triggerSource: "startup")
            logger.debug("Triggered startup scan_plugins task", ("task_id", pluginTaskId.toString()))
        } else {
            logger.debug("ENABLE_INITIAL_PLUGIN_SCAN is disabled, skipping initial plugin scan")
        }

        // 检查是否启用初始扫描（改用分类系统）
        let enableInitialScan = SystemSettingsService.getBoolean("ENABLE_INITIAL_SCAN")
        if (enableInitialScan) {
            logger.debug("ENABLE_INITIAL_SCAN is enabled, triggering scan_all_categories task")
            let params = "{}"
            let task = TaskModel.createTaskWithOptions("启动时扫描所有分类", "scan_all_categories", params, 30, "", "startup")
            TaskPoolService.getInstance().notifyTaskAvailable()
            logger.debug("Triggered startup scan_all_categories task", ("task_id", task.id.toString()))
        } else {
            logger.debug("ENABLE_INITIAL_SCAN is disabled, skipping initial directory scan")
        }

        // 检查是否启用初始数据库检查
        let enableInitialDbCheck = SystemSettingsService.getBoolean("ENABLE_INITIAL_DB_CHECK")
        if (enableInitialDbCheck) {
            logger.debug("ENABLE_INITIAL_DB_CHECK is enabled, triggering database check")
            let dbCheckTaskId = triggerDatabaseCheck(priority: 50, triggerSource: "startup")
            logger.debug("Triggered startup check_database task", ("task_id", dbCheckTaskId.toString()))
        } else {
            logger.debug("ENABLE_INITIAL_DB_CHECK is disabled, skipping initial database check")
        }
    }

    /**
     * 触发分类扫描任务
     */
    public func triggerCategoryScan(catid: String, _: String, priority: Int32, triggerSource: String): Int64 {
        let source = if (triggerSource.size > 0) { triggerSource } else { "manual" }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("category_id").writeValue(catid)
        w.endObject()
        w.flush()
        let params = String.fromUtf8(readToEnd(out))
        let task = TaskModel.createTaskWithOptions("分类扫描", "scan_single_category", params, priority, "category_scan:${catid}", source)
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
        logger.debug("Enqueued check_database task", ("task_id", task.id.toString()))
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
        logger.debug("Enqueued scan_plugins task", ("task_id", task.id.toString()))
        return task.id
    }

    /**
     * 触发缓存清理任务
     */
    public func triggerClearCache(priority!: Int32 = 40, triggerSource!: String = "manual", maxAgeDays!: Int64 = 7): Int64 {
        let source = if (triggerSource.size > 0) { triggerSource } else { "manual" }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("maxAgeDays").writeValue(maxAgeDays)
        w.endObject()
        w.flush()
        let params = String.fromUtf8(readToEnd(out))
        let task = TaskModel.createTaskWithOptions("清理缓存", "clear_cache", params, priority, "", source)
        TaskPoolService.getInstance().notifyTaskAvailable()
        let logger = getLogger("cron_service")
        logger.debug("Enqueued clear_cache task", ("task_id", task.id.toString()), ("maxAgeDays", maxAgeDays.toString()))
        return task.id
    }

    /**
     * 触发日志清理任务
     */
    public func triggerClearLog(priority!: Int32 = 40, triggerSource!: String = "manual", maxAgeDays!: Int64 = 7): Int64 {
        let source = if (triggerSource.size > 0) { triggerSource } else { "manual" }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("maxAgeDays").writeValue(maxAgeDays)
        w.endObject()
        w.flush()
        let params = String.fromUtf8(readToEnd(out))
        let task = TaskModel.createTaskWithOptions("清理日志", "clear_log", params, priority, "", source)
        TaskPoolService.getInstance().notifyTaskAvailable()
        let logger = getLogger("cron_service")
        logger.debug("Enqueued clear_log task", ("task_id", task.id.toString()), ("maxAgeDays", maxAgeDays.toString()))
        return task.id
    }

    /**
     * 触发所有分类的扫描任务（API入口）
     */
    public func scanArchives(): ScanResultData {
        let logger = getLogger("cron_service")
        let source = "manual"
        let params = "{}"
        let task = TaskModel.createTaskWithOptions("扫描所有分类", "scan_all_categories", params, 30, "", source)
        TaskPoolService.getInstance().notifyTaskAvailable()
        logger.debug("Enqueued scan_all_categories task", ("task_id", task.id.toString()))
        return ScanResultData(0, 0, 0, [], taskId: task.id)
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
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("valid").writeValue(valid)
        w.writeName("error").writeValue(error)
        w.writeName("nextRuns")
        w.startArray()
        for (s in nextRuns) {
            w.writeValue(s)
        }
        w.endArray()
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
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
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("running").writeValue(running)
        w.writeName("totalTasks").writeValue(totalTasks)
        w.writeName("enabledTasks").writeValue(enabledTasks)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }
}
