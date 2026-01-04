package lrr4cj.migrations

import std.database.sql.*

/**
 * Migration 接口 - 所有迁移必须实现此接口
 */
public interface Migration {
    /**
     * 获取版本标识符 (如 "V001")
     */
    func version(): String

    /**
     * 获取人类可读的描述
     */
    func description(): String

    /**
     * 执行迁移
     * @param conn 数据库连接（调用者管理事务）
     * @return true 如果成功，false 否则
     */
    func up(conn: Connection): Bool
}
