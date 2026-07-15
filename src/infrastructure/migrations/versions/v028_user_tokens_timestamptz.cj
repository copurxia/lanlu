package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*

/**
 * V028: user_tokens 时间列迁移为 timestamptz，并固定数据库默认时区为 Asia/Shanghai。
 *
 * 背景：原列是 timestamp WITHOUT time zone，由 CURRENT_TIMESTAMP 写入，其值依赖会话时区。
 * 服务端 postgresql.conf 配置为 America/Los_Angeles，而应用与用户预期为 Asia/Shanghai，
 * 导致 sessions 等接口返回的时间与真实北京时间偏差约 15 小时。
 *
 * 本迁移：
 * 1. 将现有 naive timestamp 按 Los_Angeles 时区解释为真实时刻，转为 timestamptz；
 * 2. 设置当前数据库默认 timezone 为 Asia/Shanghai，使后续会话的 CURRENT_TIMESTAMP
 *    及 timestamptz 的文本显示都使用北京时间。
 *
 * 历史数据按 Los_Angeles 解释；若后续发现历史数据实际写入于其他时区，可单独修正。
 */
public class V028_UserTokensTimestamptz <: Migration {
    public func version(): String {
        return "V028"
    }

    public func description(): String {
        return "Convert user_tokens timestamp columns to timestamptz and set DB timezone to Asia/Shanghai"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.tableExists(db, "user_tokens")) {
            return true
        }

        // 固定该数据库的默认会话时区，避免后续连接再继承服务器 America/Los_Angeles。
        // 先查出当前库名（ALTER DATABASE 不接受 current_database() 函数）。
        match (db.rawOne<String>("SELECT current_database()", [], { row => row.getText(0) })) {
            case Some(dbName) =>
                let safeName = dbName.replace("\"", "\"\"")
                let setTzSql = "ALTER DATABASE \"${safeName}\" SET timezone = 'Asia/Shanghai'"
                if (!MigrationHelpers.execUpdate(db, setTzSql)) {
                    return false
                }
            case None =>
                return false
        }

        // 将 timestamp without time zone 列转为 timestamptz。
        // USING ... AT TIME ZONE 'America/Los_Angeles' 表示：把原先按 Los_Angeles 写入的
        // naive 值解释为该时区的本地时间，再转换为真实时刻存储。
        let alterSql = """
            ALTER TABLE user_tokens
                ALTER COLUMN created_at   TYPE timestamptz USING created_at   AT TIME ZONE 'America/Los_Angeles',
                ALTER COLUMN last_used_at TYPE timestamptz USING last_used_at AT TIME ZONE 'America/Los_Angeles',
                ALTER COLUMN revoked_at   TYPE timestamptz USING revoked_at   AT TIME ZONE 'America/Los_Angeles',
                ALTER COLUMN expires_at   TYPE timestamptz USING expires_at   AT TIME ZONE 'America/Los_Angeles'
        """
        if (!MigrationHelpers.execUpdate(db, alterSql)) {
            return false
        }

        return true
    }
}
