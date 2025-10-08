package lrr4cj.controllers

import cjoy.*
import std.time.*
import std.convert.*
import std.collection.*
import lrr4cj.dao.*

/**
 * Info API 控制器
 * 处理 /api/info 接口
 */
public class InfoController {
    /**
     * 获取服务器信息
     */
    public static func getServerInfo(ctx: JoyContext) {
        try {
            // 获取当前时间戳
            let currentTime = DateTime.nowUTC().toUnixTimeStamp()
            
            // 获取档案总数
            let (_, totalArchives) = ArchiveDao.searchArchives("", "", 0, 0, "title", "asc")
            
            // 获取总阅读页数（这里使用模拟数据，实际应该从数据库获取）
            let totalPagesRead = 0
            
            // 构建服务器信息响应
            var serverInfo = "{"
            serverInfo += "\"archives_per_page\":100,"
            serverInfo += "\"cache_last_cleared\":${currentTime},"
            serverInfo += "\"debug_mode\":true,"
            serverInfo += "\"has_password\":false,"
            serverInfo += "\"motd\":\"LANraragi for Cangjie\","
            serverInfo += "\"name\":\"LANraragi\","
            serverInfo += "\"nofun_mode\":false,"
            serverInfo += "\"server_resizes_images\":false,"
            serverInfo += "\"server_tracks_progress\":true,"
            serverInfo += "\"total_archives\":${totalArchives},"
            serverInfo += "\"total_pages_read\":${totalPagesRead},"
            serverInfo += "\"version\":\"0.9.50\","
            serverInfo += "\"version_desc\":\"LANraragi for Cangjie - Initial Release\","
            serverInfo += "\"version_name\":\"Cangjie\""
            serverInfo += "}"
            
            ctx.json(serverInfo)
        } catch (ex: Exception) {
            let errorResponse = "{\"error\":\"Failed to get server info: ${ex.message}\"}"
            ctx.status(500).json(errorResponse)
        }
    }
}