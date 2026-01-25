package lrr4cj.controllers

import cjoy.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

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
            // 获取档案总数
            let (_, totalArchives) = ArchiveDao.searchArchives("", "", 0, 0, "title", "asc")

            // 获取全局总阅读页数
            let totalPagesRead = UserStatsDao.getGlobalTotalPagesRead()

            // 从系统设置获取服务器名称和欢迎消息
            let serverName = SystemSettingsService.getString("SERVER_NAME")
            let serverMotd = SystemSettingsService.getString("SERVER_MOTD")

            // 构建服务器信息响应
            var serverInfo = "{"
            serverInfo += "\"motd\":\"${escapeJson(serverMotd)}\","
            serverInfo += "\"name\":\"${escapeJson(serverName)}\","
            serverInfo += "\"total_archives\":${totalArchives},"
            serverInfo += "\"total_pages_read\":${totalPagesRead},"
            serverInfo += "\"version\":\"0.9.50\","
            serverInfo += "\"version_desc\":\"Lanlu - Initial Release\","
            serverInfo += "\"version_name\":\"Cangjie\""
            serverInfo += "}"

            ctx.json(serverInfo)
        } catch (ex: Exception) {
            let errorResponse = "{\"error\":\"Failed to get server info: ${ex.message}\"}"
            ctx.status(500).json(errorResponse)
        }
    }

}
