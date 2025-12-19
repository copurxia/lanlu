package lrr4cj.services

import std.sync.*
import std.convert.*
import stdx.log.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

let logger = getLogger("shinobu")

/**
 * Shinobu 后台工作服务
 * 负责扫描漫画文件并生成缩略图
 */
public class ShinobuService {

    // 单例实例
    private static var instance: Option<ShinobuService> = Option<ShinobuService>.None
    private static let instanceMutex: Mutex = Mutex()
    
    // 服务状态
    private var isRunning: Bool = false
    private var currentPid: Int64 = 0
    private var mutex: Mutex  = Mutex()
    




    
    /**
     * 获取单例实例
     */
    public static func getInstance(): ShinobuService {
        instanceMutex.lock()
        if (instance.isNone()) {
            instance = Option<ShinobuService>.Some(ShinobuService())
        }
        let result = instance.getOrThrow()
        instanceMutex.unlock()
        return result
    }
    


    /**
     * 启动 Shinobu 服务
     */
    public func start(): Bool {
        mutex.lock()
        let result = startInternal()
        mutex.unlock()
        return result
    }
    
    /**
     * 内部启动方法
     */
    private func startInternal(): Bool {
        if (isRunning) {
            return true
        }
        
        isRunning = true
        // 触发启动任务（带防重复检查）
        triggerStartupTasks()

        // 注意：所有定时任务和文件监视现在由专门的执行器管理，ShinobuService只负责任务触发
        
        logger.info("Shinobu service started successfully")
        
        return true
    }
    
    /**
     * 停止 Shinobu 服务
     */
    public func stop(): Bool {
        mutex.lock()
        let result = stopInternal()
        mutex.unlock()
        return result
    }
    
    /**
     * 内部停止方法
     */
    private func stopInternal(): Bool {
        if (!isRunning) {
            return true
        }

        isRunning = false

        // 注意：任务现在由 TaskPool 和专门的执行器管理，不需要在这里停止
        
        return true
    }
    
    /**
     * 重启 Shinobu 服务
     */
    public func restart(): Bool {
        stop()
        return start()
    }
    
    /**
     * 获取服务状态
     */
    public func getStatus(): ShinobuStatusData {
        mutex.lock()
        let alive: Int32 = if (isRunning) { 1 } else { 0 }
        let status = ShinobuStatusData(1, alive, "shinobu_status", currentPid)
        mutex.unlock()
        return status
    }
    
    /**
     * 触发压缩包文件扫描任务
     */
    public func scanArchives(): ScanResultData {
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
        logger.info("Enqueued scan_plugins task", ("task_id", task.id.toString()))
        return task.id
    }

    /**
     * 触发缩略图生成任务
     */
    public func triggerThumbnailGeneration(archiveId: String, archivePath: String, priority!: Int32 = 40, triggerSource!: String = "manual"): Int64 {
        let source = if (triggerSource.size > 0) { triggerSource } else { "manual" }
        let params = "{\"archive_id\":\"${escapeJson(archiveId)}\",\"archive_path\":\"${escapeJson(archivePath)}\"}"
        let task = TaskModel.createTaskWithOptions("生成缩略图", "generate_thumbnail", params, priority, "", source)
        TaskPoolService.getInstance().notifyTaskAvailable()
        logger.info("Enqueued generate_thumbnail task", ("task_id", task.id.toString()), ("archive_id", archiveId))
        return task.id
    }

    /**
     * 触发启动任务（每次启动都执行）
     */
    private func triggerStartupTasks(): Unit {
        // 在创建启动任务之前，先清理孤儿任务
        // 这确保了：
        // 1. 应用启动时，之前的任务被正确清理
        // 2. ShinobuService 单独重启时，之前的任务被正确清理
        // 3. 新创建的启动任务不会被错误标记为失败
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
    }

    /**
     * 检查文件是否存在（公共方法）
     */
    public func checkFileExists(path: String): Bool {
        return DirectoryScanner.fileExists(path)
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
    








    







    


    /**
     * 获取配置信息
     */
    public func getConfiguration(): ShinobuConfiguration {
        return ShinobuConfiguration(
            SystemSettingsService.getBoolean("ENABLE_AUTO_SCAN"),
            SystemSettingsService.getBoolean("ENABLE_INITIAL_SCAN"),
            SystemSettingsService.getString("SCAN_INTERVAL_CRON"),
            SystemSettingsService.getBoolean("ENABLE_AUTO_THUMBNAIL"),
            SystemSettingsService.getString("THUMBNAIL_INTERVAL_CRON"),
            SystemSettingsService.getLong("SCAN_FALLBACK_INTERVAL_MS")
        )
    }
    

}

/**
 * Shinobu配置信息
 */
public class ShinobuConfiguration {
    public var enableAutoScan: Bool
    public var enableInitialScan: Bool
    public var scanIntervalCron: String
    public var enableAutoThumbnail: Bool
    public var thumbnailIntervalCron: String
    public var scanFallbackIntervalMs: Int64

    public init(
        enableAutoScan: Bool,
        enableInitialScan: Bool,
        scanIntervalCron: String,
        enableAutoThumbnail: Bool,
        thumbnailIntervalCron: String,
        scanFallbackIntervalMs: Int64
    ) {
        this.enableAutoScan = enableAutoScan
        this.enableInitialScan = enableInitialScan
        this.scanIntervalCron = scanIntervalCron
        this.enableAutoThumbnail = enableAutoThumbnail
        this.thumbnailIntervalCron = thumbnailIntervalCron
        this.scanFallbackIntervalMs = scanFallbackIntervalMs
    }

    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        return """
            {
            \"enableAutoScan\":${enableAutoScan},
            \"enableInitialScan\":${enableInitialScan},
            \"scanIntervalCron\":\"${scanIntervalCron}\",
            \"enableAutoThumbnail\":${enableAutoThumbnail},
            \"thumbnailIntervalCron\":\"${thumbnailIntervalCron}\",
            \"scanFallbackIntervalMs\":${scanFallbackIntervalMs}
            }"""
    }
}

/**
 * Shinobu状态数据
 */
public class ShinobuStatusData {
    public var success: Int32
    public var isAlive: Int32
    public var operation: String
    public var pid: Int64
    
    public init(success: Int32, isAlive: Int32, operation: String, pid: Int64) {
        this.success = success
        this.isAlive = isAlive
        this.operation = operation
        this.pid = pid
    }
}



/**
 * 插件元数据
 */
public class PluginMetadata {
    public var name: String = ""
    public var namespace: String = ""
    public var version: String = ""
    public var description: String = ""
    public var author: String = ""
    public var tags: String = ""
    public var permissions: String = ""
    public var parameters: String = "[]"
    public var url_regex: String = ""
    public var login_from: String = ""
    public var icon: String = ""
    public var has_schema: Bool = false

    public init() {}
}

/**
 * 扫描结果数据
 */
public class ScanResultData {
    public var processedCount: Int64
    public var totalFound: Int64
    public var errorCount: Int64
    public var errors: Array<String>
    public var taskId: Int64

    public init(processedCount: Int64, totalFound: Int64, errorCount: Int64, errors: Array<String>, taskId!: Int64 = 0) {
        this.processedCount = processedCount
        this.totalFound = totalFound
        this.errorCount = errorCount
        this.errors = errors
        this.taskId = taskId
    }
}

public class CheckResultData {
    public var success: Bool
    public var deletedCount: Int64
    public var checkedCount: Int64
    public var error: String

    public init(success: Bool, deletedCount: Int64, checkedCount: Int64, error: String) {
        this.success = success
        this.deletedCount = deletedCount
        this.checkedCount = checkedCount
        this.error = error
    }
}
