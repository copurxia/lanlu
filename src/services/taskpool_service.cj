package lrr4cj.services

import std.sync.*
import std.convert.*
import stdx.log.*
import lrr4cj.dao.*
import lrr4cj.kv.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.task_runners.*

/**
 * TaskPool：用worker线程从DB领取pending任务并执行
 */
public class TaskPoolService {
    private static var instance: Option<TaskPoolService> = Option<TaskPoolService>.None
    private static let instanceMutex: Mutex = Mutex()

    // Keep in sync with `executeTask()` match arms.
    public static func getSupportedTaskTypes(): Array<String> {
        return [
            "download_url",
            "upload_process",
            "metadata_plugin",
            "download_url_callback",
            "tag_import",
            "scan_all_categories",
            "scan_single_category",
            "scan_archive",
            "generate_thumbnail",
            "check_database",
            "scan_plugins",
            "deno_task",
            "metadata_plugin_callback",
            "clear_cache",
            "clear_log",
            "regenerate_cover",
            "backfill_metadata"
        ]
    }

    private var isRunning: Bool = false
    private let runningMutex: Mutex = Mutex()
    private var tickStarted: Bool = false

    // 并发 worker 上限
    private var maxWorkers: Int32 = 2
    // 使用原子操作管理 worker 计数，减少锁竞争
    private let currentWorkers: AtomicInt32 = AtomicInt32(0)
    private let workerSeq: AtomicInt32 = AtomicInt32(0)
    // Safety tick interval (seconds). Use atomic so it can be reloaded at runtime.
    private let tickIntervalSeconds: AtomicInt32 = AtomicInt32(600)

    private init() {
        loadMaxWorkersConfig()
        loadTickIntervalConfig()
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

    private func loadTickIntervalConfig(): Unit {
        // Default to 5 minutes. Keep a reasonable floor to avoid excessive DB polling.
        let secondsInt = SystemSettingsService.getInt("TASKPOOL_TICK_SECONDS")
        var seconds = if (secondsInt > 0) { secondsInt } else { 600i32 }
        if (seconds < 30i32) {
            seconds = 30i32
        }
        if (seconds > 86400i32) {
            seconds = 86400i32
        }
        tickIntervalSeconds.store(seconds)
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
        // Start a low-frequency safety tick so the pool can recover from missed notifies.
        // This is intentionally infrequent (5 minutes) to avoid extra DB load.
        if (!tickStarted) {
            tickStarted = true
            spawn { tickLoop() }
        }
        runningMutex.unlock()

        let logger = getLogger("taskpool")
        logger.debug("TaskPool starting", ("max_workers", maxWorkers.toString()))

        // 注意：孤儿任务清理现在由 ShinobuService 在创建启动任务之前处理
        // 这里不需要重复清理，避免时序问题

        // 启动时仅尝试领取已有 pending（不做轮询）
        dispatch()
        return true
    }

    private func isServiceRunning(): Bool {
        runningMutex.lock()
        let running = isRunning
        runningMutex.unlock()
        return running
    }

    /**
     * Safety tick: periodically call dispatch() even if no notify is triggered.
     * This helps recover if workers are stuck in a state where dispatch() is never reached.
     */
    private func tickLoop(): Unit {
        let logger = getLogger("taskpool")
        while (true) {
            // Sleep first so start() can do an immediate dispatch().
            let seconds = tickIntervalSeconds.load()
            sleep(Duration.second * Int64(seconds))
            if (!isServiceRunning()) {
                return
            }
            try {
                logger.debug("TaskPool tick dispatch")
                dispatch()
            } catch (e: Exception) {
                // Best-effort: never let the tick thread die.
                logger.warn("TaskPool tick failed", ("error", e.message))
            }
        }
    }

    /**
     * 有新任务入队时调用：尽可能填满并发 worker
     */
    public func notifyTaskAvailable(): Unit {
        dispatch()
    }

    /**
     * 重新加载最大并发任务数配置
     * 在系统设置更新后调用此方法以应用新配置
     */
    public func reloadMaxWorkersConfig(): Unit {
        let logger = getLogger("taskpool")
        let oldMaxWorkers = maxWorkers
        let oldTickSeconds = tickIntervalSeconds.load()
        loadMaxWorkersConfig()
        loadTickIntervalConfig()
        let newTickSeconds = tickIntervalSeconds.load()
        logger.debug(
            "TaskPool config reloaded",
            ("old_max_workers", oldMaxWorkers.toString()),
            ("new_max_workers", maxWorkers.toString()),
            ("old_tick_seconds", oldTickSeconds.toString()),
            ("new_tick_seconds", newTickSeconds.toString())
        )
    }

    /**
     * 调度：批量领取 pending 任务并 spawn worker 执行
     * 使用原子操作实现无锁调度，一次 DB 查询领取多个任务
     */
    private func dispatch(): Unit {
        if (!isServiceRunning()) {
            return
        }

        // 计算可用 slot 数量
        let current = currentWorkers.load()
        let available = maxWorkers - current
        if (available <= 0) {
            return
        }

        // 批量领取任务（一次 DB 往返）
        let tasks = TaskDao.claimPendingTasks(available)
        if (tasks.size == 0) {
            return
        }

        // 为每个任务 spawn worker
        for (task in tasks) {
            // 原子增加 worker 计数
            currentWorkers.fetchAdd(1)
            let workerId = workerSeq.fetchAdd(1)
            let taskData = task
            let id = workerId
            spawn {
                runWorker(taskData, id)
            }
        }
    }

    private func runWorker(task: TaskData, workerId: Int32): Unit {
        let logger = getLogger("taskpool")
        logger.debug("TaskPool worker executing", ("worker", workerId.toString()), ("task_id", task.id.toString()), ("task_type", task.taskType))
        executeTask(task, workerId)

        // 异步触发依赖此任务的等待任务（不阻塞 worker 释放）
        let completedTaskId = task.id
        spawn { triggerDependentTasks(completedTaskId) }

        // 释放 slot 并尝试领取下一个 pending（使用原子操作）
        currentWorkers.fetchSub(1)

        dispatch()
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
            // 以便读取 deno_task 输出并把失败结果写回到父任务/做清理。
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

        // 创建 TaskRunnerContext
        let context = createTaskRunnerContext()

        match (task.taskType) {
            case "download_url" =>
                DownloadUrlTaskRunner.run(task.id, task.parameters, context)
            case "upload_process" =>
                UploadProcessTaskRunner.run(task.id, task.parameters, context)
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
            case "check_database" =>
                CheckDatabaseTaskRunner.run(task.id, task.parameters, context)
            case "scan_plugins" =>
                ScanPluginsTaskRunner.run(task.id, task.parameters, context)
            case "deno_task" =>
                DenoTaskRunner.run(task.id, task.parameters)
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
            case _ =>
                TaskIO.appendLog(task.id, "Unknown task type: ${task.taskType}")
                TaskModel.failTask(task.id, "Unknown task type: ${task.taskType}")
                TaskIO.writeOutput(task.id, "{\"success\":0,\"error\":\"Unknown task type: ${task.taskType}\"}")
        }

        logger.debug("TaskPool task finished", ("id", task.id.toString()), ("type", task.taskType), ("worker", workerIndex.toString()))
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
        let kvStore = TaskGroupKVStore.getInstance()
        return TaskRunnerContext(paths, notifier, kvStore)
    }
}
