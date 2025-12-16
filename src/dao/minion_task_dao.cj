package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import lrr4cj.utils.*
import std.collection.*
import stdx.log.*

/**
 * Minion任务数据结构（DAO内部使用）
 */
public class MinionTaskData {
    public var id: Int64 = 0
    public var name: String = ""
    public var taskType: String = ""
    public var status: String = ""
    public var progress: Int32 = 0
    public var message: String = ""
    public var pluginNamespace: String = ""
    public var parameters: String = ""
    public var result: String = ""
    public var createdAt: String = ""
    public var startedAt: String = ""
    public var completedAt: String = ""

    public init() {}
}

/**
 * Minion任务数据访问对象 (DAO)
 * 负责处理所有与Minion任务相关的数据库操作
 */
public class MinionTaskDao {

    /**
     * 创建任务表
     */
    public static func createTable(): Bool {
        let logger = getLogger("minion_task_dao")
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 首先检查表是否存在
                    let checkTable = conn.prepareStatement("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'minion_tasks')")
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
                        logger.info("minion_tasks表不存在，创建新的minion_tasks表")
                        let createTableSql = "CREATE TABLE minion_tasks (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, task_type VARCHAR(50) NOT NULL DEFAULT 'generic', status VARCHAR(50) NOT NULL DEFAULT 'pending', progress INTEGER NOT NULL DEFAULT 0, message TEXT, plugin_namespace VARCHAR(255), parameters TEXT, result TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, started_at TIMESTAMP, completed_at TIMESTAMP)"

                        let stmt = conn.prepareStatement(createTableSql)
                        stmt.update()
                        stmt.close()
                        logger.info("minion_tasks表创建成功")
                    } else {
                        logger.info("minion_tasks表已存在，跳过创建")
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("创建minion_tasks表失败", ("error", e.message))
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
     * 创建任务
     */
    public static func createTaskData(data: MinionTaskData): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO minion_tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, started_at, completed_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id
                    """)
                    try {
                        stmt.set(0, data.name)
                        stmt.set(1, data.taskType)
                        stmt.set(2, data.status)
                        stmt.set(3, data.progress)
                        stmt.set(4, data.message)
                        stmt.set(5, data.pluginNamespace)
                        stmt.set(6, data.parameters)
                        stmt.set(7, data.result)
                        // started_at: 如果未提供则保持为NULL
                        if (data.startedAt.size > 0) {
                            stmt.set(8, data.startedAt)
                        } else {
                            stmt.setNull(8)
                        }
                        // completed_at: 如果未提供则保持为NULL
                        if (data.completedAt.size > 0) {
                            stmt.set(9, data.completedAt)
                        } else {
                            stmt.setNull(9)
                        }

                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                getLogger("minion_task_dao").info("创建任务", ("id", data.id.toString()))
                                return true
                            } else {
                                getLogger("minion_task_dao").error("获取自增ID失败")
                                return false
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("minion_task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("minion_task_dao").error("创建任务失败", ("id", data.id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("minion_task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("minion_task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 根据ID获取任务
     */
    public static func getTaskDataById(id: Int64): MinionTaskData {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result, created_at, started_at, completed_at
                        FROM minion_tasks WHERE id = ?
                    """)
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()

                        try {
                            if (rs.next()) {
                                let data = MinionTaskData()
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                data.name = rs.getOrNull<String>(1) ?? ""
                                data.taskType = rs.getOrNull<String>(2) ?? ""
                                data.status = rs.getOrNull<String>(3) ?? ""
                                data.progress = rs.getOrNull<Int32>(4) ?? 0
                                data.message = rs.getOrNull<String>(5) ?? ""
                                data.pluginNamespace = rs.getOrNull<String>(6) ?? ""
                                data.parameters = rs.getOrNull<String>(7) ?? ""
                                data.result = rs.getOrNull<String>(8) ?? ""
                                data.createdAt = rs.getOrNull<String>(9) ?? ""
                                data.startedAt = rs.getOrNull<String>(10) ?? ""
                                data.completedAt = rs.getOrNull<String>(11) ?? ""
                                return data
                            } else {
                                return MinionTaskData()
                            }
                        } finally {
                            try {
                                rs.close()
                            } catch (closeError: Exception) {
                                getLogger("minion_task_dao").warn("关闭ResultSet失败: ${closeError.message}")
                            }
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("minion_task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("minion_task_dao").error("查询任务失败", ("id", id), ("error", e.message))
                    return MinionTaskData()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("minion_task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("minion_task_dao").error("无法创建数据库连接")
                return MinionTaskData()
        }
    }

    /**
     * 更新任务状态
     */
    public static func updateTaskStatus(id: Int64, status: String, message: String, progress: Int32): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE minion_tasks SET status = ?, message = ?, progress = ?
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, status)
                        stmt.set(1, message)
                        stmt.set(2, progress)
                        stmt.set(3, id)

                        stmt.update()
                        getLogger("minion_task_dao").info("更新任务状态", ("id", id), ("status", status))
                        return true
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("minion_task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("minion_task_dao").error("更新任务状态失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("minion_task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("minion_task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 更新任务完整信息
     */
    public static func updateTaskData(data: MinionTaskData): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE minion_tasks SET
                            name = ?, task_type = ?, status = ?, progress = ?, message = ?,
                            plugin_namespace = ?, parameters = ?, result = ?,
                            started_at = ?, completed_at = ?
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, data.name)
                        stmt.set(1, data.taskType)
                        stmt.set(2, data.status)
                        stmt.set(3, data.progress)
                        stmt.set(4, data.message)
                        stmt.set(5, data.pluginNamespace)
                        stmt.set(6, data.parameters)
                        stmt.set(7, data.result)
                        // started_at: 如果为空则设置为 NULL
                        if (data.startedAt.size > 0) {
                            stmt.set(8, data.startedAt)
                        } else {
                            stmt.setNull(8)
                        }
                        // completed_at: 如果为空则设置为 NULL（在completeTask/failTask中会设置值）
                        if (data.completedAt.size > 0) {
                            stmt.set(9, data.completedAt)
                        } else {
                            stmt.setNull(9)
                        }
                        stmt.set(10, data.id)

                        stmt.update()
                        getLogger("minion_task_dao").info("更新任务", ("id", data.id))
                        return true
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("minion_task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("minion_task_dao").error("更新任务失败", ("id", data.id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("minion_task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("minion_task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 删除任务
     */
    public static func deleteTask(id: Int64): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("DELETE FROM minion_tasks WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        stmt.update()
                        getLogger("minion_task_dao").info("删除任务", ("id", id))
                        return true
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("minion_task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("minion_task_dao").error("删除任务失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("minion_task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("minion_task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 检查任务是否存在
     */
    public static func taskExists(id: Int64): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM minion_tasks WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()

                        try {
                            if (rs.next()) {
                                let count = rs.getOrNull<Int32>(0) ?? 0
                                return count > 0
                            } else {
                                return false
                            }
                        } finally {
                            try {
                                rs.close()
                            } catch (closeError: Exception) {
                                getLogger("minion_task_dao").warn("关闭ResultSet失败: ${closeError.message}")
                            }
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("minion_task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("minion_task_dao").error("检查任务存在性失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("minion_task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("minion_task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 获取任务总数
     */
    public static func getTaskCount(): Int32 {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM minion_tasks")
                    let rs = stmt.query()

                    try {
                        if (rs.next()) {
                            return rs.getOrNull<Int32>(0) ?? 0
                        } else {
                            return 0
                        }
                    } finally {
                        try {
                            rs.close()
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("minion_task_dao").warn("关闭ResultSet或PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("minion_task_dao").error("获取任务总数失败", ("error", e.message))
                    return 0
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("minion_task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("minion_task_dao").error("无法创建数据库连接")
                return 0
        }
    }

    /**
     * 分页获取任务列表
     * @param offset 偏移量
     * @param limit 每页数量
     * @return 任务数据数组
     */
    public static func getTasksWithPagination(offset: Int32, limit: Int32): Array<MinionTaskData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result, created_at, started_at, completed_at
                        FROM minion_tasks
                        ORDER BY id DESC
                        LIMIT ? OFFSET ?
                    """)
                    try {
                        stmt.set(0, limit)
                        stmt.set(1, offset)
                        let rs = stmt.query()

                        // 使用ArrayList来收集结果
                    var taskList = ArrayList<MinionTaskData>()
                    try {
                        while (rs.next()) {
                            let data = MinionTaskData()
                            data.id = rs.getOrNull<Int64>(0) ?? 0
                            data.name = rs.getOrNull<String>(1) ?? ""
                            data.taskType = rs.getOrNull<String>(2) ?? ""
                            data.status = rs.getOrNull<String>(3) ?? ""
                            data.progress = rs.getOrNull<Int32>(4) ?? 0
                            data.message = rs.getOrNull<String>(5) ?? ""
                            data.pluginNamespace = rs.getOrNull<String>(6) ?? ""
                            data.parameters = rs.getOrNull<String>(7) ?? ""
                            data.result = rs.getOrNull<String>(8) ?? ""
                            data.createdAt = rs.getOrNull<String>(9) ?? ""
                            data.startedAt = rs.getOrNull<String>(10) ?? ""
                            data.completedAt = rs.getOrNull<String>(11) ?? ""

                            taskList.add(data)
                        }
      // 转换 ArrayList 为 Array
                            let size = taskList.size
                            if (size > 0) {
                                var result = Array<MinionTaskData>(size, { _ => MinionTaskData() })
                                for (i in 0..size) {
                                    result[i] = taskList[i]
                                }
                                return result
                            } else {
                                return Array<MinionTaskData>()
                            }
                    } catch (e: Exception) {
                        getLogger("minion_task_dao").error("分页查询任务失败", ("error", e.message))
                        return Array<MinionTaskData>()
                    } finally {
                            try {
                                rs.close()
                                stmt.close()
                            } catch (closeError: Exception) {
                                getLogger("minion_task_dao").warn("关闭ResultSet或PreparedStatement失败: ${closeError.message}")
                            }
                        }
                    } catch (e: Exception) {
                        getLogger("minion_task_dao").error("分页查询任务失败", ("error", e.message))
                        return Array<MinionTaskData>()
                    }
                } catch (e: Exception) {
                    getLogger("minion_task_dao").error("分页查询任务失败", ("error", e.message))
                    return Array<MinionTaskData>()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("minion_task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("minion_task_dao").error("无法创建数据库连接")
                return Array<MinionTaskData>()
        }
    }

    /**
     * 更新任务参数
     */
    public static func updateTaskParameters(id: Int64, parameters: String): Bool {
        let logger = getLogger("minion_task_dao")
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let sql = "UPDATE minion_tasks SET parameters = ? WHERE id = ?"
                    let pstmt = conn.prepareStatement(sql)
                    pstmt.set(0, parameters)
                    pstmt.set(1, id)

                    pstmt.update()
                    logger.info("更新任务参数", ("id", id.toString()), ("parameters", parameters))

                    try {
                        pstmt.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                    }

                    return true

                } catch (e: Exception) {
                    logger.error("更新任务参数失败", ("id", id.toString()), ("error", e.message))
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
     * 更新任务类型
     */
    public static func updateTaskType(id: Int64, taskType: String): Bool {
        let logger = getLogger("minion_task_dao")
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let sql = "UPDATE minion_tasks SET task_type = ? WHERE id = ?"
                    let pstmt = conn.prepareStatement(sql)
                    pstmt.set(0, taskType)
                    pstmt.set(1, id)

                    let _ = pstmt.update()
                    try {
                        pstmt.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("更新任务类型失败", ("id", id.toString()), ("error", e.message))
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
     * 更新任务的插件命名空间
     */
    public static func updateTaskPluginNamespace(id: Int64, pluginNamespace: String): Bool {
        let logger = getLogger("minion_task_dao")
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let sql = "UPDATE minion_tasks SET plugin_namespace = ? WHERE id = ?"
                    let pstmt = conn.prepareStatement(sql)
                    pstmt.set(0, pluginNamespace)
                    pstmt.set(1, id)
                    let _ = pstmt.update()
                    try {
                        pstmt.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("更新任务插件命名空间失败", ("id", id.toString()), ("error", e.message))
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
     * 恢复非终态任务（服务重启时调用）
     * 将running状态的任务标记为failed，因为进程已重启，这些任务未真正完成
     */
    public static func recoverOrphanedTasks(): Int64 {
        let logger = getLogger("minion_task_dao")
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 更新所有非终态任务为失败状态
                    let updateSql = """
                        UPDATE minion_tasks
                        SET status = 'failed',
                            message = '服务端重启，任务未完成',
                            progress = 0,
                            completed_at = CURRENT_TIMESTAMP
                        WHERE status NOT IN ('completed', 'failed', 'stopped')
                    """
                    let stmt = conn.prepareStatement(updateSql)
                    try {
                        let updateResult = stmt.update()
                        let rowCount = updateResult.rowCount
                        logger.info("恢复孤儿任务完成", [("count", rowCount.toString())])
                        return rowCount
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    logger.error("恢复孤儿任务失败", ("error", e.message))
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
     * 领取一个待执行任务（原子地将pending置为running）
     */
    public static func claimNextPendingTask(): Option<MinionTaskData> {
        let logger = getLogger("minion_task_dao")
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 使用单条UPDATE + 子查询实现原子领取
                    let stmt = conn.prepareStatement("""
                        UPDATE minion_tasks
                        SET status = 'running',
                            message = '任务已启动',
                            progress = 0,
                            started_at = CURRENT_TIMESTAMP
                        WHERE id = (
                            SELECT id FROM minion_tasks
                            WHERE status = 'pending'
                            ORDER BY id
                            LIMIT 1
                        )
                        AND status = 'pending'
                        RETURNING id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                                  created_at, started_at, completed_at
                    """)

                    let rs = stmt.query()
                    try {
                        if (rs.next()) {
                            let data = MinionTaskData()
                            data.id = rs.getOrNull<Int64>(0) ?? 0
                            data.name = rs.getOrNull<String>(1) ?? ""
                            data.taskType = rs.getOrNull<String>(2) ?? ""
                            data.status = rs.getOrNull<String>(3) ?? ""
                            data.progress = rs.getOrNull<Int32>(4) ?? 0
                            data.message = rs.getOrNull<String>(5) ?? ""
                            data.pluginNamespace = rs.getOrNull<String>(6) ?? ""
                            data.parameters = rs.getOrNull<String>(7) ?? ""
                            data.result = rs.getOrNull<String>(8) ?? ""
                            data.createdAt = rs.getOrNull<String>(9) ?? ""
                            data.startedAt = rs.getOrNull<String>(10) ?? ""
                            data.completedAt = rs.getOrNull<String>(11) ?? ""
                            return Option<MinionTaskData>.Some(data)
                        }
                        return Option<MinionTaskData>.None
                    } finally {
                        try {
                            rs.close()
                            stmt.close()
                        } catch (closeError: Exception) {
                            logger.warn("关闭ResultSet或PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    logger.error("领取待执行任务失败", ("error", e.message))
                    return Option<MinionTaskData>.None
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Option<MinionTaskData>.None
        }
    }
}
