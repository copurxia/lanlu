package lanlu.controllers

import cjoy.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.views.*

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

            // DB extensions status (tracked list; can expand in the future).
            let installedExts = DatabaseMetaDao.getInstalledExtensions()
            let trackedExts: Array<String> = ["pg_trgm"]

            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("motd").writeValue(serverMotd)
            w.writeName("name").writeValue(serverName)
            w.writeName("total_archives").writeValue(totalArchives)
            w.writeName("total_pages_read").writeValue(totalPagesRead)
            w.writeName("version").writeValue("0.9.50")
            w.writeName("version_desc").writeValue("Lanlu - Initial Release")
            w.writeName("version_name").writeValue("Cangjie")
            w.writeName("db_extensions")
            w.startArray()
            for (extName in trackedExts) {
                var enabled = false
                var version = ""
                match (installedExts.get(extName)) {
                    case Some(v) =>
                        enabled = true
                        version = v
                    case None => ()
                }
                w.startObject()
                w.writeName("name").writeValue(extName)
                w.writeName("enabled").writeValue(enabled)
                w.writeName("version").writeValue(version)
                w.endObject()
            }
            w.endArray()
            w.endObject()
            w.flush()
            ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
        } catch (ex: Exception) {
            ctx.status(500)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("error").writeValue("Failed to get server info: ${ex.message}")
            w.endObject()
            w.flush()
            ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
        }
    }

}
