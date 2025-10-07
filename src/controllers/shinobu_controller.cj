package lrr4cj.controllers

import cjoy.*
import lrr4cj.models.*
import lrr4cj.services.*

/**
 * Shinobu控制器
 */
public class ShinobuController {
    /**
     * 获取Shinobu状态
     */
    public static func getShinobuStatus(ctx: JoyContext) {
        let status = ShinobuModel.getShinobuStatus()
        ctx.json(status.toJson())
    }
    
    /**
     * 停止Shinobu
     */
    public static func stopShinobu(ctx: JoyContext) {
        let success = ShinobuModel.stopShinobu()
        if (success) {
            let response = "{\"operation\":\"shinobu_stop\",\"success\":1}"
            ctx.json(response)
        } else {
            let response = "{\"operation\":\"shinobu_stop\",\"success\":0}"
            ctx.json(response)
        }
    }
    
    /**
     * 重启Shinobu
     */
    public static func restartShinobu(ctx: JoyContext) {
        let result = ShinobuModel.restartShinobu()
        ctx.json(result.toJson())
    }
    
    /**
     * 启动Shinobu
     */
    public static func startShinobu(ctx: JoyContext) {
        let success = ShinobuModel.startShinobu()
        if (success) {
            let response = "{\"operation\":\"shinobu_start\",\"success\":1}"
            ctx.json(response)
        } else {
            let response = "{\"operation\":\"shinobu_start\",\"success\":0}"
            ctx.json(response)
        }
    }
    
    /**
     * 扫描档案文件
     */
    public static func scanArchives(ctx: JoyContext) {
        let result = ShinobuModel.scanArchives()
        ctx.json(result)
    }
    
    /**
     * 获取Shinobu配置
     */
    public static func getShinobuConfiguration(ctx: JoyContext) {
        let service = ShinobuService.getInstance()
        let config = service.getConfiguration()
        ctx.json(config.toJson())
    }
    
    /**
     * 获取当前任务状态
     */
    public static func getJobStatus(ctx: JoyContext) {
        let service = ShinobuService.getInstance()
        let currentJobs = service.getCurrentJobCount()
        let maxJobs = service.getMaxConcurrentJobs()
        
        let status = "{"
            + "\"currentJobs\":${currentJobs},"
            + "\"maxJobs\":${maxJobs},"
            + "\"availableSlots\":${maxJobs - currentJobs}"
            + "}"
        
        ctx.json(status)
    }
    
    /**
     * 获取文件监视器状态
     */
    public static func getFileWatcherStatus(ctx: JoyContext) {
        let status = ShinobuModel.getFileWatcherStatus()
        ctx.json(status.toJson())
    }
    
    /**
     * 重启文件监视器
     */
    public static func restartFileWatcher(ctx: JoyContext) {
        let success = ShinobuModel.restartFileWatcher()
        
        if (success) {
            let response = "{\"operation\":\"file_watcher_restart\",\"success\":1}"
            ctx.json(response)
        } else {
            let response = "{\"operation\":\"file_watcher_restart\",\"success\":0}"
            ctx.json(response)
        }
    }
}