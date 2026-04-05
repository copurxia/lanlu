package lanlu.contexts.task.application

import std.collection.*
import std.sync.*
import std.convert.*
import std.time.*
import stdx.log.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.infrastructure.kv.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.system.application.*
import lanlu.shared.utils.*
import lanlu.contexts.task.application.runners.*
import lanlu.contexts.plugin.application.PluginTaskService

/**
 * TaskPool：用worker线程从DB领取pending任务并执行
 */
public class TaskPoolService {
    private static var instance: Option<TaskPoolService> = Option<TaskPoolService>.None
    private static let instanceMutex: Mutex = Mutex()

    // Keep in sync with `executeTask()` match arms.
    public static func getSupportedTaskTypes(): Array<String> {
        return [
            "upload",
            "asset_upload",
            "download_url",
            "upload_process",
            "asset_upload_process",
            "archive_asset_consume",
            "tag_asset_consume",
            "avatar_asset_consume",
            "metadata_asset_consume",
            "plugin_asset_consume",
            "metadata_plugin",
            "download_url_callback",
            "tag_import",
            "scan_all_categories",
            "scan_single_category",
            "scan_archive",
            "generate_thumbnail",
            "generate_category_cover",
            "check_database",
            "scan_plugins",
            "wasm_task",
            "metadata_plugin_callback",
            "clear_cache",
            "clear_log",
            "regenerate_cover",
            "backfill_metadata",
            "page_metadata"
        ]
    }

    private var isRunning: Bool = false
    private let runningMutex: Mutex = Mutex()

    // 并发 worker 上限
    private var maxWorkers: Int32 = 2
    // 使用原子操作管理 worker 计数，减少锁竞争
    private let currentWorkers: AtomicInt32 = AtomicInt32(0)
    private let workerSeq: AtomicInt32 = AtomicInt32(0)
    private let dispatchMutex: Mutex = Mutex()
    private var dispatchRunning: Bool = false
    private var dispatchRequested: Bool = false
    private let activeWorkersMutex: Mutex = Mutex()
    private var activeWorkers: HashMap<Int64, Int32> = HashMap<Int64, Int32>()
    private let orphanReconcileMutex: Mutex = Mutex()
    private var lastOrphanReconcileAtMs: Int64 = 0
    // upload task 空闲超时时间：10分钟内无分片上报则失败
    private static let UPLOAD_IDLE_TIMEOUT_SECONDS: Int32 = 600
    private static let UPLOAD_WAIT_HEARTBEAT_MILLIS: Int64 = 15000
    private static let ORPHAN_RECONCILE_INTERVAL_MILLIS: Int64 = 60000
    private static let ORPHAN_MIN_RUNNING_AGE_MILLIS: Int64 = 120000

    private init() {
        loadMaxWorkersConfig()
    }

    private func loadMaxWorkersConfig(): Unit {
        // 从数据库读取最大并发任务数设置
        let workersInt = SystemSettingsService.getInt("MAX_CONCURRENT_JOBS")
        maxWorkers = if (workersInt > 0) {
            workersInt
        } else {
            2  // 默认值
        }
        if (maxWorkers < 1) {
            maxWorkers = 1
        }
    }

    public static func getInstance(): TaskPoolService {
        instanceMutex.lock()
        match (instance) {
            case Some(s) =>
                instanceMutex.unlock()
                return s
            case None =>
                let s = TaskPoolService()
                instance = Some(s)
                instanceMutex.unlock()
                return s
        }
    }

    public func start(): Bool {
        runningMutex.lock()
        if (isRunning) {
            runningMutex.unlock()
            return true
        }
        isRunning = true
        runningMutex.unlock()

        let logger = getLogger("taskpool")
        logger.debug("TaskPool starting", ("max_workers", maxWorkers.toString()))

        // 注意：孤儿任务清理现在由 CronService 在创建启动任务之前处理
        // 这里不需要重复清理，避免时序问题

        // 启动时仅尝试领取已有 pending（不做轮询）
        // 后续的调度由事件驱动：任务入队时 notify，Worker 完成时 dispatch
        requestDispatch()
        return true
    }

    private func isServiceRunning(): Bool {
        runningMutex.lock()
        let running = isRunning
        runningMutex.unlock()
        return running
    }

    /**
     * 有新任务入队时调用：尽可能填满并发 worker
     */
    public func notifyTaskAvailable(): Unit {
        requestDispatch()
    }

    /**
     * Safety tick: 由 CronService 周期性调用，检查是否有遗漏的 pending 任务
     * 这是事件驱动的兜底机制，防止 notify 失效时任务卡住
     */
    public func safetyTick(): Unit {
        requestDispatch()
    }

    /**
     * 清理超时的上传任务：由 CronService 周期性调用
     */
    public static func cleanupTimedOutUploads(): Int64 {
        return TaskDao.failTimedOutUploadTasks()
    }

    /**
     * 重新加载最大并发任务数配置
     * 在系统设置更新后调用此方法以应用新配置
     */
    public func reloadMaxWorkersConfig(): Unit {
        let logger = getLogger("taskpool")
        let oldMaxWorkers = maxWorkers
        loadMaxWorkersConfig()
        logger.debug(
            "TaskPool config reloaded",
            ("old_max_workers", oldMaxWorkers.toString()),
            ("new_max_workers", maxWorkers.toString())
        )
    }

    /**
     * 调度：批量领取 pending 任务并 spawn worker 执行
     * 使用原子操作实现无锁调度，一次 DB 查询领取多个任务
     */
    public func requestDispatch(): Unit {
        if (!isServiceRunning()) {
            return
        }

        dispatchMutex.lock()
        dispatchRequested = true
        if (dispatchRunning) {
            dispatchMutex.unlock()
            return
        }
        dispatchRunning = true
        dispatchMutex.unlock()

        dispatchLoop()
    }

    private func dispatchLoop(): Unit {
        let logger = getLogger("taskpool")
        if (!isServiceRunning()) {
            dispatchMutex.lock()
            dispatchRunning = false
            dispatchRequested = false
            dispatchMutex.unlock()
            return
        }

        while (true) {
            dispatchMutex.lock()
            let shouldDrain = dispatchRequested
            dispatchRequested = false
            dispatchMutex.unlock()

            if (!shouldDrain) {
                dispatchMutex.lock()
                dispatchRunning = false
                dispatchMutex.unlock()
                return
            }

            while (isServiceRunning()) {
                reconcileOrphanedRunningTasks()
                let current = currentWorkers.load()
                let available = maxWorkers - current
                if (available <= 0) {
                    break
                }

                let tasks = TaskDao.claimPendingTasks(available)
                if (tasks.size == 0) {
                    break
                }

                logger.debug(
                    "TaskPool dispatch claimed tasks",
                    ("current_workers", current.toString()),
                    ("available_slots", available.toString()),
                    ("claimed_count", tasks.size.toString())
                )

                for (task in tasks) {
                    if (isTaskActivelyTracked(task.id)) {
                        // 防御性检查：任务已在 activeWorkers 中，说明出现了 double-claim。
                        // DB 状态已被 claimPendingTasks 改为 running，原 worker 仍在运行，
                        // 直接跳过本次 spawn，不增加 currentWorkers 计数。
                        logger.error(
                            "double-claim detected: task already has an active worker, skip re-dispatch",
                            ("task_id", task.id.toString()),
                            ("task_type", task.taskType)
                        )
                        continue
                    }
                    currentWorkers.fetchAdd(1)
                    let workerId = workerSeq.fetchAdd(1)
                    let taskData = task
                    let id = workerId
                    registerActiveWorker(taskData.id, id)
                    spawn {
                        runWorker(taskData, id)
                    }
                }
            }
        }
    }

    private func runWorker(task: TaskData, workerId: Int32): Unit {
        let logger = getLogger("taskpool")
        let groupId = task.groupId.trimAscii()
        let kvStore = TaskKVService.getStore()
        if (groupId.size > 0) {
            kvStore.acquireGroup(groupId)
        }
        logger.debug("TaskPool worker executing", ("worker", workerId.toString()), ("task_id", task.id.toString()), ("task_type", task.taskType))
        try {
            try {
                executeTask(task, workerId)
            } catch (e: Exception) {
                // Safety net: never leave the task stuck in "running" due to an unhandled exception.
            TaskIO.appendLog(task.id, "ERROR: task runner crashed: ${e.message}")
                TaskModel.failTask(task.id, "Task runner crashed: ${e.message}")
            }

            // 只有任务进入终态时，才触发依赖任务。
            // upload 任务会在此 worker 内等待到 completed/failed/stopped，避免过早释放并发槽位。
            let latestTask = TaskDao.getTaskDataById(task.id)
            if (isTerminalStatus(latestTask.status)) {
                let completedTaskId = task.id
                spawn { triggerDependentTasks(completedTaskId) }
            } else {
                logger.debug(
                    "Skip triggering dependents because task is not terminal",
                    ("task_id", task.id.toString()),
                    ("status", latestTask.status),
                    ("task_type", latestTask.taskType)
                )
            }
        } finally {
            unregisterActiveWorker(task.id)
            if (groupId.size > 0) {
                kvStore.releaseGroup(groupId)
            }

            // 若任务已 handoff 到不同类型但因 double-claim 被调度器抢先置为 running，
            // worker 退出时将其重置回 pending，确保 requestDispatch() 能正常领取执行。
            let handoffTask = TaskDao.getTaskDataById(task.id)
            if (handoffTask.status == "running" && handoffTask.taskType != task.taskType) {
                let _ = TaskDao.resetHandoffedTask(task.id, task.taskType)
            }

            // 释放 slot 并尝试领取下一个 pending（使用原子操作）
            currentWorkers.fetchSub(1)

            requestDispatch()
        }
    }

    private func registerActiveWorker(taskId: Int64, workerId: Int32): Unit {
        if (taskId <= 0) {
            return
        }
        activeWorkersMutex.lock()
        activeWorkers[taskId] = workerId
        activeWorkersMutex.unlock()
    }

    private func unregisterActiveWorker(taskId: Int64): Unit {
        if (taskId <= 0) {
            return
        }
        activeWorkersMutex.lock()
        let _ = activeWorkers.remove(taskId)
        activeWorkersMutex.unlock()
    }

    private func isTaskActivelyTracked(taskId: Int64): Bool {
        if (taskId <= 0) {
            return false
        }
        activeWorkersMutex.lock()
        let exists = activeWorkers.contains(taskId)
        activeWorkersMutex.unlock()
        return exists
    }

    private func reconcileOrphanedRunningTasks(): Unit {
        let logger = getLogger("taskpool")
        if (!shouldRunOrphanReconcile()) {
            return
        }
        let runningTasks = TaskDao.getTasksWithPaginationByStatus(0, 512, "running")
        let now = DateTime.now()
        for (task in runningTasks) {
            if (task.id <= 0 || isTaskActivelyTracked(task.id)) {
                continue
            }
            if (!isTaskOldEnoughForOrphanCheck(task, now)) {
                continue
            }
            if (TaskIO.readOutput(task.id, maxBytes: 256).trimAscii().size > 0) {
                logger.warn(
                    "Skip orphan recovery because task already has output",
                    ("task_id", task.id.toString()),
                    ("task_type", task.taskType),
                    ("phase", task.phase)
                )
                continue
            }

            let latestTask = TaskDao.getTaskDataById(task.id)
            if (latestTask.id == 0 || latestTask.status != "running" || isTaskActivelyTracked(latestTask.id)) {
                continue
            }
            if (!isTaskOldEnoughForOrphanCheck(latestTask, now)) {
                continue
            }
            if (TaskIO.readOutput(latestTask.id, maxBytes: 256).trimAscii().size > 0) {
                logger.warn(
                    "Skip orphan recovery after recheck because task already has output",
                    ("task_id", latestTask.id.toString()),
                    ("task_type", latestTask.taskType),
                    ("phase", latestTask.phase)
                )
                continue
            }

            logger.error(
                "Detected orphaned running task",
                ("task_id", latestTask.id.toString()),
                ("task_type", latestTask.taskType),
                ("phase", latestTask.phase),
                ("started_at", latestTask.startedAt)
            )
            TaskIO.appendLog(latestTask.id, "ERROR: task worker lost; marking task failed")
            if (TaskModel.failTask(latestTask.id, "Task worker lost")) {
                triggerDependentTasks(latestTask.id)
            }
        }
    }

    private func shouldRunOrphanReconcile(): Bool {
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        orphanReconcileMutex.lock()
        if ((nowMs - lastOrphanReconcileAtMs) < TaskPoolService.ORPHAN_RECONCILE_INTERVAL_MILLIS) {
            orphanReconcileMutex.unlock()
            return false
        }
        lastOrphanReconcileAtMs = nowMs
        orphanReconcileMutex.unlock()
        return true
    }

    private func isTaskOldEnoughForOrphanCheck(task: TaskData, now: DateTime): Bool {
        let baseline = if (task.startedAt.trimAscii().size > 0) { task.startedAt } else { task.createdAt }
        if (baseline.trimAscii().size == 0) {
            return false
        }
        match (DateTime.tryParse(baseline)) {
            case Some(started) =>
                let ageMs = (now - started).toMilliseconds()
                return ageMs >= TaskPoolService.ORPHAN_MIN_RUNNING_AGE_MILLIS
            case None =>
                return false
        }
    }

    /**
     * 触发依赖指定任务的等待任务
     * 当任务完成时，检查是否有等待它的任务，并根据完成状态激活或失败它们
     */
    private func triggerDependentTasks(completedTaskId: Int64): Unit {
        let logger = getLogger("taskpool")

        // 获取已完成任务的最新状态
        let completedTask = TaskDao.getTaskDataById(completedTaskId)
        if (completedTask.id == 0) {
            return
        }

        // 查询等待此任务的所有任务
        let waitingTasks = TaskDao.getTasksWaitingFor(completedTaskId)
        if (waitingTasks.size == 0) {
            return
        }

        logger.debug("触发依赖任务", ("completed_id", completedTaskId.toString()), ("waiting_count", waitingTasks.size.toString()))

        for (waitingTask in waitingTasks) {
            // 激活等待任务（无论依赖任务成功/失败）
            //
            // 原先的语义是：依赖失败则级联失败 waiting 任务。
            // 但像 download_url / metadata_plugin 这类“回调任务”需要在依赖失败时也能运行，
            // 以便读取插件任务输出并把失败结果写回到父任务/做清理。
            TaskDao.activateWaitingTask(waitingTask.id)
            logger.debug(
                "激活等待任务",
                ("id", waitingTask.id.toString()),
                ("wait_for_status", completedTask.status)
            )
        }

        // 通知有新任务可用
        notifyTaskAvailable()
    }

    private func executeTask(task: TaskData, workerIndex: Int32): Unit {
        let logger = getLogger("taskpool")
        TaskIO.appendLog(task.id, "[worker ${workerIndex}] start task ${task.id} type=${task.taskType}")
        TaskEventHub.getInstance().publishTaskStarted(task.id)

        // 创建 TaskRunnerContext
        let context = createTaskRunnerContext()

        match (task.taskType) {
            case "upload" =>
                // upload 任务类型只是一个占位符，用于让 TaskPool 调度机制介入
                // 实际上传由前端通过 /api/assets/upload/chunk 与上传结束动作驱动。
                // 这里需要阻塞 worker，直到任务进入终态，确保上传并发受 TaskPool 限制。
                let _ = TaskDao.extendTaskTimeout(task.id, UPLOAD_IDLE_TIMEOUT_SECONDS)
                TaskIO.appendLog(task.id, "upload task is now running, waiting for complete/failed")
                waitUploadTaskFinalization(task.id, "upload")
            case "asset_upload" =>
                let _ = TaskDao.extendTaskTimeout(task.id, UPLOAD_IDLE_TIMEOUT_SECONDS)
                TaskIO.appendLog(task.id, "asset_upload task is now running, waiting for complete/failed")
                waitUploadTaskFinalization(task.id, "asset_upload")
            case "download_url" =>
                DownloadUrlTaskRunner.run(task.id, task.parameters, context)
            case "upload_process" =>
                UploadProcessTaskRunner.run(task.id, task.parameters, context)
            case "asset_upload_process" =>
                AssetUploadProcessTaskRunner.run(task.id, task.parameters, context)
            case "archive_asset_consume" =>
                ArchiveAssetConsumeTaskRunner.run(task.id, task.parameters, context)
            case "tag_asset_consume" =>
                TagAssetConsumeTaskRunner.run(task.id, task.parameters, context)
            case "avatar_asset_consume" =>
                AvatarAssetConsumeTaskRunner.run(task.id, task.parameters, context)
            case "metadata_asset_consume" =>
                MetadataAssetConsumeTaskRunner.run(task.id, task.parameters, context)
            case "plugin_asset_consume" =>
                PluginAssetConsumeTaskRunner.run(task.id, task.parameters, context)
            case "metadata_plugin" =>
                MetadataPluginTaskRunner.run(task.id, task.parameters, context)
            case "download_url_callback" =>
                DownloadUrlCallbackRunner.run(task.id, task.parameters, context)
            case "tag_import" =>
                TagI18nImportTaskRunner.run(task.id, task.parameters, context)
            case "scan_all_categories" =>
                ScanAllCategoriesTaskRunner.run(task.id, task.parameters, context)
            case "scan_single_category" =>
                ScanSingleCategoryTaskRunner.run(task.id, task.parameters, context)
            case "scan_archive" =>
                ScanArchiveTaskRunner.run(task.id, task.parameters, context)
            case "generate_thumbnail" =>
                GenerateThumbnailTaskRunner.run(task.id, task.parameters, context)
            case "generate_category_cover" =>
                GenerateCategoryCoverTaskRunner.run(task.id, task.parameters, context)
            case "check_database" =>
                CheckDatabaseTaskRunner.run(task.id, task.parameters, context)
            case "scan_plugins" =>
                PluginTaskService.runScanPluginsTask(task.id, task.parameters, context)
            case "wasm_task" =>
                WasmTaskRunner.run(task.id, task.parameters)
            case "metadata_plugin_callback" =>
                MetadataPluginCallbackRunner.run(task.id, task.parameters, context)
            case "clear_cache" =>
                ClearCacheTaskRunner.run(task.id, task.parameters, context)
            case "clear_log" =>
                ClearLogTaskRunner.run(task.id, task.parameters, context)
            case "regenerate_cover" =>
                RegenerateCoverTaskRunner.run(task.id, task.parameters, context)
            case "backfill_metadata" =>
                BackfillMetadataTaskRunner.run(task.id, task.parameters, context)
            case "page_metadata" =>
                PageMetadataTaskRunner.run(task.id, task.parameters, context)
            case _ =>
                TaskIO.appendLog(task.id, "Unknown task type: ${task.taskType}")
                TaskModel.failTask(task.id, "Unknown task type: ${task.taskType}")
                TaskIO.writeOutput(task.id, "{\"success\":0,\"error\":\"Unknown task type: ${task.taskType}\"}")
        }

        logger.debug("TaskPool task finished", ("id", task.id.toString()), ("type", task.taskType), ("worker", workerIndex.toString()))
    }

    private static func isTerminalStatus(status: String): Bool {
        return status == "completed" || status == "failed" || status == "stopped"
    }

    private func waitUploadTaskFinalization(taskId: Int64, placeholderTaskType: String): Unit {
        let logger = getLogger("taskpool")
        let eventHub = TaskEventHub.getInstance()
        var ticks: Int64 = 0
        var revision = eventHub.currentRevision(taskId)

        while (isServiceRunning()) {
            let task = TaskDao.getTaskDataById(taskId)
            if (task.id == 0) {
                TaskIO.appendLog(taskId, "upload task missing while waiting; stop waiting")
                return
            }

            // async=1 分支会把当前 task 从 upload 改为 upload_process，
            // 检测到 task_type 变更即视为"upload 阶段结束"，释放当前 worker。
            // 无论 status 是 pending 还是 running（safetyTick/notifyTaskAvailable 抢先
            // dispatch 导致的 double-claim），都需要退出等待循环。
            if (task.taskType != placeholderTaskType) {
                TaskIO.appendLog(taskId, "${placeholderTaskType} task handed off to ${task.taskType}; release worker")
                return
            }

            if (isTerminalStatus(task.status)) {
                TaskIO.appendLog(taskId, "${placeholderTaskType} task reached terminal status: ${task.status}")
                return
            }

            let stableRevision = eventHub.currentRevision(taskId)
            if (stableRevision != revision) {
                revision = stableRevision
                continue
            }

            let waitResult = eventHub.awaitNext(taskId, revision, UPLOAD_WAIT_HEARTBEAT_MILLIS)
            revision = waitResult.revision
            if (!waitResult.changed) {
                ticks += 1
            }
            if (ticks > 0 && ticks % 30 == 0) {
                logger.debug(
                    "${placeholderTaskType} task still running",
                    ("task_id", taskId.toString()),
                    ("status", task.status),
                    ("progress", task.progress.toString())
                )
            }
        }
    }

    /**
     * 创建 TaskRunnerContext
     */
    private func createTaskRunnerContext(): TaskRunnerContext {
        let paths = TaskRunnerPaths(
            cachePath: SystemSettingsService.getPath("CACHE_PATH"),
            assetPath: SystemSettingsService.getPath("ASSET_PATH"),
            pluginPath: SystemSettingsService.getPath("PLUGIN_PATH")
        )
        let notifier: TaskNotifier = { => this.notifyTaskAvailable() }
        let requestDispatch: TaskNotifier = { => this.requestDispatch() }
        let kvStore = TaskKVService.getStore()
        return TaskRunnerContext(paths, notifier, requestDispatch, kvStore)
    }
}
