package lanlu.dao

import std.database.sql.*
import lanlu.config.*
import lanlu.utils.*
import std.collection.*
import stdx.log.*

/**
 * 定时任务数据结构（DAO内部使用）
 */
public class ScheduledTaskData {
    public var id: Int64 = 0
    public var name: String = ""
    public var cronExpression: String = ""
    public var taskType: String = ""
    public var taskParameters: String = ""
    public var enabled: Bool = true
    public var priority: Int32 = 50
    public var timeoutSeconds: Int32 = 3600

    public var lastRunAt: String = ""
    public var lastRunStatus: String = ""
    public var lastError: String = ""
    public var nextRunAt: String = ""

    public var runCount: Int32 = 0
    public var successCount: Int32 = 0
    public var failureCount: Int32 = 0

    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var createdBy: String = ""
    public var updatedBy: String = ""

    public init() {}
}

/**
 * 定时任务数据访问对象 (DAO)
 * 负责处理所有与定时任务相关的数据库操作
 */
public class ScheduledTaskDao {

    /**
     * 创建定时任务表
     */
    public static func createTable(): Bool {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 检查表是否存在
                    let checkTable = conn.prepareStatement("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'scheduled_tasks')")
                    let rs = checkTable.query()
                    var tableExists = false
                    try {
                        if (rs.next()) {
                            tableExists = rs.getOrNull<Bool>(0) ?? false
                        }
                    } finally {
                        rs.close()
                        checkTable.close()
                    }

                    if (!tableExists) {
                        logger.debug("scheduled_tasks表不存在，创建新表")
                        let createTableSql = """
                            CREATE TABLE scheduled_tasks (
                                id BIGSERIAL PRIMARY KEY,
                                name VARCHAR(255) NOT NULL,
                                cron_expression VARCHAR(255) NOT NULL,
                                task_type VARCHAR(50) NOT NULL,
                                task_parameters TEXT,
                                enabled BOOLEAN NOT NULL DEFAULT TRUE,
                                priority INTEGER NOT NULL DEFAULT 50,
                                timeout_seconds INTEGER NOT NULL DEFAULT 3600,

                                last_run_at TIMESTAMPTZ NULL,
                                last_run_status VARCHAR(20) NULL,
                                last_error TEXT NULL,
                                next_run_at TIMESTAMPTZ NULL,

                                run_count INTEGER NOT NULL DEFAULT 0,
                                success_count INTEGER NOT NULL DEFAULT 0,
                                failure_count INTEGER NOT NULL DEFAULT 0,

                                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                created_by VARCHAR(100),
                                updated_by VARCHAR(100)
                            )
                        """

                        let stmt = conn.prepareStatement(createTableSql)
                        stmt.update()
                        stmt.close()
                        logger.debug("scheduled_tasks表创建成功")

                        // 创建索引
                        createIndexes(conn)
                    } else {
                        logger.debug("scheduled_tasks表已存在，跳过创建")
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("创建scheduled_tasks表失败", ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    private static func createIndexes(conn: Connection): Unit {
        let logger = getLogger("scheduled_task_dao")
        let indexes = [
            ("idx_scheduled_tasks_enabled_next_run", "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_enabled_next_run ON scheduled_tasks (enabled, next_run_at)"),
            ("idx_scheduled_tasks_task_type", "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_task_type ON scheduled_tasks (task_type)"),
            ("idx_scheduled_tasks_last_run_at", "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_last_run_at ON scheduled_tasks (last_run_at)")
        ]

        for ((name, sql) in indexes) {
            try {
                let stmt = conn.prepareStatement(sql)
                stmt.update()
                stmt.close()
                logger.debug("索引创建成功", ("index", name))
            } catch (e: Exception) {
                logger.warn("创建索引失败", ("index", name), ("error", e.message))
            }
        }
    }

    /**
     * 创建定时任务
     */
    public static func create(data: ScheduledTaskData): Bool {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO scheduled_tasks (
                            name, cron_expression, task_type, task_parameters, enabled,
                            priority, timeout_seconds, next_run_at,
                            created_at, updated_at, created_by, updated_by
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        RETURNING id
                    """)
                    try {
                        stmt.set(0, data.name)
                        stmt.set(1, data.cronExpression)
                        stmt.set(2, data.taskType)
                        if (data.taskParameters.size > 0) {
                            stmt.set(3, data.taskParameters)
                        } else {
                            stmt.setNull(3)
                        }
                        stmt.set(4, data.enabled)
                        stmt.set(5, data.priority)
                        stmt.set(6, data.timeoutSeconds)
                        if (data.nextRunAt.size > 0) {
                            stmt.set(7, data.nextRunAt)
                        } else {
                            stmt.setNull(7)
                        }
                        stmt.set(8, data.createdAt)
                        stmt.set(9, data.updatedAt)
                        if (data.createdBy.size > 0) {
                            stmt.set(10, data.createdBy)
                        } else {
                            stmt.setNull(10)
                        }
                        if (data.updatedBy.size > 0) {
                            stmt.set(11, data.updatedBy)
                        } else {
                            stmt.setNull(11)
                        }

                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                logger.debug("创建定时任务成功", ("id", data.id.toString()), ("name", data.name))
                                return true
                            } else {
                                logger.error("获取自增ID失败")
                                return false
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    logger.error("创建定时任务失败", ("name", data.name), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 根据ID获取定时任务
     */
    public static func getById(id: Int64): ScheduledTaskData {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                               priority, timeout_seconds,
                               last_run_at, last_run_status, last_error, next_run_at,
                               run_count, success_count, failure_count,
                               created_at, updated_at, created_by, updated_by
                        FROM scheduled_tasks WHERE id = ?
                    """)
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()

                        try {
                            if (rs.next()) {
                                return mapResultSetToData(rs)
                            } else {
                                return ScheduledTaskData()
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("查询定时任务失败", ("id", id), ("error", e.message))
                    return ScheduledTaskData()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return ScheduledTaskData()
        }
    }

    /**
     * 根据名称获取定时任务（name 唯一性由调用方保证）
     */
    public static func getByName(name: String): ScheduledTaskData {
        let logger = getLogger("scheduled_task_dao")
        let trimmed = name.trimAscii()
        if (trimmed.size == 0) { return ScheduledTaskData() }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                               priority, timeout_seconds,
                               last_run_at, last_run_status, last_error, next_run_at,
                               run_count, success_count, failure_count,
                               created_at, updated_at, created_by, updated_by
                        FROM scheduled_tasks
                        WHERE name = ?
                        ORDER BY id ASC
                        LIMIT 1
                    """)
                    try {
                        stmt.set(0, trimmed)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return mapResultSetToData(rs)
                            } else {
                                return ScheduledTaskData()
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("按名称查询定时任务失败", ("name", trimmed), ("error", e.message))
                    return ScheduledTaskData()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return ScheduledTaskData()
        }
    }

    /**
     * 获取所有启用的定时任务
     */
    public static func getEnabledTasks(): Array<ScheduledTaskData> {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                               priority, timeout_seconds,
                               last_run_at, last_run_status, last_error, next_run_at,
                               run_count, success_count, failure_count,
                               created_at, updated_at, created_by, updated_by
                        FROM scheduled_tasks
                        WHERE enabled = TRUE
                        ORDER BY priority ASC, id ASC
                    """)
                    try {
                        let rs = stmt.query()
                        return collectTasks(rs)
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("查询启用的定时任务失败", ("error", e.message))
                    return Array<ScheduledTaskData>()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Array<ScheduledTaskData>()
        }
    }

    /**
     * 获取到期的定时任务（next_run_at <= NOW()）
     */
    public static func getDueTasks(): Array<ScheduledTaskData> {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                               priority, timeout_seconds,
                               last_run_at, last_run_status, last_error, next_run_at,
                               run_count, success_count, failure_count,
                               created_at, updated_at, created_by, updated_by
                        FROM scheduled_tasks
                        WHERE enabled = TRUE
                          AND next_run_at IS NOT NULL
                          AND next_run_at <= NOW()
                        ORDER BY next_run_at ASC, priority ASC
                        LIMIT 100
                    """)
                    try {
                        let rs = stmt.query()
                        return collectTasks(rs)
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("查询到期定时任务失败", ("error", e.message))
                    return Array<ScheduledTaskData>()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Array<ScheduledTaskData>()
        }
    }

    /**
     * 分页获取定时任务
     */
    public static func getWithPagination(offset: Int32, limit: Int32): Array<ScheduledTaskData> {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                               priority, timeout_seconds,
                               last_run_at, last_run_status, last_error, next_run_at,
                               run_count, success_count, failure_count,
                               created_at, updated_at, created_by, updated_by
                        FROM scheduled_tasks
                        ORDER BY id DESC
                        LIMIT ? OFFSET ?
                    """)
                    try {
                        stmt.set(0, limit)
                        stmt.set(1, offset)
                        let rs = stmt.query()
                        return collectTasks(rs)
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("分页查询定时任务失败", ("error", e.message))
                    return Array<ScheduledTaskData>()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Array<ScheduledTaskData>()
        }
    }

    /**
     * 获取定时任务总数
     */
    public static func getCount(): Int32 {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM scheduled_tasks")
                    let rs = stmt.query()

                    try {
                        if (rs.next()) {
                            return rs.getOrNull<Int32>(0) ?? 0
                        } else {
                            return 0
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("获取定时任务总数失败", ("error", e.message))
                    return 0
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return 0
        }
    }

    /**
     * 更新定时任务
     */
    public static func update(data: ScheduledTaskData): Bool {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE scheduled_tasks SET
                            name = ?, cron_expression = ?, task_type = ?, task_parameters = ?,
                            enabled = ?, priority = ?, timeout_seconds = ?,
                            next_run_at = ?, updated_at = ?, updated_by = ?
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, data.name)
                        stmt.set(1, data.cronExpression)
                        stmt.set(2, data.taskType)
                        if (data.taskParameters.size > 0) {
                            stmt.set(3, data.taskParameters)
                        } else {
                            stmt.setNull(3)
                        }
                        stmt.set(4, data.enabled)
                        stmt.set(5, data.priority)
                        stmt.set(6, data.timeoutSeconds)
                        if (data.nextRunAt.size > 0) {
                            stmt.set(7, data.nextRunAt)
                        } else {
                            stmt.setNull(7)
                        }
                        stmt.set(8, data.updatedAt)
                        if (data.updatedBy.size > 0) {
                            stmt.set(9, data.updatedBy)
                        } else {
                            stmt.setNull(9)
                        }
                        stmt.set(10, data.id)

                        stmt.update()
                        logger.debug("更新定时任务成功", ("id", data.id))
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("更新定时任务失败", ("id", data.id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 删除定时任务
     */
    public static func delete(id: Int64): Bool {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("DELETE FROM scheduled_tasks WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        stmt.update()
                        logger.debug("删除定时任务成功", ("id", id))
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("删除定时任务失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 根据名称删除定时任务
     */
    public static func deleteByName(name: String): Bool {
        let logger = getLogger("scheduled_task_dao")
        let trimmed = name.trimAscii()
        if (trimmed.size == 0) { return false }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("DELETE FROM scheduled_tasks WHERE name = ?")
                    try {
                        stmt.set(0, trimmed)
                        let affected = stmt.update()
                        if (affected.rowCount > 0) {
                            logger.debug("按名称删除定时任务成功", [("name", trimmed), ("affected", affected.rowCount.toString())])
                            return true
                        }
                        return false
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("按名称删除定时任务失败", ("name", trimmed), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 设置启用/禁用状态
     */
    public static func setEnabled(id: Int64, enabled: Bool): Bool {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE scheduled_tasks SET enabled = ?, updated_at = NOW()
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, enabled)
                        stmt.set(1, id)
                        stmt.update()
                        logger.debug("更新定时任务启用状态", ("id", id), ("enabled", enabled.toString()))
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("更新定时任务启用状态失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 更新任务执行结果
     */
    public static func updateRunResult(id: Int64, success: Bool, errorMessage: String): Bool {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let status = if (success) { "success" } else { "failed" }
                    let successIncrement = if (success) { 1 } else { 0 }
                    let failureIncrement = if (success) { 0 } else { 1 }

                    let stmt = conn.prepareStatement("""
                        UPDATE scheduled_tasks SET
                            last_run_at = NOW(),
                            last_run_status = ?,
                            last_error = ?,
                            run_count = run_count + 1,
                            success_count = success_count + ?,
                            failure_count = failure_count + ?,
                            updated_at = NOW()
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, status)
                        if (errorMessage.size > 0) {
                            stmt.set(1, errorMessage)
                        } else {
                            stmt.setNull(1)
                        }
                        stmt.set(2, successIncrement)
                        stmt.set(3, failureIncrement)
                        stmt.set(4, id)

                        stmt.update()
                        logger.debug("更新定时任务执行结果", ("id", id), ("success", success.toString()))
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("更新定时任务执行结果失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 更新下次执行时间
     */
    public static func updateNextRunAt(id: Int64, nextRunAt: String): Bool {
        let logger = getLogger("scheduled_task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE scheduled_tasks SET next_run_at = ?, updated_at = NOW()
                        WHERE id = ?
                    """)
                    try {
                        if (nextRunAt.size > 0) {
                            stmt.set(0, nextRunAt)
                        } else {
                            stmt.setNull(0)
                        }
                        stmt.set(1, id)

                        stmt.update()
                        logger.debug("更新下次执行时间", ("id", id), ("next_run_at", nextRunAt))
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("更新下次执行时间失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 从ResultSet映射到ScheduledTaskData
     */
    private static func mapResultSetToData(rs: QueryResult): ScheduledTaskData {
        let data = ScheduledTaskData()
        data.id = rs.getOrNull<Int64>(0) ?? 0
        data.name = rs.getOrNull<String>(1) ?? ""
        data.cronExpression = rs.getOrNull<String>(2) ?? ""
        data.taskType = rs.getOrNull<String>(3) ?? ""
        data.taskParameters = rs.getOrNull<String>(4) ?? ""
        data.enabled = rs.getOrNull<Bool>(5) ?? true
        data.priority = rs.getOrNull<Int32>(6) ?? 50
        data.timeoutSeconds = rs.getOrNull<Int32>(7) ?? 3600
        data.lastRunAt = rs.getOrNull<String>(8) ?? ""
        data.lastRunStatus = rs.getOrNull<String>(9) ?? ""
        data.lastError = rs.getOrNull<String>(10) ?? ""
        data.nextRunAt = rs.getOrNull<String>(11) ?? ""
        data.runCount = rs.getOrNull<Int32>(12) ?? 0
        data.successCount = rs.getOrNull<Int32>(13) ?? 0
        data.failureCount = rs.getOrNull<Int32>(14) ?? 0
        data.createdAt = rs.getOrNull<String>(15) ?? ""
        data.updatedAt = rs.getOrNull<String>(16) ?? ""
        data.createdBy = rs.getOrNull<String>(17) ?? ""
        data.updatedBy = rs.getOrNull<String>(18) ?? ""
        return data
    }

    /**
     * 收集ResultSet中的所有任务
     */
    private static func collectTasks(rs: QueryResult): Array<ScheduledTaskData> {
        let logger = getLogger("scheduled_task_dao")
        var taskList = ArrayList<ScheduledTaskData>()
        try {
            while (rs.next()) {
                taskList.add(mapResultSetToData(rs))
            }
            let size = taskList.size
            if (size > 0) {
                var result = Array<ScheduledTaskData>(size, { _ => ScheduledTaskData() })
                for (i in 0..size) {
                    result[i] = taskList[i]
                }
                return result
            } else {
                return Array<ScheduledTaskData>()
            }
        } catch (e: Exception) {
            logger.error("收集任务结果失败", ("error", e.message))
            return Array<ScheduledTaskData>()
        } finally {
            try {
                rs.close()
            } catch (closeError: Exception) {
                logger.warn("关闭ResultSet失败: ${closeError.message}")
            }
        }
    }
}
