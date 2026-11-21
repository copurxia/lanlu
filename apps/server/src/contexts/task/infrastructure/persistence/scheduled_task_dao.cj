package lanlu.contexts.task.infrastructure.persistence

import csorm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
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

    private static let SELECT_COLUMNS = """
        SELECT id, name, cron_expression, task_type, task_parameters, enabled,
               priority, timeout_seconds,
               to_char(last_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'), last_run_status, last_error,
               to_char(next_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
               run_count, success_count, failure_count,
               to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
               to_char(updated_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
               created_by, updated_by
        FROM scheduled_tasks
    """

    /**
     * 创建定时任务表
     */
    public static func createTable(): Bool {
        let logger = getLogger("scheduled_task_dao")
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // 检查表是否存在
                    let checkSql = "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'scheduled_tasks')"
                    let tableExists = db.rawOne<Bool>(checkSql, [], { r => r.getOrNullBool(0) ?? false }) ?? false

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
                        db.execRawSql(createTableSql)
                        logger.debug("scheduled_tasks表创建成功")

                        // 创建索引
                        createIndexes(db)
                    } else {
                        logger.debug("scheduled_tasks表已存在，跳过创建")
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("创建scheduled_tasks表失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    private static func createIndexes(db: Database): Unit {
        let logger = getLogger("scheduled_task_dao")
        let indexes = [
            ("idx_scheduled_tasks_enabled_next_run", "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_enabled_next_run ON scheduled_tasks (enabled, next_run_at)"),
            ("idx_scheduled_tasks_task_type", "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_task_type ON scheduled_tasks (task_type)"),
            ("idx_scheduled_tasks_last_run_at", "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_last_run_at ON scheduled_tasks (last_run_at)")
        ]

        for ((name, sql) in indexes) {
            try {
                db.execRawSql(sql)
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
        let params: Array<Value> = [
            vtext(data.name),
            vtext(data.cronExpression),
            vtext(data.taskType),
            if (data.taskParameters.size > 0) { vtext(data.taskParameters) } else { vnull() },
            vbool(data.enabled),
            vint(Int64(data.priority)),
            vint(Int64(data.timeoutSeconds)),
            if (data.nextRunAt.size > 0) { vtext(data.nextRunAt) } else { vnull() },
            vtext(data.createdAt),
            vtext(data.updatedAt),
            if (data.createdBy.size > 0) { vtext(data.createdBy) } else { vnull() },
            if (data.updatedBy.size > 0) { vtext(data.updatedBy) } else { vnull() }
        ]
        let sql = """
            INSERT INTO scheduled_tasks (
                name, cron_expression, task_type, task_parameters, enabled,
                priority, timeout_seconds, next_run_at,
                created_at, updated_at, created_by, updated_by
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            RETURNING id
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let idOpt = db.rawOne<Int64>(sql, params, { r => r.getInt64(0) })
                    match (idOpt) {
                        case Some(id) =>
                            data.id = id
                            logger.debug("创建定时任务成功", ("id", data.id.toString()), ("name", data.name))
                            return true
                        case None =>
                            logger.error("获取自增ID失败")
                            return false
                    }
                } catch (e: Exception) {
                    logger.error("创建定时任务失败", ("name", data.name), ("error", e.message))
                    return false
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
        let sql = "${SELECT_COLUMNS} WHERE id = $1"
        let params: Array<Value> = [vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<ScheduledTaskData>(sql, params, { row => mapRowToData(row) })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return ScheduledTaskData()
                } catch (e: Exception) {
                    logger.error("查询定时任务失败", ("id", id), ("error", e.message))
                    return ScheduledTaskData()
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

        let sql = """
            ${SELECT_COLUMNS}
            WHERE name = $1
            ORDER BY id ASC
            LIMIT 1
        """
        let params: Array<Value> = [vtext(trimmed)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<ScheduledTaskData>(sql, params, { row => mapRowToData(row) })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return ScheduledTaskData()
                } catch (e: Exception) {
                    logger.error("按名称查询定时任务失败", ("name", trimmed), ("error", e.message))
                    return ScheduledTaskData()
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
        let sql = """
            ${SELECT_COLUMNS}
            WHERE enabled = TRUE
            ORDER BY priority ASC, id ASC
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<ScheduledTaskData>(sql, [], { row => mapRowToData(row) })
                } catch (e: Exception) {
                    logger.error("查询启用的定时任务失败", ("error", e.message))
                    return Array<ScheduledTaskData>()
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
        let sql = """
            ${SELECT_COLUMNS}
            WHERE enabled = TRUE
              AND next_run_at IS NOT NULL
              AND next_run_at <= NOW()
            ORDER BY scheduled_tasks.next_run_at ASC, priority ASC
            LIMIT 100
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<ScheduledTaskData>(sql, [], { row => mapRowToData(row) })
                } catch (e: Exception) {
                    logger.error("查询到期定时任务失败", ("error", e.message))
                    return Array<ScheduledTaskData>()
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
        let sql = """
            ${SELECT_COLUMNS}
            ORDER BY id DESC
            LIMIT $1 OFFSET $2
        """
        let params: Array<Value> = [vint(Int64(limit)), vint(Int64(offset))]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<ScheduledTaskData>(sql, params, { row => mapRowToData(row) })
                } catch (e: Exception) {
                    logger.error("分页查询定时任务失败", ("error", e.message))
                    return Array<ScheduledTaskData>()
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
        let sql = "SELECT COUNT(*) FROM scheduled_tasks"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let count = db.rawOne<Int64>(sql, [], { r => r.getOrNullInt64(0) ?? 0 }) ?? 0
                    return Int32(count)
                } catch (e: Exception) {
                    logger.error("获取定时任务总数失败", ("error", e.message))
                    return 0
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
        let params: Array<Value> = [
            vtext(data.name),
            vtext(data.cronExpression),
            vtext(data.taskType),
            if (data.taskParameters.size > 0) { vtext(data.taskParameters) } else { vnull() },
            vbool(data.enabled),
            vint(Int64(data.priority)),
            vint(Int64(data.timeoutSeconds)),
            if (data.nextRunAt.size > 0) { vtext(data.nextRunAt) } else { vnull() },
            vtext(data.updatedAt),
            if (data.updatedBy.size > 0) { vtext(data.updatedBy) } else { vnull() },
            vint(data.id)
        ]
        let sql = """
            UPDATE scheduled_tasks SET
                name = $1, cron_expression = $2, task_type = $3, task_parameters = $4,
                enabled = $5, priority = $6, timeout_seconds = $7,
                next_run_at = $8, updated_at = $9, updated_by = $10
            WHERE id = $11
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    logger.debug("更新定时任务成功", ("id", data.id))
                    return true
                } catch (e: Exception) {
                    logger.error("更新定时任务失败", ("id", data.id), ("error", e.message))
                    return false
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
        let sql = "DELETE FROM scheduled_tasks WHERE id = $1"
        let params: Array<Value> = [vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    logger.debug("删除定时任务成功", ("id", id))
                    return true
                } catch (e: Exception) {
                    logger.error("删除定时任务失败", ("id", id), ("error", e.message))
                    return false
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

        let sql = "DELETE FROM scheduled_tasks WHERE name = $1"
        let params: Array<Value> = [vtext(trimmed)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    if (affected > 0) {
                        logger.debug("按名称删除定时任务成功", [("name", trimmed), ("affected", affected.toString())])
                        return true
                    }
                    return false
                } catch (e: Exception) {
                    logger.error("按名称删除定时任务失败", ("name", trimmed), ("error", e.message))
                    return false
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
        let sql = """
            UPDATE scheduled_tasks SET enabled = $1, updated_at = NOW()
            WHERE id = $2
        """
        let params: Array<Value> = [vbool(enabled), vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    logger.debug("更新定时任务启用状态", ("id", id), ("enabled", enabled.toString()))
                    return true
                } catch (e: Exception) {
                    logger.error("更新定时任务启用状态失败", ("id", id), ("error", e.message))
                    return false
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
        let status = if (success) { "success" } else { "failed" }
        let successIncrement = if (success) { 1 } else { 0 }
        let failureIncrement = if (success) { 0 } else { 1 }

        let params: Array<Value> = [
            vtext(status),
            if (errorMessage.size > 0) { vtext(errorMessage) } else { vnull() },
            vint(Int64(successIncrement)),
            vint(Int64(failureIncrement)),
            vint(id)
        ]
        let sql = """
            UPDATE scheduled_tasks SET
                last_run_at = NOW(),
                last_run_status = $1,
                last_error = $2,
                run_count = run_count + 1,
                success_count = success_count + $3,
                failure_count = failure_count + $4,
                updated_at = NOW()
            WHERE id = $5
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    logger.debug("更新定时任务执行结果", ("id", id), ("success", success.toString()))
                    return true
                } catch (e: Exception) {
                    logger.error("更新定时任务执行结果失败", ("id", id), ("error", e.message))
                    return false
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
        let sql = """
            UPDATE scheduled_tasks SET next_run_at = $1, updated_at = NOW()
            WHERE id = $2
        """
        let params: Array<Value> = [
            if (nextRunAt.size > 0) { vtext(nextRunAt) } else { vnull() },
            vint(id)
        ]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    logger.debug("更新下次执行时间", ("id", id), ("next_run_at", nextRunAt))
                    return true
                } catch (e: Exception) {
                    logger.error("更新下次执行时间失败", ("id", id), ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 从Row映射到ScheduledTaskData
     */
    private static func mapRowToData(row: Row): ScheduledTaskData {
        let data = ScheduledTaskData()
        data.id = row.getOrNullInt64(0) ?? 0
        data.name = row.getOrNullText(1) ?? ""
        data.cronExpression = row.getOrNullText(2) ?? ""
        data.taskType = row.getOrNullText(3) ?? ""
        data.taskParameters = row.getOrNullText(4) ?? ""
        data.enabled = row.getOrNullBool(5) ?? true
        data.priority = row.getOrNullInt32(6) ?? 50
        data.timeoutSeconds = row.getOrNullInt32(7) ?? 3600
        data.lastRunAt = row.getOrNullText(8) ?? ""
        data.lastRunStatus = row.getOrNullText(9) ?? ""
        data.lastError = row.getOrNullText(10) ?? ""
        data.nextRunAt = row.getOrNullText(11) ?? ""
        data.runCount = row.getOrNullInt32(12) ?? 0
        data.successCount = row.getOrNullInt32(13) ?? 0
        data.failureCount = row.getOrNullInt32(14) ?? 0
        data.createdAt = row.getOrNullText(15) ?? ""
        data.updatedAt = row.getOrNullText(16) ?? ""
        data.createdBy = row.getOrNullText(17) ?? ""
        data.updatedBy = row.getOrNullText(18) ?? ""
        return data
    }
}