package lanlu.contexts.task.infrastructure.persistence

import ace_orm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
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
        try {
            // 检查表是否存在
            let rows = DatabaseConfig.driver().query("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'scheduled_tasks')", [])
            var tableExists = false
            if (rows.size > 0) {
                let r = rows[0]
                tableExists = r.getBool("exists")
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

                DatabaseConfig.driver().exec(createTableSql, [])
                logger.debug("scheduled_tasks表创建成功")

                // 创建索引
                createIndexes()
            } else {
                logger.debug("scheduled_tasks表已存在，跳过创建")
            }
            return true
        } catch (e: Exception) {
            logger.error("创建scheduled_tasks表失败", ("error", e.message))
            return false
        }
    }

    private static func createIndexes(): Unit {
        let logger = getLogger("scheduled_task_dao")
        let indexes = [
            ("idx_scheduled_tasks_enabled_next_run", "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_enabled_next_run ON scheduled_tasks (enabled, next_run_at)"),
            ("idx_scheduled_tasks_task_type", "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_task_type ON scheduled_tasks (task_type)"),
            ("idx_scheduled_tasks_last_run_at", "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_last_run_at ON scheduled_tasks (last_run_at)")
        ]

        for ((name, sql) in indexes) {
            try {
                DatabaseConfig.driver().exec(sql, [])
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
        try {
            let rows = DatabaseConfig.driver().query("""
                INSERT INTO scheduled_tasks (
                    name, cron_expression, task_type, task_parameters, enabled,
                    priority, timeout_seconds, next_run_at,
                    created_at, updated_at, created_by, updated_by
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                RETURNING id
            """, [
                DbText(data.name),
                DbText(data.cronExpression),
                DbText(data.taskType),
                if (data.taskParameters.size > 0) { DbText(data.taskParameters) } else { DbNull },
                DbBool(data.enabled),
                DbInt(Int64(data.priority)),
                DbInt(Int64(data.timeoutSeconds)),
                if (data.nextRunAt.size > 0) { DbText(data.nextRunAt) } else { DbNull },
                DbText(data.createdAt),
                DbText(data.updatedAt),
                if (data.createdBy.size > 0) { DbText(data.createdBy) } else { DbNull },
                if (data.updatedBy.size > 0) { DbText(data.updatedBy) } else { DbNull }
            ])
            if (rows.size > 0) {
                data.id = rows[0].getInt("id")
                logger.debug("创建定时任务成功", ("id", data.id.toString()), ("name", data.name))
                return true
            } else {
                logger.error("获取自增ID失败")
                return false
            }
        } catch (e: Exception) {
            logger.error("创建定时任务失败", ("name", data.name), ("error", e.message))
            return false
        }
    }

    /**
     * 根据ID获取定时任务
     */
    public static func getById(id: Int64): ScheduledTaskData {
        let logger = getLogger("scheduled_task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                       priority, timeout_seconds,
                       to_char(last_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'), last_run_status, last_error,
                       to_char(next_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       run_count, success_count, failure_count,
                       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       to_char(updated_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       created_by, updated_by
                FROM scheduled_tasks WHERE id = $1
            """, [DbInt(id)])
            if (rows.size > 0) {
                return mapRowToData(rows[0])
            } else {
                return ScheduledTaskData()
            }
        } catch (e: Exception) {
            logger.error("查询定时任务失败", ("id", id), ("error", e.message))
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

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                       priority, timeout_seconds,
                       to_char(last_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'), last_run_status, last_error,
                       to_char(next_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       run_count, success_count, failure_count,
                       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       to_char(updated_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       created_by, updated_by
                FROM scheduled_tasks
                WHERE name = $1
                ORDER BY id ASC
                LIMIT 1
            """, [DbText(trimmed)])
            if (rows.size > 0) {
                return mapRowToData(rows[0])
            } else {
                return ScheduledTaskData()
            }
        } catch (e: Exception) {
            logger.error("按名称查询定时任务失败", ("name", trimmed), ("error", e.message))
            return ScheduledTaskData()
        }
    }

    /**
     * 获取所有启用的定时任务
     */
    public static func getEnabledTasks(): Array<ScheduledTaskData> {
        let logger = getLogger("scheduled_task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                       priority, timeout_seconds,
                       to_char(last_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'), last_run_status, last_error,
                       to_char(next_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       run_count, success_count, failure_count,
                       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       to_char(updated_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       created_by, updated_by
                FROM scheduled_tasks
                WHERE enabled = TRUE
                ORDER BY priority ASC, id ASC
            """, [])
            return collectTasks(rows)
        } catch (e: Exception) {
            logger.error("查询启用的定时任务失败", ("error", e.message))
            return Array<ScheduledTaskData>()
        }
    }

    /**
     * 获取到期的定时任务（next_run_at <= NOW()）
     */
    public static func getDueTasks(): Array<ScheduledTaskData> {
        let logger = getLogger("scheduled_task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                       priority, timeout_seconds,
                       to_char(last_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'), last_run_status, last_error,
                       to_char(next_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       run_count, success_count, failure_count,
                       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       to_char(updated_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       created_by, updated_by
                FROM scheduled_tasks
                WHERE enabled = TRUE
                  AND next_run_at IS NOT NULL
                  AND next_run_at <= NOW()
                ORDER BY scheduled_tasks.next_run_at ASC, priority ASC
                LIMIT 100
            """, [])
            return collectTasks(rows)
        } catch (e: Exception) {
            logger.error("查询到期定时任务失败", ("error", e.message))
            return Array<ScheduledTaskData>()
        }
    }

    /**
     * 分页获取定时任务
     */
    public static func getWithPagination(offset: Int32, limit: Int32): Array<ScheduledTaskData> {
        let logger = getLogger("scheduled_task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, cron_expression, task_type, task_parameters, enabled,
                       priority, timeout_seconds,
                       to_char(last_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'), last_run_status, last_error,
                       to_char(next_run_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       run_count, success_count, failure_count,
                       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       to_char(updated_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'),
                       created_by, updated_by
                FROM scheduled_tasks
                ORDER BY id DESC
                LIMIT $1 OFFSET $2
            """, [DbInt(Int64(limit)), DbInt(Int64(offset))])
            return collectTasks(rows)
        } catch (e: Exception) {
            logger.error("分页查询定时任务失败", ("error", e.message))
            return Array<ScheduledTaskData>()
        }
    }

    /**
     * 获取定时任务总数
     */
    public static func getCount(): Int32 {
        let logger = getLogger("scheduled_task_dao")
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) FROM scheduled_tasks", [])
            if (rows.size > 0) {
                return Int32(rows[0].getInt("count"))
            } else {
                return 0
            }
        } catch (e: Exception) {
            logger.error("获取定时任务总数失败", ("error", e.message))
            return 0
        }
    }

    /**
     * 更新定时任务
     */
    public static func update(data: ScheduledTaskData): Bool {
        let logger = getLogger("scheduled_task_dao")
        try {
            DatabaseConfig.driver().exec("""
                UPDATE scheduled_tasks SET
                    name = $1, cron_expression = $2, task_type = $3, task_parameters = $4,
                    enabled = $5, priority = $6, timeout_seconds = $7,
                    next_run_at = $8, updated_at = $9, updated_by = $10
                WHERE id = $11
            """, [
                DbText(data.name),
                DbText(data.cronExpression),
                DbText(data.taskType),
                if (data.taskParameters.size > 0) { DbText(data.taskParameters) } else { DbNull },
                DbBool(data.enabled),
                DbInt(Int64(data.priority)),
                DbInt(Int64(data.timeoutSeconds)),
                if (data.nextRunAt.size > 0) { DbText(data.nextRunAt) } else { DbNull },
                DbText(data.updatedAt),
                if (data.updatedBy.size > 0) { DbText(data.updatedBy) } else { DbNull },
                DbInt(data.id)
            ])
            logger.debug("更新定时任务成功", ("id", data.id))
            return true
        } catch (e: Exception) {
            logger.error("更新定时任务失败", ("id", data.id), ("error", e.message))
            return false
        }
    }

    /**
     * 删除定时任务
     */
    public static func delete(id: Int64): Bool {
        let logger = getLogger("scheduled_task_dao")
        try {
            DatabaseConfig.driver().exec("DELETE FROM scheduled_tasks WHERE id = $1", [DbInt(id)])
            logger.debug("删除定时任务成功", ("id", id))
            return true
        } catch (e: Exception) {
            logger.error("删除定时任务失败", ("id", id), ("error", e.message))
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

        try {
            let affected = DatabaseConfig.driver().exec("DELETE FROM scheduled_tasks WHERE name = $1", [DbText(trimmed)])
            if (affected > 0) {
                logger.debug("按名称删除定时任务成功", [("name", trimmed), ("affected", affected.toString())])
                return true
            }
            return false
        } catch (e: Exception) {
            logger.error("按名称删除定时任务失败", ("name", trimmed), ("error", e.message))
            return false
        }
    }

    /**
     * 设置启用/禁用状态
     */
    public static func setEnabled(id: Int64, enabled: Bool): Bool {
        let logger = getLogger("scheduled_task_dao")
        try {
            DatabaseConfig.driver().exec("""
                UPDATE scheduled_tasks SET enabled = $1, updated_at = NOW()
                WHERE id = $2
            """, [DbBool(enabled), DbInt(id)])
            logger.debug("更新定时任务启用状态", ("id", id), ("enabled", enabled.toString()))
            return true
        } catch (e: Exception) {
            logger.error("更新定时任务启用状态失败", ("id", id), ("error", e.message))
            return false
        }
    }

    /**
     * 更新任务执行结果
     */
    public static func updateRunResult(id: Int64, success: Bool, errorMessage: String): Bool {
        let logger = getLogger("scheduled_task_dao")
        try {
            let status = if (success) { "success" } else { "failed" }
            let successIncrement = if (success) { 1 } else { 0 }
            let failureIncrement = if (success) { 0 } else { 1 }

            DatabaseConfig.driver().exec("""
                UPDATE scheduled_tasks SET
                    last_run_at = NOW(),
                    last_run_status = $1,
                    last_error = $2,
                    run_count = run_count + 1,
                    success_count = success_count + $3,
                    failure_count = failure_count + $4,
                    updated_at = NOW()
                WHERE id = $5
            """, [
                DbText(status),
                if (errorMessage.size > 0) { DbText(errorMessage) } else { DbNull },
                DbInt(Int64(successIncrement)),
                DbInt(Int64(failureIncrement)),
                DbInt(id)
            ])
            logger.debug("更新定时任务执行结果", ("id", id), ("success", success.toString()))
            return true
        } catch (e: Exception) {
            logger.error("更新定时任务执行结果失败", ("id", id), ("error", e.message))
            return false
        }
    }

    /**
     * 更新下次执行时间
     */
    public static func updateNextRunAt(id: Int64, nextRunAt: String): Bool {
        let logger = getLogger("scheduled_task_dao")
        try {
            DatabaseConfig.driver().exec("""
                UPDATE scheduled_tasks SET next_run_at = $1, updated_at = NOW()
                WHERE id = $2
            """, [
                if (nextRunAt.size > 0) { DbText(nextRunAt) } else { DbNull },
                DbInt(id)
            ])
            logger.debug("更新下次执行时间", ("id", id), ("next_run_at", nextRunAt))
            return true
        } catch (e: Exception) {
            logger.error("更新下次执行时间失败", ("id", id), ("error", e.message))
            return false
        }
    }

    /**
     * 从Row映射到ScheduledTaskData
     */
    private static func mapRowToData(r: Row): ScheduledTaskData {
        let data = ScheduledTaskData()
        data.id = r.getInt("id")
        data.name = r.getText("name")
        data.cronExpression = r.getText("cron_expression")
        data.taskType = r.getText("task_type")
        data.taskParameters = r.getText("task_parameters")
        data.enabled = r.getBool("enabled")
        data.priority = Int32(r.getInt("priority"))
        data.timeoutSeconds = Int32(r.getInt("timeout_seconds"))
        data.lastRunAt = r.getText("last_run_at")
        data.lastRunStatus = r.getText("last_run_status")
        data.lastError = r.getText("last_error")
        data.nextRunAt = r.getText("next_run_at")
        data.runCount = Int32(r.getInt("run_count"))
        data.successCount = Int32(r.getInt("success_count"))
        data.failureCount = Int32(r.getInt("failure_count"))
        data.createdAt = r.getText("created_at")
        data.updatedAt = r.getText("updated_at")
        data.createdBy = r.getText("created_by")
        data.updatedBy = r.getText("updated_by")
        return data
    }

    /**
     * 收集查询结果中的所有任务
     */
    private static func collectTasks(rows: Array<Row>): Array<ScheduledTaskData> {
        let logger = getLogger("scheduled_task_dao")
        try {
            let taskList = ArrayList<ScheduledTaskData>()
            for (r in rows) {
                taskList.add(mapRowToData(r))
            }
            return taskList.toArray()
        } catch (e: Exception) {
            logger.error("收集任务结果失败", ("error", e.message))
            return Array<ScheduledTaskData>()
        }
    }
}