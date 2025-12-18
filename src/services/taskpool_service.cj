package lrr4cj.services

import std.sync.*
import std.convert.*
import stdx.log.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

/**
 * TaskPool：用worker线程从DB领取pending任务并执行
 */
public class TaskPoolService {
    private static var instance: Option<TaskPoolService> = Option<TaskPoolService>.None
    private static let instanceMutex: Mutex = Mutex()

    private var isRunning: Bool = false
    private let runningMutex: Mutex = Mutex()

    // 并发 worker 上限
    private var maxWorkers: Int32 = 2
    private var currentWorkers: Int32 = 0
    private var workerSeq: Int32 = 0
    private let dispatchMutex: Mutex = Mutex()

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
        logger.info("TaskPool starting", ("max_workers", maxWorkers.toString()))

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
        loadMaxWorkersConfig()
        logger.info("TaskPool max workers config reloaded", ("old_max_workers", oldMaxWorkers.toString()), ("new_max_workers", maxWorkers.toString()))
    }

    /**
     * 调度：在并发上限内领取 pending 任务并 spawn worker 执行
     */
    private func dispatch(): Unit {
        while (true) {
            if (!isServiceRunning()) {
                return
            }

            // 先占用一个 worker slot（避免并发超发），DB 操作不持锁
            dispatchMutex.lock()
            if (currentWorkers >= maxWorkers) {
                dispatchMutex.unlock()
                return
            }
            let workerId = workerSeq
            workerSeq += 1
            currentWorkers += 1
            dispatchMutex.unlock()

            // 领取一个 pending（无任务则释放 slot 并退出）
            match (TaskDao.claimNextPendingTask()) {
                case Some(taskData) =>
                    let id = workerId
                    spawn {
                        runWorker(taskData, id)
                    }
                case None =>
                    dispatchMutex.lock()
                    if (currentWorkers > 0) {
                        currentWorkers -= 1
                    }
                    dispatchMutex.unlock()
                    return
            }
        }
    }

    private func runWorker(task: TaskData, workerId: Int32): Unit {
        let logger = getLogger("taskpool")
        logger.info("TaskPool worker executing", ("worker", workerId.toString()), ("task_id", task.id.toString()), ("task_type", task.taskType))
        executeTask(task, workerId)

        // 释放 slot 并尝试领取下一个 pending
        dispatchMutex.lock()
        if (currentWorkers > 0) {
            currentWorkers -= 1
        }
        dispatchMutex.unlock()

        dispatch()
    }

    private func executeTask(task: TaskData, workerIndex: Int32): Unit {
        let logger = getLogger("taskpool")
        TaskIO.appendLog(task.id, "[worker ${workerIndex}] start task ${task.id} type=${task.taskType}")

        match (task.taskType) {
            case "download_url" =>
                DownloadUrlTaskRunner.run(task.id, task.parameters)
            case "upload_process" =>
                UploadProcessTaskRunner.run(task.id, task.parameters)
            case "metadata_plugin" =>
                MetadataPluginTaskRunner.run(task.id, task.parameters)
            case "tag_import" =>
                TagI18nImportTaskRunner.run(task.id, task.parameters)
            case "scan_directory" =>
                ScanDirectoryTaskRunner.run(task.id, task.parameters)
            case "scan_archive" =>
                ScanArchiveTaskRunner.run(task.id, task.parameters)
            case "generate_thumbnail" =>
                GenerateThumbnailTaskRunner.run(task.id, task.parameters)
            case "check_database" =>
                CheckDatabaseTaskRunner.run(task.id, task.parameters)
            case "scan_plugins" =>
                ScanPluginsTaskRunner.run(task.id, task.parameters)
            case _ =>
                TaskIO.appendLog(task.id, "Unknown task type: ${task.taskType}")
                TaskModel.failTask(task.id, "Unknown task type: ${task.taskType}")
                TaskIO.writeOutput(task.id, "{\"success\":0,\"error\":\"Unknown task type: ${task.taskType}\"}")
        }

        logger.info("TaskPool task finished", ("id", task.id.toString()), ("type", task.taskType), ("worker", workerIndex.toString()))
    }
}
