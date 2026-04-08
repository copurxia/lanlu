package lanlu.contexts.task.infrastructure.persistence

import std.database.sql.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
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
    public var phase: String = ""
    public var waitingReason: String = ""
    public var activeKey: String = ""

    public init() {}
}

/**
 * 任务数据访问对象 (DAO)
 * 负责处理所有与任务相关的数据库操作
 */
public class TaskDao {
    private static func defaultPhaseForStatus(status: String): String {
        match (status) {
            case "pending" => return "queued"
            case "running" => return "executing"
            case "waiting" => return "waiting"
            case "completed" => return "completed"
            case "failed" => return "failed"
            case "stopped" => return "stopped"
            case _ => return ""
        }
    }

    // 注意：表创建已由迁移系统处理，createTable() 方法已移除

    /**
     * 创建任务（含扩展字段）
     */
    public static func createTaskData(data: TaskData): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    if (data.phase.size == 0) {
                        data.phase = defaultPhaseForStatus(data.status)
                    }
                    let stmt = conn.prepareStatement("""
                        INSERT INTO tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, started_at, completed_at, phase, waiting_reason, active_key)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id
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
                        if (data.phase.size > 0) {
                            stmt.set(14, data.phase)
                        } else {
                            stmt.setNull(14)
                        }
                        if (data.waitingReason.size > 0) {
                            stmt.set(15, data.waitingReason)
                        } else {
                            stmt.setNull(15)
                        }
                        if (data.activeKey.size > 0) {
                            stmt.set(16, data.activeKey)
                        } else {
                            stmt.setNull(16)
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
                    let phase = defaultPhaseForStatus(status)
                    let stmt = conn.prepareStatement("""
                        INSERT INTO tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, started_at, completed_at, phase, waiting_reason, active_key)
                        VALUES (?, ?, ?, ?, ?, '', ?, '', ?, NULL, NULL, ?, NULL, NULL, ?, NULL, NULL) RETURNING id
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
                        stmt.set(8, phase)

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
                               created_at, started_at, completed_at, phase, waiting_reason, active_key
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
                                data.phase = rs.getOrNull<String>(16) ?? ""
                                data.waitingReason = rs.getOrNull<String>(17) ?? ""
                                data.activeKey = rs.getOrNull<String>(18) ?? ""
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
                    let phase = defaultPhaseForStatus(status)
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks SET status = ?, message = ?, progress = ?, phase = ?,
                            waiting_reason = CASE WHEN ? = 'waiting' THEN waiting_reason ELSE NULL END
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, status)
                        stmt.set(1, message)
                        stmt.set(2, progress)
                        stmt.set(3, phase)
                        stmt.set(4, status)
                        stmt.set(5, id)

                        let result = stmt.update()
                        if (result.rowCount > 0) {
                            TaskEventHub.getInstance().publishTaskChanged(id)
                        }
                        getLogger("task_dao").debug("更新任务状态", ("id", id), ("status", status))
                        return result.rowCount > 0
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
     * 更新任务进度与消息，但保留当前主状态。
     */
    public static func updateTaskProgressPreserveStatus(id: Int64, progress: Int32, message: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET message = ?, progress = ?
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, message)
                        stmt.set(1, progress)
                        stmt.set(2, id)

                        let result = stmt.update()
                        if (result.rowCount > 0) {
                            let eventHub = TaskEventHub.getInstance()
                            eventHub.publishTaskChanged(id)
                            eventHub.publishTaskProgress(id)
                        }
                        getLogger("task_dao").debug("更新任务进度(保留状态)", [("id", id.toString()), ("progress", progress.toString())])
                        return result.rowCount > 0
                    } finally {
                        try {
                            stmt.close()
                        } catch (closeError: Exception) {
                            getLogger("task_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                        }
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("更新任务进度失败", ("id", id), ("error", e.message))
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
     * 更新 waiting 相关元数据。
     */
    public static func updateTaskWaitingState(id: Int64, message: String, progress: Int32, phase: String, waitingReason: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET status = 'waiting',
                            message = ?,
                            progress = ?,
                            phase = ?,
                            waiting_reason = ?
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, message)
                        stmt.set(1, progress)
                        stmt.set(2, phase)
                        stmt.set(3, waitingReason)
                        stmt.set(4, id)

                        let result = stmt.update()
                        if (result.rowCount > 0) {
                            let eventHub = TaskEventHub.getInstance()
                            eventHub.publishTaskChanged(id)
                            eventHub.publishTaskWaiting(id)
                        }
                        return result.rowCount > 0
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("更新等待任务状态失败", ("id", id), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("task_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 延长任务超时时间：timeout_at = now + timeoutSeconds
     */
    public static func extendTaskTimeout(id: Int64, timeoutSeconds: Int32): Bool {
        let logger = getLogger("task_dao")
        if (timeoutSeconds <= 0) {
            return false
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET timeout_at = CURRENT_TIMESTAMP + (? * INTERVAL '1 second')
                        WHERE id = ? AND status = 'running'
                    """)
                    try {
                        stmt.set(0, Int64(timeoutSeconds))
                        stmt.set(1, id)
                        let updateResult = stmt.update()
                        return updateResult.rowCount > 0
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("延长任务超时失败", ("id", id.toString()), ("error", e.message))
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
     * 原子性地延长任务超时时间并更新进度
     * 
     * 优化说明：
     * - 将 extendTaskTimeout + updateTaskProgressPreserveStatus 合并为单次SQL
     * - 减少数据库往返次数，从2次DB写降至1次
     * - 适用于高频调用的分片上传场景
     * - 仅更新 running 状态的任务，避免误更新已完成任务
     *
     * @param id 任务ID
     * @param timeoutSeconds 超时秒数
     * @param progress 进度百分比（0-100）
     * @param message 进度消息
     * @return 是否更新成功
     */
    public static func extendTimeoutAndUpdateProgress(
        id: Int64,
        timeoutSeconds: Int32,
        progress: Int32,
        message: String
    ): Bool {
        let logger = getLogger("task_dao")
        if (timeoutSeconds <= 0) {
            return false
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET timeout_at = CURRENT_TIMESTAMP + (? * INTERVAL '1 second'),
                            message = ?,
                            progress = ?
                        WHERE id = ? AND status = 'running'
                    """)
                    try {
                        stmt.set(0, Int64(timeoutSeconds))
                        stmt.set(1, message)
                        stmt.set(2, progress)
                        stmt.set(3, id)
                        let updateResult = stmt.update()
                        if (updateResult.rowCount > 0) {
                            TaskEventHub.getInstance().publishTaskChanged(id)
                        }
                        return updateResult.rowCount > 0
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("延长超时并更新进度失败", ("id", id.toString()), ("error", e.message))
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
     * 原子地将 asset_upload 任务转交给 asset_upload_process
     *
     * 修复说明：
     * - 将 updateTaskType + updateTaskStatus 合并为单条 SQL，消除两步操作之间的竜态窗口
     * - WHERE 已加上 status='running' AND task_type='asset_upload' 安全地幸，
     *   若任务已被取消或失败，返回 false。
     *
     * @param id       任务ID
     * @param message  转交后的状态消息
     * @param progress 转交后的进度（0-100）
     * @return 是否转交成功
     */
    public static func handoffUploadTask(id: Int64, message: String, progress: Int32): Bool {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET task_type = 'asset_upload_process',
                            status    = 'pending',
                            message   = ?,
                            progress  = ?,
                            phase     = 'queued',
                            waiting_reason = NULL
                        WHERE id = ? AND status = 'running' AND task_type = 'asset_upload'
                    """)
                    try {
                        stmt.set(0, message)
                        stmt.set(1, progress)
                        stmt.set(2, id)
                        let updateResult = stmt.update()
                        if (updateResult.rowCount > 0) {
                            TaskEventHub.getInstance().publishTaskChanged(id)
                        }
                        return updateResult.rowCount > 0
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("任务 handoff 失败", ("id", id.toString()), ("error", e.message))
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
     * 将 handoff 后因 double-claim 被抢先置为 running 的任务重置回 pending，
     * 以便 requestDispatch() 可以正常领取并执行新 task_type 的逻辑。
     * 在 worker 退出 finally 块时调用。
     */
    public static func resetHandoffedTask(id: Int64, originalType: String): Bool {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET status = 'pending',
                            phase  = 'queued'
                        WHERE id = ? AND status = 'running' AND task_type != ?
                    """)
                    try {
                        stmt.set(0, id)
                        stmt.set(1, originalType)
                        let result = stmt.update()
                        if (result.rowCount > 0) {
                            logger.debug(
                                "resetHandoffedTask: reset to pending",
                                ("id", id.toString()),
                                ("original_type", originalType)
                            )
                            TaskEventHub.getInstance().publishTaskChanged(id)
                        }
                        return result.rowCount > 0
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("resetHandoffedTask 失败", ("id", id.toString()), ("error", e.message))
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
     * 定期清理超时的上传占位任务（running 且 timeout_at 已过期）
     */
    public static func failTimedOutUploadTasks(): Int64 {
        let logger = getLogger("task_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET status = 'failed',
                            message = '上传任务超时：10分钟内未完成',
                            completed_at = CURRENT_TIMESTAMP
                        WHERE task_type IN ('upload', 'asset_upload', 'asset_upload_process', 'archive_asset_consume', 'tag_asset_consume', 'avatar_asset_consume', 'metadata_asset_consume', 'plugin_asset_consume')
                          AND status = 'running'
                          AND timeout_at IS NOT NULL
                          AND timeout_at <= CURRENT_TIMESTAMP
                        RETURNING id
                    """)
                    try {
                        let rs = stmt.query()
                        let timedOutIds = ArrayList<Int64>()
                        try {
                            while (rs.next()) {
                                timedOutIds.add(rs.getOrNull<Int64>(0) ?? 0)
                            }
                        } finally {
                            try { rs.close() } catch (_: Exception) {}
                        }
                        let rowCount = Int64(timedOutIds.size)
                        for (taskId in timedOutIds) {
                            if (taskId > 0) {
                                TaskEventHub.getInstance().publishTaskChanged(taskId)
                            }
                        }
                        if (rowCount > 0) {
                            logger.warn("超时上传任务已标记失败", ("count", rowCount.toString()))
                        }
                        return rowCount
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    logger.error("清理超时上传任务失败", ("error", e.message))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法创建数据库连接")
                return 0
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
                    if (data.phase.size == 0) {
                        data.phase = defaultPhaseForStatus(data.status)
                    }
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks SET
                            name = ?, task_type = ?, status = ?, progress = ?, message = ?,
                            plugin_namespace = ?, parameters = ?, result = ?, priority = ?, group_id = ?,
                            timeout_at = ?, trigger_source = ?, started_at = ?, completed_at = ?,
                            phase = ?, waiting_reason = ?, active_key = ?
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
                        if (data.phase.size > 0) {
                            stmt.set(14, data.phase)
                        } else {
                            stmt.setNull(14)
                        }
                        if (data.waitingReason.size > 0) {
                            stmt.set(15, data.waitingReason)
                        } else {
                            stmt.setNull(15)
                        }
                        if (data.activeKey.size > 0) {
                            stmt.set(16, data.activeKey)
                        } else {
                            stmt.setNull(16)
                        }
                        stmt.set(17, data.id)

                        let result = stmt.update()
                        if (result.rowCount > 0) {
                            TaskEventHub.getInstance().publishTaskChanged(data.id)
                        }
                        getLogger("task_dao").debug("更新任务", ("id", data.id))
                        return result.rowCount > 0
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
     * 获取指定状态的任务总数
     */
    public static func getTaskCountByStatus(status: String): Int32 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM tasks WHERE status = ?")
                    stmt.set(0, status)
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
                    getLogger("task_dao").error("获取指定状态任务总数失败", ("status", status), ("error", e.message))
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
                        SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, created_at, started_at, completed_at, phase, waiting_reason, active_key
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
                            data.phase = rs.getOrNull<String>(16) ?? ""
                            data.waitingReason = rs.getOrNull<String>(17) ?? ""
                            data.activeKey = rs.getOrNull<String>(18) ?? ""

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
     * 分页获取指定状态的任务列表
     * @param offset 偏移量
     * @param limit 每页数量
     * @param status 任务状态
     */
    public static func getTasksWithPaginationByStatus(offset: Int32, limit: Int32, status: String): Array<TaskData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, created_at, started_at, completed_at, phase, waiting_reason, active_key
                        FROM tasks
                        WHERE status = ?
                        ORDER BY id DESC
                        LIMIT ? OFFSET ?
                    """)
                    try {
                        stmt.set(0, status)
                        stmt.set(1, limit)
                        stmt.set(2, offset)
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
                                data.phase = rs.getOrNull<String>(16) ?? ""
                                data.waitingReason = rs.getOrNull<String>(17) ?? ""
                                data.activeKey = rs.getOrNull<String>(18) ?? ""

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
                        } catch (e: Exception) {
                            getLogger("task_dao").error("分页查询指定状态任务失败", ("status", status), ("error", e.message))
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
                        getLogger("task_dao").error("分页查询指定状态任务失败", ("status", status), ("error", e.message))
                        return Array<TaskData>()
                    }
                } catch (e: Exception) {
                    getLogger("task_dao").error("分页查询指定状态任务失败", ("status", status), ("error", e.message))
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

                    let result = pstmt.update()
                    logger.debug("更新任务参数", ("id", id.toString()), ("parameters", parameters))
                    if (result.rowCount > 0) {
                        TaskEventHub.getInstance().publishTaskChanged(id)
                    }

                    try {
                        pstmt.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                    }

                    return result.rowCount > 0

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

                    let result = pstmt.update()
                    if (result.rowCount > 0) {
                        TaskEventHub.getInstance().publishTaskChanged(id)
                    }
                    try {
                        pstmt.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                    }
                    return result.rowCount > 0
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
                    let result = pstmt.update()
                    if (result.rowCount > 0) {
                        TaskEventHub.getInstance().publishTaskChanged(id)
                    }
                    try {
                        pstmt.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭PreparedStatement失败: ${closeError.message}")
                    }
                    return result.rowCount > 0
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
                        RETURNING id
                    """
                    let stmt = conn.prepareStatement(updateSql)
                    try {
                        let rs = stmt.query()
                        let recoveredIds = ArrayList<Int64>()
                        try {
                            while (rs.next()) {
                                recoveredIds.add(rs.getOrNull<Int64>(0) ?? 0)
                            }
                        } finally {
                            try { rs.close() } catch (_: Exception) {}
                        }
                        let rowCount = Int64(recoveredIds.size)
                        for (taskId in recoveredIds) {
                            if (taskId > 0) {
                                TaskEventHub.getInstance().publishTaskChanged(taskId)
                            }
                        }
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
                               created_at, started_at, completed_at, phase, waiting_reason, active_key
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
                                data.phase = rs.getOrNull<String>(16) ?? ""
                                data.waitingReason = rs.getOrNull<String>(17) ?? ""
                                data.activeKey = rs.getOrNull<String>(18) ?? ""

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
                               created_at, started_at, completed_at, phase, waiting_reason, active_key
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
                                data.phase = rs.getOrNull<String>(16) ?? ""
                                data.waitingReason = rs.getOrNull<String>(17) ?? ""
                                data.activeKey = rs.getOrNull<String>(18) ?? ""

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
     * 查询指定 group_id 是否仍有未进入终态的任务。
     */
    public static func existsNonTerminalTasksByGroupId(groupId: String): Bool {
        if (groupId.trimAscii().size == 0) {
            return false
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT 1
                        FROM tasks
                        WHERE group_id = ?
                          AND status NOT IN ('completed', 'failed', 'stopped')
                        LIMIT 1
                    """)
                    try {
                        stmt.set(0, groupId)
                        let rs = stmt.query()
                        try {
                            return rs.next()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 查询指定类型与 group_id 是否已存在活动任务。
     */
    public static func existsActiveTaskByTypeAndGroupId(taskType: String, groupId: String): Bool {
        if (taskType.trimAscii().size == 0 || groupId.trimAscii().size == 0) {
            return false
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT 1
                        FROM tasks
                        WHERE task_type = ?
                          AND group_id = ?
                          AND status IN ('pending', 'running', 'waiting')
                        LIMIT 1
                    """)
                    try {
                        stmt.set(0, taskType)
                        stmt.set(1, groupId)
                        let rs = stmt.query()
                        try {
                            return rs.next()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 查询指定 active_key 是否已存在活动任务。
     */
    public static func existsActiveTaskByActiveKey(activeKey: String): Bool {
        let normalized = activeKey.trimAscii()
        if (normalized.size == 0) {
            return false
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT 1
                        FROM tasks
                        WHERE active_key = ?
                          AND status IN ('pending', 'running', 'waiting')
                        LIMIT 1
                    """)
                    try {
                        stmt.set(0, normalized)
                        let rs = stmt.query()
                        try {
                            return rs.next()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
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
     * 批量领取待执行任务（原子地将多个pending置为running）
     * @param limit 最多领取的任务数量
     * @return 领取到的任务列表
     */
    public static func claimPendingTasks(limit: Int32): ArrayList<TaskData> {
        let logger = getLogger("task_dao")
        var result = ArrayList<TaskData>()
        if (limit <= 0) {
            return result
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 使用子查询实现批量原子领取
                    let stmt = conn.prepareStatement("""
                        UPDATE tasks
                        SET status = 'running',
                            message = '任务已启动',
                            progress = 0,
                            started_at = CURRENT_TIMESTAMP,
                            phase = 'executing',
                            waiting_reason = NULL
                        WHERE id IN (
                            SELECT id FROM tasks
                            WHERE status = 'pending'
                            ORDER BY priority ASC, created_at ASC, id ASC
                            LIMIT ?
                        )
                        AND status = 'pending'
                        RETURNING id, name, task_type, status, progress, message,
                                  plugin_namespace, parameters, result,
                                  priority, group_id, timeout_at, trigger_source,
                                  created_at, started_at, completed_at, phase, waiting_reason, active_key
                    """)
                    stmt.set(0, Int64(limit))

                    let rs = stmt.query()
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
                            data.phase = rs.getOrNull<String>(16) ?? ""
                            data.waitingReason = rs.getOrNull<String>(17) ?? ""
                            data.activeKey = rs.getOrNull<String>(18) ?? ""
                            result.add(data)
                        }
                        for (task in result) {
                            if (task.id > 0) {
                                TaskEventHub.getInstance().publishTaskChanged(task.id)
                            }
                        }
                    } finally {
                        try {
                            rs.close()
                            stmt.close()
                        } catch (closeError: Exception) {
                            logger.warn("关闭ResultSet或PreparedStatement失败: ${closeError.message}")
                        }
                    }
                    return result
                } catch (e: Exception) {
                    logger.error("批量领取待执行任务失败", ("error", e.message))
                    return result
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return result
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
                    data.phase = "awaiting_dependency"
                    data.waitingReason = "task_dependency"
                    let stmt = conn.prepareStatement("""
                        INSERT INTO tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, wait_for_task_id, started_at, completed_at, phase, waiting_reason, active_key)
                        VALUES (?, ?, 'waiting', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?) RETURNING id
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
                        stmt.set(12, data.phase)
                        stmt.set(13, data.waitingReason)
                        if (data.activeKey.size > 0) {
                            stmt.set(14, data.activeKey)
                        } else {
                            stmt.setNull(14)
                        }

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
                               created_at, started_at, completed_at, phase, waiting_reason, active_key
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
                                data.phase = rs.getOrNull<String>(17) ?? ""
                                data.waitingReason = rs.getOrNull<String>(18) ?? ""
                                data.activeKey = rs.getOrNull<String>(19) ?? ""
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
                        UPDATE tasks SET status = 'pending', message = '依赖任务已完成，等待执行', phase = 'queued', waiting_reason = NULL
                        WHERE id = ? AND status = 'waiting'
                    """)
                    try {
                        stmt.set(0, taskId)
                        let result = stmt.update()
                        if (result.rowCount > 0) {
                            logger.debug("激活等待任务", ("id", taskId.toString()))
                            let eventHub = TaskEventHub.getInstance()
                            eventHub.publishTaskChanged(taskId)
                            eventHub.publishWaitingActivated(taskId)
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
                            logger.debug("等待任务标记失败", ("id", taskId.toString()))
                            TaskEventHub.getInstance().publishTaskChanged(taskId)
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
