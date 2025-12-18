package lrr4cj.services

import std.fs.*
import std.time.*
import std.sync.*
import std.convert.*
import stdx.log.*
import cjoy.json.*
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
    
    // 配置 - 使用静态变量存储配置
    private static var archivePath: Path = Path("")
    private static var thumbnailPath: Path = Path("")
    private static var cachePath: Path = Path("")
    private static var pluginPath: Path = Path("")

    // 扫描和缩略图配置 - 使用静态变量存储配置
    private static var enableAutoScan: Bool = false
    private static var enableInitialScan: Bool = false
    private static var scanIntervalCron: String = ""
    private static var enableAutoThumbnail: Bool = false
    private static var thumbnailIntervalCron: String = ""
    private static var scanFallbackIntervalMs: Int64 = 0
    private static var enableFileWatcher: Bool = true
    private static var enableDbCheck: Bool = false
    private static var dbCheckIntervalCron: String = ""
    private static var enableInitialDbCheck: Bool = false

    // 定时任务线程 - 使用字符串标识线程
    private var scanThread: Option<String> = Option<String>.None
    private var thumbnailThread: Option<String> = Option<String>.None
    private var fileWatcherThread: Option<String> = Option<String>.None
    private var dbCheckThread: Option<String> = Option<String>.None
    
    // 任务控制标志
    private var isTaskRunning: Bool = false
    private let runningMutex: Mutex = Mutex()
    


    /**
     * 初始化静态配置
     * 必须在获取实例之前调用，且在SystemSettingsService初始化之后
     */
    public static func initializeConfig(): Unit {
        // 从系统设置服务读取配置
        let archivePathStr = SystemSettingsService.getPath("ARCHIVE_PATH")
        let thumbnailPathStr = SystemSettingsService.getPath("THUMBNAIL_PATH")
        let cachePathStr = SystemSettingsService.getPath("CACHE_PATH")
        let pluginPathStr = "./plugins" // 插件路径保留在代码中或可扩展为配置

        // 转换为 Path 类型并规范化
        archivePath = canonicalize(archivePathStr)
        thumbnailPath = canonicalize(thumbnailPathStr)
        cachePath = canonicalize(cachePathStr)
        pluginPath = canonicalize(pluginPathStr)

        // 确保必要的目录存在
        FileUtils.ensureDirectoryExists(archivePath)
        FileUtils.ensureDirectoryExists(thumbnailPath)
        FileUtils.ensureDirectoryExists(cachePath)
        FileUtils.ensureDirectoryExists(pluginPath)

        // 创建上传缓存目录
        let uploadsPath = cachePath.join("uploads")
        FileUtils.ensureDirectoryExists(uploadsPath)

        // 读取扫描和缩略图配置
        enableAutoScan = SystemSettingsService.getBoolean("ENABLE_AUTO_SCAN")
        enableInitialScan = SystemSettingsService.getBoolean("ENABLE_INITIAL_SCAN")
        scanIntervalCron = SystemSettingsService.getString("SCAN_INTERVAL_CRON")
        enableAutoThumbnail = SystemSettingsService.getBoolean("ENABLE_AUTO_THUMBNAIL")
        thumbnailIntervalCron = SystemSettingsService.getString("THUMBNAIL_INTERVAL_CRON")
        scanFallbackIntervalMs = SystemSettingsService.getLong("SCAN_FALLBACK_INTERVAL_MS")

        // 数据库检查配置（从数据库读取）
        enableDbCheck = SystemSettingsService.getBoolean("ENABLE_DB_CHECK")
        dbCheckIntervalCron = SystemSettingsService.getString("DB_CHECK_INTERVAL_CRON")
        enableInitialDbCheck = SystemSettingsService.getBoolean("ENABLE_INITIAL_DB_CHECK")

        enableFileWatcher = true
    }

    
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
     * 获取归档路径
     */
    public static func getArchivePath(): Path {
        return archivePath
    }
    
    /**
     * 获取缩略图路径
     */
    public static func getThumbnailPath(): Path {
        return thumbnailPath
    }
    
    /**
     * 获取缓存路径
     */
    public static func getCachePath(): Path {
        return cachePath
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
        currentPid = getCurrentProcessId()
        
        logger.info("Shinobu service starting with configuration",
            ("archive_path", archivePath.toString()),
            ("thumbnail_path", thumbnailPath.toString()),
            ("cache_path", cachePath.toString()),
            ("enable_auto_scan", enableAutoScan.toString()),
            ("enable_initial_scan", enableInitialScan.toString()),
            ("scan_interval_cron", scanIntervalCron),
            ("enable_auto_thumbnail", enableAutoThumbnail.toString()),
            ("thumbnail_interval_cron", thumbnailIntervalCron),
            ("scan_fallback_interval_ms", scanFallbackIntervalMs.toString()),
            ("enable_file_watcher", enableFileWatcher.toString()),
            ("enable_initial_db_check", enableInitialDbCheck.toString()),
            ("enable_db_check", enableDbCheck.toString()),
            ("db_check_interval_cron", dbCheckIntervalCron))

        // 触发启动任务（带防重复检查）
        triggerStartupTasks()

        // 如果启用初始扫描，启动时进行一次扫描（已废弃，改用任务触发）
        // 保留旧的 spawnScanThread 逻辑以防万一，但优先使用任务触发
        if (enableInitialScan) {
            logger.info("Initial scan will be triggered via task system")
        } else {
            logger.info("Initial scan is disabled")
        }
        
        // 如果启用自动扫描，启动定时任务
        if (enableAutoScan) {
            startScheduledScan()
        } else {
            logger.info("Auto scan is disabled")
        }
        
        // 如果启用自动缩略图生成，启动定时任务
        if (enableAutoThumbnail) {
            startScheduledThumbnail()
        } else {
            logger.info("Auto thumbnail generation is disabled")
        }
        
        // 启动文件监视器（如果启用）
        if (enableFileWatcher) {
            startFileWatcher()
        }
        
        // 如果启用初始数据库检查，启动时进行一次检查
        if (enableInitialDbCheck) {
            logger.info("Starting initial database check...")
            triggerDatabaseCheck(priority: 50, triggerSource: "startup")
        } else {
            logger.info("Initial database check is disabled")
        }
        
        // 启动数据库检查（如果启用）
        if (enableDbCheck) {
            startScheduledDbCheck()
        } else {
            logger.info("Database check is disabled")
        }
        
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

        // 停止所有定时任务
        stopScheduledTasks()

        // 注意：任务现在由 TaskPool 管理，不需要在这里等待

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
        let scanPath = ShinobuService.archivePath.toString()
        let dirExists = directoryExists(scanPath)
        if (!dirExists) {
            logger.error("Archive directory does not exist", ("path", scanPath))
            return ScanResultData(0, 0, 1, ["Archive directory does not exist: ${scanPath}"])
        }

        let taskId = triggerDirectoryScan(scanPath: scanPath, priority: 30, triggerSource: "manual")
        logger.info("Enqueued scan_directory task", ("task_id", taskId.toString()), ("path", scanPath))
        return ScanResultData(0, 0, 0, Array<String>(), taskId: taskId)
    }

    public func triggerDirectoryScan(scanPath!: String = "", priority!: Int32 = 30, triggerSource!: String = "manual"): Int64 {
        let targetPath = if (scanPath.size > 0) { scanPath } else { ShinobuService.archivePath.toString() }
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

        // 1. 触发目录扫描任务（如果启用初始扫描）
        if (enableInitialScan) {
            let taskId = triggerDirectoryScan(priority: 30, triggerSource: "startup")
            logger.info("Triggered startup scan_directory task", ("task_id", taskId.toString()))
        }

        // 2. 触发数据库检查任务（如果启用初始数据库检查）
        if (enableInitialDbCheck) {
            let taskId = triggerDatabaseCheck(priority: 50, triggerSource: "startup")
            logger.info("Triggered startup check_database task", ("task_id", taskId.toString()))
        }

        // 3. 触发插件扫描任务（总是在启动时执行）
        let taskId = triggerPluginScan(priority: 50, triggerSource: "startup")
        logger.info("Triggered startup scan_plugins task", ("task_id", taskId.toString()))
    }

    /**
     * 检查文件是否存在（公共方法）
     */
    public func checkFileExists(path: String): Bool {
        return fileExists(path)
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
     * 生成文件哈希（公共方法）
     */
    public func generateFileHashForUpload(filePath: String): String {
        return ArchiveUtils.generateFileHash(filePath)
    }



    



    


    

    

    

    

    



    
    /**
     * 获取当前进程ID
     */
    private func getCurrentProcessId(): Int64 {
        // 简单实现，实际应该使用系统API
        return 12345
    }
    


    /**
     * 检查目录是否存在（支持软链接）- 保持向后兼容性
     */
    private func directoryExists(path: String): Bool {
        return DirectoryScanner.directoryExists(path)
    }

    /**
     * 检查文件是否存在（支持软链接）- 保持向后兼容性
     */
    private func fileExists(path: String): Bool {
        return DirectoryScanner.fileExists(path)
    }

    /**
     * 列出目录内容（支持软链接）- 保持向后兼容性
     */
    private func listDirectory(path: String): Array<String> {
        return DirectoryScanner.listDirectory(path)
    }

    /**
     * 拼接路径 - 保持向后兼容性
     */
    private func joinPath(base: String, part: String): String {
        return DirectoryScanner.joinPath(base, part)
    }






    




    /**
     * 启动定时扫描任务
     */
    private func startScheduledScan() {
        if (enableAutoScan) {
            // 生成线程ID
            let threadId = "scheduled-scan-${DateTime.nowUTC().toUnixTimeStamp()}"
            scanThread = Option<String>.Some(threadId)
            
            spawn {
                logger.info("Starting scheduled scan", ("cron", scanIntervalCron))
                
                // 简单的定时实现：每隔一定时间执行一次
                // 实际应该解析 cron 表达式并精确调度
                let intervalSeconds = parseCronToSeconds(scanIntervalCron)
                
                runningMutex.lock()
                let running = isTaskRunning
                runningMutex.unlock()
                
                while (running) {
                    sleep(Duration.second * intervalSeconds)
                    
                    runningMutex.lock()
                    let stillRunning = isTaskRunning
                    runningMutex.unlock()
                    
                    if (!stillRunning) {
                        break
                    }
                    
                    logger.debug("Executing scheduled scan enqueue")
                    triggerDirectoryScan(scanPath: ShinobuService.archivePath.toString(), priority: 30, triggerSource: "scheduled")
                }
                
                logger.info("Scheduled scan thread stopped")
            }
        }
    }
    
    /**
     * 启动定时缩略图任务
     */
    private func startScheduledThumbnail() {
        if (enableAutoThumbnail) {
            // 生成线程ID
            let threadId = "thumbnail-${DateTime.nowUTC().toUnixTimeStamp()}"
            thumbnailThread = Option<String>.Some(threadId)
            
            spawn {
                logger.info("Starting scheduled thumbnail generation", ("cron", thumbnailIntervalCron))
                
                // 简单的定时实现：每隔一定时间执行一次
                // 实际应该解析 cron 表达式并精确调度
                let intervalSeconds = parseCronToSeconds(thumbnailIntervalCron)
                
                runningMutex.lock()
                let running = isTaskRunning
                runningMutex.unlock()
                
                while (running) {
                    sleep(Duration.second * intervalSeconds)
                    
                    runningMutex.lock()
                    let stillRunning = isTaskRunning
                    runningMutex.unlock()
                    
                    if (!stillRunning) {
                        break
                    }

                    logger.info("Executing scheduled thumbnail generation")
                    // TODO: 为所有没有缩略图的归档创建 generate_thumbnail 任务
                    // generateAllThumbnails() 方法已移动到 GenerateThumbnailTaskRunner
                }
                
                logger.info("Scheduled thumbnail generation thread stopped")
            }
        }
    }
    
    /**
     * 启动定时数据库检查任务
     */
    private func startScheduledDbCheck() {
        if (enableDbCheck) {
            // 生成线程ID
            let threadId = "db-check-${DateTime.nowUTC().toUnixTimeStamp()}"
            dbCheckThread = Option<String>.Some(threadId)
            
            spawn {
                logger.info("Starting scheduled database check", ("cron", dbCheckIntervalCron))
                
                // 简单的定时实现：每隔一定时间执行一次
                // 实际应该解析 cron 表达式并精确调度
                let intervalSeconds = parseCronToSeconds(dbCheckIntervalCron)
                
                runningMutex.lock()
                let running = isTaskRunning
                runningMutex.unlock()
                
                while (running) {
                    sleep(Duration.second * intervalSeconds)
                    
                    runningMutex.lock()
                    let stillRunning = isTaskRunning
                    runningMutex.unlock()

                    if (!stillRunning) {
                        break
                    }

                    logger.info("Executing scheduled database check")
                    triggerDatabaseCheck(priority: 50, triggerSource: "scheduled")
                }
                
                logger.info("Scheduled database check thread stopped")
            }
        }
    }

    /**
     * 启动文件监视器
     */
    private func startFileWatcher() {
        if (enableAutoScan) {
            // 生成线程ID
            let threadId = "file-watcher-${DateTime.nowUTC().toUnixTimeStamp()}"
            fileWatcherThread = Option<String>.Some(threadId)
            
            spawn {
                logger.debug("Starting file watcher", ("directory", archivePath.toString()))
                logger.debug("File watcher polling interval", ("interval_ms", scanFallbackIntervalMs.toString()))
                
                // 简单的轮询实现：每隔一定时间检查目录变化
                // 实际应该使用文件系统监视 API
                var lastFileCount = countFilesInDirectory(archivePath.toString())
                logger.debug("Initial file count in archive directory", ("count", lastFileCount.toString()))
                
                runningMutex.lock()
                let running = isTaskRunning
                runningMutex.unlock()
                
                while (running) {
                    sleep(Duration.second * (scanFallbackIntervalMs / 1000))
                    
                    runningMutex.lock()
                    let stillRunning = isTaskRunning
                    runningMutex.unlock()
                    
                    if (!stillRunning) {
                        break
                    }
                    
                    // 检查目录中的文件数量是否变化
                    let currentFileCount = countFilesInDirectory(archivePath.toString())
                    if (currentFileCount != lastFileCount) {
                        logger.debug("File change detected, triggering scan", ("previous_count", lastFileCount.toString()), ("current_count", currentFileCount.toString()))
                        triggerDirectoryScan(scanPath: ShinobuService.archivePath.toString(), priority: 30, triggerSource: "watcher")
                        lastFileCount = currentFileCount
                    } else {
                        logger.debug("File watcher check: no changes detected", ("count", currentFileCount.toString()))
                    }
                }
                
                logger.info("File watcher thread stopped")
            }
        } else {
            logger.info("File watcher is disabled")
        }
    }
    
    /**
     * 停止所有定时任务
     */
    private func stopScheduledTasks() {
        runningMutex.lock()
        isTaskRunning = false
        runningMutex.unlock()
        
        // 等待所有线程结束 - 仓颉中无法直接join线程，线程会在isTaskRunning=false时自动退出
        match (scanThread) {
            case Option<String>.Some(_) =>
                // 线程会在 isTaskRunning = false 时自动退出
                ()
            case Option<String>.None => ()
        }
        
        match (thumbnailThread) {
            case Option<String>.Some(_) =>
                // 线程会在 isTaskRunning = false 时自动退出
                ()
            case Option<String>.None => ()
        }
        
        match (fileWatcherThread) {
            case Option<String>.Some(_) =>
                // 线程会在 isTaskRunning = false 时自动退出
                ()
            case Option<String>.None => ()
        }
        
        match (dbCheckThread) {
            case Option<String>.Some(_) =>
                // 线程会在 isTaskRunning = false 时自动退出
                ()
            case Option<String>.None => ()
        }
        
        scanThread = Option<String>.None
        thumbnailThread = Option<String>.None
        fileWatcherThread = Option<String>.None
        dbCheckThread = Option<String>.None
        
        logger.info("All scheduled tasks stopped")
    }
    
    /**
     * 简单解析 cron 表达式为秒数
     * 这是一个简化实现，实际应该使用完整的 cron 解析库
     */
    private func parseCronToSeconds(cronExpression: String): Int64 {
        // 简单实现：只处理数字格式（表示秒数）
        // 实际应该解析完整的 cron 表达式
        try {
            let seconds = Int64.parse(cronExpression)
            return seconds
        } catch (e: Exception) {
            // 默认 1 小时
            return 3600
        }
    }
    
    /**
     * 计算目录中的文件数量
     */
    private func countFilesInDirectory(dirPath: String): Int64 {
        var count: Int64 = 0

        try {
            let entries = listDirectory(dirPath)
            for (entry in entries) {
                let entryPath = joinPath(dirPath, entry)
                if (fileExists(entryPath)) {
                    count += 1
                }
            }
        } catch (e: Exception) {
            logger.error("Error counting files in directory", ("directory", dirPath))
        }

        return count
    }

    /**
     * 获取配置信息
     */
    public func getConfiguration(): ShinobuConfiguration {
        return ShinobuConfiguration(
            ShinobuService.enableAutoScan,
            ShinobuService.enableInitialScan,
            ShinobuService.scanIntervalCron,
            ShinobuService.enableAutoThumbnail,
            ShinobuService.thumbnailIntervalCron,
            ShinobuService.scanFallbackIntervalMs
        )
    }
    
    /**
     * 获取文件监视器状态
     */
    public func getFileWatcherStatus(): FileWatcherStatusData {
        // 检查文件监视器是否活跃
        let isActive = isFileWatcherActive()
        
        // 获取监视器数量（简化实现）
        let watcherCount: Int32 = if (isActive) { 1 } else { 0 }
        
        // 获取最后事件时间（简化实现）
        let lastEventTime = if (isActive) {
            DateTime.nowUTC().toString()
        } else {
            "Never"
        }
        
        // 获取总事件数（简化实现）
        let totalEvents: Int64 = 0 // 实际应该跟踪事件数量
        
        // 获取错误数（简化实现）
        let errorCount: Int64 = 0 // 实际应该跟踪错误数量
        
        // 获取最后错误（简化实现）
        let lastError = "" // 实际应该记录最后错误
        
        return FileWatcherStatusData(
            isActive,
            watcherCount,
            lastEventTime,
            totalEvents,
            errorCount,
            lastError
        )
    }
    
    /**
     * 检查文件监视器是否活跃
     */
    private func isFileWatcherActive(): Bool {
        match (fileWatcherThread) {
            case Option<String>.Some(_) =>
                return isRunning && ShinobuService.enableFileWatcher
            case Option<String>.None =>
                return false
        }
    }
    
    /**
     * 重启文件监视器
     */
    public func restartFileWatcher(): Bool {
        // 停止现有的文件监视器
        stopFileWatcher()
        
        // 等待一段时间
        sleep(Duration.second * 2)
        
        // 重新启动文件监视器
        if (enableFileWatcher && isRunning) {
            startFileWatcher()
            return true
        }
        
        return false
    }
    
    /**
     * 停止文件监视器
     */
    private func stopFileWatcher() {
        match (fileWatcherThread) {
            case Option<String>.Some(_) =>
                // 线程会在 isTaskRunning = false 时自动退出
                fileWatcherThread = Option<String>.None
                logger.info("File watcher stopped")
            case Option<String>.None =>
                ()
        }
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
 * 文件监视器状态数据
 */
public class FileWatcherStatusData {
    public var isActive: Bool
    public var watcherCount: Int32
    public var lastEventTime: String
    public var totalEvents: Int64
    public var errorCount: Int64
    public var lastError: String
    
    public init(isActive: Bool, watcherCount: Int32, lastEventTime: String,
                totalEvents: Int64, errorCount: Int64, lastError: String) {
        this.isActive = isActive
        this.watcherCount = watcherCount
        this.lastEventTime = lastEventTime
        this.totalEvents = totalEvents
        this.errorCount = errorCount
        this.lastError = lastError
    }
    
    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        return """
            {
            \"isActive\":${isActive},
            \"watcherCount\":${watcherCount},
            \"lastEventTime\":\"${lastEventTime}\",
            \"totalEvents\":${totalEvents},
            \"errorCount\":${errorCount},
            \"lastError\":\"${lastError}\"
            }"""
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
