package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import lrr4cj.utils.*
import std.collection.*
import stdx.log.*

/**
 * 任务数据结构（DAO内部使用）
 */
public class TaskData {
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
    public var priority: Int32 = 50
    public var groupId: String = ""
    public var timeoutAt: String = ""
    public var triggerSource: String = ""
    public var waitForTaskId: Int64 = 0  // 条件驱动：等待指定任务完成后才能执行

    public init() {}
}

/**
 * 任务数据访问对象 (DAO)
 * 负责处理所有与任务相关的数据库操作
 */
public class TaskDao {
    // 注意：表创建已由迁移系统处理，createTable() 方法已移除

    /**
     * 创建任务（含扩展字段）
     */
    public static func createTaskData(data: TaskData): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, started_at, completed_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id
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
                        stmt.set(8, data.priority)
                        if (data.groupId.size > 0) {
                            stmt.set(9, data.groupId)
                        } else {
                            stmt.setNull(9)
                        }
                        if (data.timeoutAt.size > 0) {
                            stmt.set(10, data.timeoutAt)
                        } else {
                            stmt.setNull(10)
                        }
                        if (data.triggerSource.size > 0) {
                            stmt.set(11, data.triggerSource)
                        } else {
                            stmt.setNull(11)
                        }
                        if (data.startedAt.size > 0) {
                            stmt.set(12, data.startedAt)
                        } else {
                            stmt.setNull(12)
                        }
                        if (data.completedAt.size > 0) {
                            stmt.set(13, data.completedAt)
                        } else {
                            stmt.setNull(13)
                        }

                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                getLogger("task_dao").info("创建任务", ("id", data.id.toString()))
                                return true
                            } else {
                                getLogger("task_dao").error("获取自增ID失败")
                                return false
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("创建任务失败", ("id", data.id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("task_dao").warn("释放连接失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 创建任务（完整版，单次数据库操作）
     * 用于减少数据库连接次数，一次性设置所有字段
     */
    public static func createTaskDataFull(
        name: String,
        taskType: String,
        status: String,
        progress: Int32,
        message: String,
        parameters: String,
        priority: Int32,
        triggerSource: String
    ): Option<Int64> {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, started_at, completed_at)
                        VALUES (?, ?, ?, ?, ?, '', ?, '', ?, NULL, NULL, ?, NULL, NULL) RETURNING id
                    """)
                    try {
                        stmt.set(0, name)
                        stmt.set(1, taskType)
                        stmt.set(2, status)
                        stmt.set(3, progress)
                        stmt.set(4, message)
                        stmt.set(5, parameters)
                        stmt.set(6, priority)
                        stmt.set(7, triggerSource)

                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let id = rs.getOrNull<Int64>(0) ?? 0
                                logger.debug("创建完整任务", ("id", id.toString()))
                                return Some(id)
                            }
                            return None
                        } finally {
                            rs.close()
                        }
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("创建完整任务失败", ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法创建数据库连接")
                return None
        }
    }

    /**
     * 根据ID获取任务
     */
    public static func getTaskDataById(id: Int64): TaskData {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                               priority, group_id, timeout_at, trigger_source,
                               created_at, started_at, completed_at
                        FROM tasks WHERE id = ?
                    """)
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()

                        try {
                            if (rs.next()) {
                                let data = TaskData()
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                data.name = rs.getOrNull<String>(1) ?? ""
                                data.taskType = rs.getOrNull<String>(2) ?? ""
                                data.status = rs.getOrNull<String>(3) ?? ""
                                data.progress = rs.getOrNull<Int32>(4) ?? 0
                                data.message = rs.getOrNull<String>(5) ?? ""
                                data.pluginNamespace = rs.getOrNull<String>(6) ?? ""
                                data.parameters = rs.getOrNull<String>(7) ?? ""
                                data.result = rs.getOrNull<String>(8) ?? ""
                                data.priority = rs.getOrNull<Int32>(9) ?? 50
                                data.groupId = rs.getOrNull<String>(10) ?? ""
                                data.timeoutAt = rs.getOrNull<String>(11) ?? ""
                                data.triggerSource = rs.getOrNull<String>(12) ?? ""
                                data.createdAt = rs.getOrNull<String>(13) ?? ""
                                data.startedAt = rs.getOrNull<String>(14) ?? ""
                                data.completedAt = rs.getOrNull<String>(15) ?? ""
                                return data
                            } else {
                                return TaskData()
                            }
                        } finally {
                            try {
                                rs.close()
                            } catch (closeError: Exception) {
                                getLogger("task_dao").warn("关闭ResultSet失败: ${closeError.message}")
                            }
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("查询任务失败", ("id", id), ("error", e.message))
                    return TaskData()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("task_dao").error("无法创建数据库连接")
                return TaskData()
        }
    }

    /**
     * 更新任务状态
     */
    public static func updateTaskStatus(id: Int64, status: String, message: String, progress: Int32): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks SET status = ?, message = ?, progress = ?
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, status)
                        stmt.set(1, message)
                        stmt.set(2, progress)
                        stmt.set(3, id)

                        stmt.update()
                        getLogger("task_dao").info("更新任务状态", ("id", id), ("status", status))
                        return true
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("更新任务状态失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 更新任务完整信息
     */
    public static func updateTaskData(data: TaskData): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks SET
                            name = ?, task_type = ?, status = ?, progress = ?, message = ?,
                            plugin_namespace = ?, parameters = ?, result = ?, priority = ?, group_id = ?,
                            timeout_at = ?, trigger_source = ?, started_at = ?, completed_at = ?
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
                        stmt.set(8, data.priority)
                        if (data.groupId.size > 0) {
                            stmt.set(9, data.groupId)
                        } else {
                            stmt.setNull(9)
                        }
                        if (data.timeoutAt.size > 0) {
                            stmt.set(10, data.timeoutAt)
                        } else {
                            stmt.setNull(10)
                        }
                        if (data.triggerSource.size > 0) {
                            stmt.set(11, data.triggerSource)
                        } else {
                            stmt.setNull(11)
                        }
                        if (data.startedAt.size > 0) {
                            stmt.set(12, data.startedAt)
                        } else {
                            stmt.setNull(12)
                        }
                        if (data.completedAt.size > 0) {
                            stmt.set(13, data.completedAt)
                        } else {
                            stmt.setNull(13)
                        }
                        stmt.set(14, data.id)

                        stmt.update()
                        getLogger("task_dao").info("更新任务", ("id", data.id))
                        return true
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("更新任务失败", ("id", data.id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 删除任务
     */
    public static func deleteTask(id: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("DELETE FROM tasks WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        stmt.update()
                        getLogger("task_dao").info("删除任务", ("id", id))
                        return true
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("删除任务失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 检查任务是否存在
     */
    public static func taskExists(id: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM tasks WHERE id = ?")
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
                                getLogger("task_dao").warn("关闭ResultSet失败: ${closeError.message}")
                            }
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("检查任务存在性失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 获取任务总数
     */
    public static func getTaskCount(): Int32 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM tasks")
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
                            getLogger("task_dao").warn("关闭ResultSet或PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("获取任务总数失败", ("error", e.message))
                    return 0
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("task_dao").error("无法创建数据库连接")
                return 0
        }
    }

    /**
     * 分页获取任务列表
     * @param offset 偏移量
     * @param limit 每页数量
     * @return 任务数据数组
     */
    public static func getTasksWithPagination(offset: Int32, limit: Int32): Array<TaskData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, created_at, started_at, completed_at
                        FROM tasks
                        ORDER BY id DESC
                        LIMIT ? OFFSET ?
                    """)
                    try {
                        stmt.set(0, limit)
                        stmt.set(1, offset)
                        let rs = stmt.query()

                        // 使用ArrayList来收集结果
                    var taskList = ArrayList<TaskData>()
                    try {
                        while (rs.next()) {
                            let data = TaskData()
                            data.id = rs.getOrNull<Int64>(0) ?? 0
                            data.name = rs.getOrNull<String>(1) ?? ""
                            data.taskType = rs.getOrNull<String>(2) ?? ""
                            data.status = rs.getOrNull<String>(3) ?? ""
                            data.progress = rs.getOrNull<Int32>(4) ?? 0
                            data.message = rs.getOrNull<String>(5) ?? ""
                            data.pluginNamespace = rs.getOrNull<String>(6) ?? ""
                            data.parameters = rs.getOrNull<String>(7) ?? ""
                            data.result = rs.getOrNull<String>(8) ?? ""
                            data.priority = rs.getOrNull<Int32>(9) ?? 50
                            data.groupId = rs.getOrNull<String>(10) ?? ""
                            data.timeoutAt = rs.getOrNull<String>(11) ?? ""
                            data.triggerSource = rs.getOrNull<String>(12) ?? ""
                            data.createdAt = rs.getOrNull<String>(13) ?? ""
                            data.startedAt = rs.getOrNull<String>(14) ?? ""
                            data.completedAt = rs.getOrNull<String>(15) ?? ""

                            taskList.add(data)
                        }
      // 转换 ArrayList 为 Array
                            let size = taskList.size
                            if (size > 0) {
                                var result = Array<TaskData>(size, { _ => TaskData() })
                                for (i in 0..size) {
                                    result[i] = taskList[i]
                                }
                                return result
                            } else {
                                return Array<TaskData>()
                            }
                    } catch (e: Exception) {
                        getLogger("task_dao").error("分页查询任务失败", ("error", e.message))
                        return Array<TaskData>()
                    } finally {
                            try {
                                rs.close()
                                stmt.close()
                            } catch (closeError: Exception) {
                                getLogger("task_dao").warn("关闭ResultSet或PreparedStatement失败: ${closeError.message}")
                            }
                        }
                    } catch (e: Exception) {
                        getLogger("task_dao").error("分页查询任务失败", ("error", e.message))
                        return Array<TaskData>()
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("分页查询任务失败", ("error", e.message))
                    return Array<TaskData>()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("task_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("task_dao").error("无法创建数据库连接")
                return Array<TaskData>()
        }
    }

    /**
     * 更新任务参数
     */
    public static func updateTaskParameters(id: Int64, parameters: String): Bool {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let sql = "UPDATE tasks SET parameters = ? WHERE id = ?"
                    let pstmt = conn.prepareStatement(sql)
                    pstmt.set(0, parameters)
                    pstmt.set(1, id)

                    pstmt.update()
                    logger.debug("更新任务参数", ("id", id.toString()), ("parameters", parameters))

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
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let sql = "UPDATE tasks SET task_type = ? WHERE id = ?"
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
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let sql = "UPDATE tasks SET plugin_namespace = ? WHERE id = ?"
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
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 更新所有非终态任务为失败状态
                    let updateSql = """
                        UPDATE tasks
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
                        logger.debug("恢复孤儿任务完成", [("count", rowCount.toString())])
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
     * 检查最近时间内是否存在指定类型和触发源的任务（防重复）
     */
    public static func hasRecentTask(taskType: String, triggerSource: String, withinSeconds: Int32): Bool {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let sql = """
                        SELECT COUNT(*) FROM tasks
                        WHERE task_type = ?
                        AND trigger_source = ?
                        AND created_at >= NOW() - INTERVAL '${withinSeconds} seconds'
                    """
                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, taskType)
                        stmt.set(1, triggerSource)
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
                                logger.warn("关闭ResultSet失败: ${closeError.message}")
                            }
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    logger.error("检查最近任务失败", ("error", e.message))
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
     * 按 trigger_source 查询任务
     */
    public static func getTasksByTriggerSource(triggerSource: String, limit: Int32): Array<TaskData> {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                               priority, group_id, timeout_at, trigger_source,
                               created_at, started_at, completed_at
                        FROM tasks
                        WHERE trigger_source = ?
                        ORDER BY created_at DESC
                        LIMIT ?
                    """)
                    try {
                        stmt.set(0, triggerSource)
                        stmt.set(1, limit)
                        let rs = stmt.query()

                        var taskList = ArrayList<TaskData>()
                        try {
                            while (rs.next()) {
                                let data = TaskData()
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                data.name = rs.getOrNull<String>(1) ?? ""
                                data.taskType = rs.getOrNull<String>(2) ?? ""
                                data.status = rs.getOrNull<String>(3) ?? ""
                                data.progress = rs.getOrNull<Int32>(4) ?? 0
                                data.message = rs.getOrNull<String>(5) ?? ""
                                data.pluginNamespace = rs.getOrNull<String>(6) ?? ""
                                data.parameters = rs.getOrNull<String>(7) ?? ""
                                data.result = rs.getOrNull<String>(8) ?? ""
                                data.priority = rs.getOrNull<Int32>(9) ?? 50
                                data.groupId = rs.getOrNull<String>(10) ?? ""
                                data.timeoutAt = rs.getOrNull<String>(11) ?? ""
                                data.triggerSource = rs.getOrNull<String>(12) ?? ""
                                data.createdAt = rs.getOrNull<String>(13) ?? ""
                                data.startedAt = rs.getOrNull<String>(14) ?? ""
                                data.completedAt = rs.getOrNull<String>(15) ?? ""

                                taskList.add(data)
                            }
                            let size = taskList.size
                            if (size > 0) {
                                var result = Array<TaskData>(size, { _ => TaskData() })
                                for (i in 0..size) {
                                    result[i] = taskList[i]
                                }
                                return result
                            } else {
                                return Array<TaskData>()
                            }
                        } finally {
                            try {
                                rs.close()
                            } catch (closeError: Exception) {
                                logger.warn("关闭ResultSet失败: ${closeError.message}")
                            }
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    logger.error("按触发源查询任务失败", ("error", e.message))
                    return Array<TaskData>()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Array<TaskData>()
        }
    }

    /**
     * 按 group_id 查询任务
     */
    public static func getTasksByGroupId(groupId: String): Array<TaskData> {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                               priority, group_id, timeout_at, trigger_source,
                               created_at, started_at, completed_at
                        FROM tasks
                        WHERE group_id = ?
                        ORDER BY created_at ASC
                    """)
                    try {
                        stmt.set(0, groupId)
                        let rs = stmt.query()

                        var taskList = ArrayList<TaskData>()
                        try {
                            while (rs.next()) {
                                let data = TaskData()
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                data.name = rs.getOrNull<String>(1) ?? ""
                                data.taskType = rs.getOrNull<String>(2) ?? ""
                                data.status = rs.getOrNull<String>(3) ?? ""
                                data.progress = rs.getOrNull<Int32>(4) ?? 0
                                data.message = rs.getOrNull<String>(5) ?? ""
                                data.pluginNamespace = rs.getOrNull<String>(6) ?? ""
                                data.parameters = rs.getOrNull<String>(7) ?? ""
                                data.result = rs.getOrNull<String>(8) ?? ""
                                data.priority = rs.getOrNull<Int32>(9) ?? 50
                                data.groupId = rs.getOrNull<String>(10) ?? ""
                                data.timeoutAt = rs.getOrNull<String>(11) ?? ""
                                data.triggerSource = rs.getOrNull<String>(12) ?? ""
                                data.createdAt = rs.getOrNull<String>(13) ?? ""
                                data.startedAt = rs.getOrNull<String>(14) ?? ""
                                data.completedAt = rs.getOrNull<String>(15) ?? ""

                                taskList.add(data)
                            }
                            let size = taskList.size
                            if (size > 0) {
                                var result = Array<TaskData>(size, { _ => TaskData() })
                                for (i in 0..size) {
                                    result[i] = taskList[i]
                                }
                                return result
                            } else {
                                return Array<TaskData>()
                            }
                        } finally {
                            try {
                                rs.close()
                            } catch (closeError: Exception) {
                                logger.warn("关闭ResultSet失败: ${closeError.message}")
                            }
                        }
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    logger.error("按分组ID查询任务失败", ("error", e.message))
                    return Array<TaskData>()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Array<TaskData>()
        }
    }

    /**
     * 批量更新任务状态（用于批量取消）
     */
    public static func updateTaskStatusByGroupId(groupId: String, status: String, message: String): Int64 {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET status = ?, message = ?, completed_at = CURRENT_TIMESTAMP
                        WHERE group_id = ? AND status IN ('pending', 'running')
                    """)
                    try {
                        stmt.set(0, status)
                        stmt.set(1, message)
                        stmt.set(2, groupId)

                        let updateResult = stmt.update()
                        let rowCount = updateResult.rowCount
                        logger.debug("批量更新任务状态", ("group_id", groupId), ("count", rowCount.toString()))
                        return rowCount
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    logger.error("批量更新任务状态失败", ("error", e.message))
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
    public static func claimNextPendingTask(): Option<TaskData> {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 使用单条UPDATE + 子查询实现原子领取
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET status = 'running',
                            message = '任务已启动',
                            progress = 0,
                            started_at = CURRENT_TIMESTAMP
                        WHERE id = (
                            SELECT id FROM tasks
                            WHERE status = 'pending'
                            ORDER BY priority ASC, created_at ASC, id ASC
                            LIMIT 1
                        )
                        AND status = 'pending'
                        RETURNING id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                                  priority, group_id, timeout_at, trigger_source,
                                  created_at, started_at, completed_at
                    """)

                    let rs = stmt.query()
                    try {
                        if (rs.next()) {
                            let data = TaskData()
                            data.id = rs.getOrNull<Int64>(0) ?? 0
                            data.name = rs.getOrNull<String>(1) ?? ""
                            data.taskType = rs.getOrNull<String>(2) ?? ""
                            data.status = rs.getOrNull<String>(3) ?? ""
                            data.progress = rs.getOrNull<Int32>(4) ?? 0
                            data.message = rs.getOrNull<String>(5) ?? ""
                            data.pluginNamespace = rs.getOrNull<String>(6) ?? ""
                            data.parameters = rs.getOrNull<String>(7) ?? ""
                            data.result = rs.getOrNull<String>(8) ?? ""
                            data.priority = rs.getOrNull<Int32>(9) ?? 50
                            data.groupId = rs.getOrNull<String>(10) ?? ""
                            data.timeoutAt = rs.getOrNull<String>(11) ?? ""
                            data.triggerSource = rs.getOrNull<String>(12) ?? ""
                            data.createdAt = rs.getOrNull<String>(13) ?? ""
                            data.startedAt = rs.getOrNull<String>(14) ?? ""
                            data.completedAt = rs.getOrNull<String>(15) ?? ""
                            return Option<TaskData>.Some(data)
                        }
                        return Option<TaskData>.None
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
                    return Option<TaskData>.None
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Option<TaskData>.None
        }
    }

    /**
     * 创建等待状态的任务（条件驱动）
     * 任务创建后处于 waiting 状态，等待 waitForTaskId 指定的任务完成后自动转为 pending
     */
    public static func createWaitingTaskData(data: TaskData, waitForTaskId: Int64): Bool {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, wait_for_task_id, started_at, completed_at)
                        VALUES (?, ?, 'waiting', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL) RETURNING id
                    """)
                    try {
                        stmt.set(0, data.name)
                        stmt.set(1, data.taskType)
                        stmt.set(2, data.progress)
                        stmt.set(3, data.message)
                        stmt.set(4, data.pluginNamespace)
                        stmt.set(5, data.parameters)
                        stmt.set(6, data.result)
                        stmt.set(7, data.priority)
                        if (data.groupId.size > 0) {
                            stmt.set(8, data.groupId)
                        } else {
                            stmt.setNull(8)
                        }
                        if (data.timeoutAt.size > 0) {
                            stmt.set(9, data.timeoutAt)
                        } else {
                            stmt.setNull(9)
                        }
                        if (data.triggerSource.size > 0) {
                            stmt.set(10, data.triggerSource)
                        } else {
                            stmt.setNull(10)
                        }
                        stmt.set(11, waitForTaskId)

                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                data.status = "waiting"
                                data.waitForTaskId = waitForTaskId
                                logger.info("创建等待任务", ("id", data.id.toString()), ("wait_for", waitForTaskId.toString()))
                                return true
                            }
                            return false
                        } finally {
                            rs.close()
                        }
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("创建等待任务失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 查询等待指定任务完成的所有任务
     */
    public static func getTasksWaitingFor(taskId: Int64): Array<TaskData> {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                               priority, group_id, timeout_at, trigger_source, wait_for_task_id,
                               created_at, started_at, completed_at
                        FROM tasks
                        WHERE wait_for_task_id = ? AND status = 'waiting'
                    """)
                    try {
                        stmt.set(0, taskId)
                        let rs = stmt.query()
                        var taskList = ArrayList<TaskData>()
                        try {
                            while (rs.next()) {
                                let data = TaskData()
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                data.name = rs.getOrNull<String>(1) ?? ""
                                data.taskType = rs.getOrNull<String>(2) ?? ""
                                data.status = rs.getOrNull<String>(3) ?? ""
                                data.progress = rs.getOrNull<Int32>(4) ?? 0
                                data.message = rs.getOrNull<String>(5) ?? ""
                                data.pluginNamespace = rs.getOrNull<String>(6) ?? ""
                                data.parameters = rs.getOrNull<String>(7) ?? ""
                                data.result = rs.getOrNull<String>(8) ?? ""
                                data.priority = rs.getOrNull<Int32>(9) ?? 50
                                data.groupId = rs.getOrNull<String>(10) ?? ""
                                data.timeoutAt = rs.getOrNull<String>(11) ?? ""
                                data.triggerSource = rs.getOrNull<String>(12) ?? ""
                                data.waitForTaskId = rs.getOrNull<Int64>(13) ?? 0
                                data.createdAt = rs.getOrNull<String>(14) ?? ""
                                data.startedAt = rs.getOrNull<String>(15) ?? ""
                                data.completedAt = rs.getOrNull<String>(16) ?? ""
                                taskList.add(data)
                            }
                            let size = taskList.size
                            if (size > 0) {
                                var result = Array<TaskData>(size, { _ => TaskData() })
                                for (i in 0..size) {
                                    result[i] = taskList[i]
                                }
                                return result
                            }
                            return Array<TaskData>()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("查询等待任务失败", ("error", e.message))
                    return Array<TaskData>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Array<TaskData>()
        }
    }

    /**
     * 激活等待任务（将 waiting 状态转为 pending）
     */
    public static func activateWaitingTask(taskId: Int64): Bool {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks SET status = 'pending', message = '依赖任务已完成，等待执行'
                        WHERE id = ? AND status = 'waiting'
                    """)
                    try {
                        stmt.set(0, taskId)
                        let result = stmt.update()
                        if (result.rowCount > 0) {
                            logger.info("激活等待任务", ("id", taskId.toString()))
                            return true
                        }
                        return false
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("激活等待任务失败", ("id", taskId.toString()), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 将等待任务标记为失败（依赖任务失败时调用）
     */
    public static func failWaitingTask(taskId: Int64, errorMessage: String): Bool {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks SET status = 'failed', message = ?, completed_at = CURRENT_TIMESTAMP
                        WHERE id = ? AND status = 'waiting'
                    """)
                    try {
                        stmt.set(0, errorMessage)
                        stmt.set(1, taskId)
                        let result = stmt.update()
                        if (result.rowCount > 0) {
                            logger.info("等待任务标记失败", ("id", taskId.toString()))
                            return true
                        }
                        return false
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("标记等待任务失败", ("id", taskId.toString()), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }
}
