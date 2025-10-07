package lrr4cj.models

import std.unittest.*
import cjoy.*
import lrr4cj.services.*

/**
 * Shinobu状态数据模型
 */
public class ShinobuStatus {
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
    
    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        return "{\"success\":${success},\"is_alive\":${isAlive},\"operation\":\"${operation}\",\"pid\":${pid}}"
    }
}

/**
 * Shinobu操作结果数据模型
 */
public class ShinobuResult {
    public var success: Int32
    public var operation: String
    public var newPid: Int64
    
    public init(success: Int32, operation: String, newPid: Int64) {
        this.success = success
        this.operation = operation
        this.newPid = newPid
    }
    
    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        return "{\"success\":${success},\"operation\":\"${operation}\",\"new_pid\":${newPid}}"
    }
}

/**
 * Shinobu数据访问层
 */
public class ShinobuModel {
    /**
     * 获取Shinobu状态
     */
    public static func getShinobuStatus(): ShinobuStatus {
        let service = ShinobuService.getInstance()
        let statusData = service.getStatus()
        return ShinobuStatus(statusData.success, statusData.isAlive, statusData.operation, statusData.pid)
    }
    
    /**
     * 停止Shinobu
     */
    public static func stopShinobu(): Bool {
        let service = ShinobuService.getInstance()
        return service.stop()
    }
    
    /**
     * 重启Shinobu
     */
    public static func restartShinobu(): ShinobuResult {
        let service = ShinobuService.getInstance()
        let success = service.restart()
        let statusData = service.getStatus()
        return ShinobuResult(if (success) { 1 } else { 0 }, "shinobu_restart", statusData.pid)
    }
    
    /**
     * 启动Shinobu
     */
    public static func startShinobu(): Bool {
        let service = ShinobuService.getInstance()
        return service.start()
    }
    
    /**
     * 扫描档案文件
     */
    public static func scanArchives(): String {
        let service = ShinobuService.getInstance()
        let result = service.scanArchives()
        return "{\"processed_count\":${result.processedCount},\"error_count\":${result.errorCount},\"duration\":${result.duration}}"
    }
    
    /**
     * 获取Shinobu配置
     */
    public static func getShinobuConfiguration(): ShinobuConfiguration {
        let service = ShinobuService.getInstance()
        return service.getConfiguration()
    }
    
    /**
     * 获取当前任务数量
     */
    public static func getCurrentJobCount(): Int32 {
        let service = ShinobuService.getInstance()
        return service.getCurrentJobCount()
    }
    
    /**
     * 获取最大并发任务数
     */
    public static func getMaxConcurrentJobs(): Int32 {
        let service = ShinobuService.getInstance()
        return service.getMaxConcurrentJobs()
    }
    
    /**
     * 获取文件监视器状态
     */
    public static func getFileWatcherStatus(): FileWatcherStatus {
        let service = ShinobuService.getInstance()
        let statusData = service.getFileWatcherStatus()
        return FileWatcherStatus(
            statusData.isActive,
            statusData.watcherCount,
            statusData.lastEventTime,
            statusData.totalEvents,
            statusData.errorCount,
            statusData.lastError
        )
    }
    
    /**
     * 重启文件监视器
     */
    public static func restartFileWatcher(): Bool {
        let service = ShinobuService.getInstance()
        return service.restartFileWatcher()
    }
}

/**
 * 文件监视器状态数据模型
 */
public class FileWatcherStatus {
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
        return "{"
            + "\"isActive\":${isActive},"
            + "\"watcherCount\":${watcherCount},"
            + "\"lastEventTime\":\"${lastEventTime}\","
            + "\"totalEvents\":${totalEvents},"
            + "\"errorCount\":${errorCount},"
            + "\"lastError\":\"${lastError}\""
            + "}"
    }
}