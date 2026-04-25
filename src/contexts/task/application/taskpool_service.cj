package lanlu.contexts.task.application

import std.sync.*
import std.convert.*
import std.fs.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.infrastructure.kv.*
import lanlu.shared.utils.*

/**
 * Compatibility facade for TaskPool public entry points.
 */
public class TaskPoolService {
    private static var instance: Option<TaskPoolService> = Option<TaskPoolService>.None
    private static let instanceMutex: Mutex = Mutex()

    private let coordinator: TaskPoolCoordinator

    private init() {
        coordinator = TaskPoolCoordinator()
    }

    public static func getSupportedTaskTypes(): Array<String> {
        return TaskPoolService.getInstance().coordinator.supportedTaskTypes()
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
        return coordinator.start()
    }

    public func stop(): Unit {
        coordinator.stop()
    }

    public func isCoordinatorLoopAlive(): Bool {
        return coordinator.isCoordinatorLoopAlive()
    }

    public func notifyTaskAvailable(): Unit {
        coordinator.notifyTaskAvailable()
    }

    public func safetyTick(): Unit {
        coordinator.safetyTick()
    }

    public func reloadMaxWorkersConfig(): Unit {
        coordinator.reloadMaxWorkersConfig()
    }

    /**
     * Internal compatibility alias used by runner contexts.
     */
    public func requestDispatch(): Unit {
        coordinator.notifyTaskAvailable()
    }

    /**
     * 清理超时的上传任务：由 CronService 周期性调用
     */
    public static func cleanupTimedOutUploads(): Int64 {
        return TaskDao.failTimedOutUploadTasks()
    }

    /**
     * 清理孤立的上传临时文件：由 CronService 周期性调用
     * 扫描 data/cache/task/ 下的目录，清理已终态或不存在的任务对应的临时目录
     */
    public static func cleanupOrphanedUploadDirs(): Int64 {
        let logger = getLogger("taskpool_cleanup")
        let cacheTaskDir = "./data/cache/task"
        if (!exists(Path(cacheTaskDir))) {
            return 0
        }

        var cleanedCount: Int64 = 0
        try {
            let fileInfos = Directory.readFrom(Path(cacheTaskDir))
            for (fi in fileInfos) {
                let entry = fi.path.fileName.toString()
                let taskIdOpt = try { Some(Int64.parse(entry)) } catch (_: Exception) { Option<Int64>.None }
                match (taskIdOpt) {
                    case Some(taskId) =>
                        let task = TaskDao.getTaskDataById(taskId)
                        let shouldCleanup = if (task.id == 0) {
                            true
                        } else if (task.status == "completed" || task.status == "failed" || task.status == "stopped") {
                            true
                        } else {
                            false
                        }
                        if (shouldCleanup) {
                            let dirPath = Path("${cacheTaskDir}/${entry}")
                            try {
                                remove(dirPath, recursive: true)
                                cleanedCount += 1
                                logger.debug("Cleaned up orphaned upload dir", ("taskId", entry))
                            } catch (e: Exception) {
                                logger.warn("Failed to clean upload dir", ("taskId", entry), ("error", e.message))
                            }
                            TaskKVService.getStore().deleteGroup("asset_upload:${entry}")
                        }
                    case None => ()
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to scan upload cache dir", ("error", e.message))
        }

        if (cleanedCount > 0) {
            logger.debug("Upload dir cleanup completed", ("cleaned", cleanedCount.toString()))
        }
        return cleanedCount
    }
}
