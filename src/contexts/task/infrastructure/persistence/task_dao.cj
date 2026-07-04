package lanlu.contexts.task.infrastructure.persistence

import ace_orm.*
import lanlu.contexts.task.*
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
    public var waitForTaskId: Int64 = 0 // 条件驱动：等待指定任务完成后才能执行
    public var phase: String = ""
    public var waitingReason: String = ""
    public var activeKey: String = ""

    public mut prop taskStatus: TaskStatus {
        get() {
            TaskStatus.fromDb(status)
        }
        set(value) {
            status = value.toDb()
        }
    }

    public init() {}
}

/**
 * 任务数据访问对象 (DAO)
 * 负责处理所有与任务相关的数据库操作
 */
public class TaskDao {
    private static func defaultPhaseForStatus(status: String): String {
        return TaskStatus.defaultPhaseForDbValue(status)
    }

    public static func updateTaskStatus(id: Int64, status: TaskStatus, message: String, progress: Int32): Bool {
        return updateTaskStatus(id, status.toDb(), message, progress)
    }

    // 注意：表创建已由迁移系统处理，createTable() 方法已移除

    /**
     * 从 Row 映射到 TaskData（标准 19 列：id, name, task_type, status, progress, message,
     * plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source,
     * created_at, started_at, completed_at, phase, waiting_reason, active_key）
     */
    private static func mapRowToTaskData(r: Row): TaskData {
        let data = TaskData()
        data.id = r.getInt("id")
        data.name = r.getText("name")
        data.taskType = r.getText("task_type")
        data.status = r.getText("status")
        data.progress = Int32(r.getInt("progress"))
        data.message = r.getText("message")
        data.pluginNamespace = r.getText("plugin_namespace")
        data.parameters = r.getText("parameters")
        data.result = r.getText("result")
        data.priority = Int32(r.getInt("priority"))
        data.groupId = r.getText("group_id")
        data.timeoutAt = r.getText("timeout_at")
        data.triggerSource = r.getText("trigger_source")
        data.createdAt = r.getText("created_at")
        data.startedAt = r.getText("started_at")
        data.completedAt = r.getText("completed_at")
        data.phase = r.getText("phase")
        data.waitingReason = r.getText("waiting_reason")
        data.activeKey = r.getText("active_key")
        return data
    }

    /**
     * 从 Row 映射到 TaskData（含 wait_for_task_id，20 列）
     */
    private static func mapRowToTaskDataWithWaitFor(r: Row): TaskData {
        let data = TaskData()
        data.id = r.getInt("id")
        data.name = r.getText("name")
        data.taskType = r.getText("task_type")
        data.status = r.getText("status")
        data.progress = Int32(r.getInt("progress"))
        data.message = r.getText("message")
        data.pluginNamespace = r.getText("plugin_namespace")
        data.parameters = r.getText("parameters")
        data.result = r.getText("result")
        data.priority = Int32(r.getInt("priority"))
        data.groupId = r.getText("group_id")
        data.timeoutAt = r.getText("timeout_at")
        data.triggerSource = r.getText("trigger_source")
        data.waitForTaskId = r.getInt("wait_for_task_id")
        data.createdAt = r.getText("created_at")
        data.startedAt = r.getText("started_at")
        data.completedAt = r.getText("completed_at")
        data.phase = r.getText("phase")
        data.waitingReason = r.getText("waiting_reason")
        data.activeKey = r.getText("active_key")
        return data
    }

    /**
     * 创建任务（含扩展字段）
     */
    public static func createTaskData(data: TaskData): Bool {
        let logger = getLogger("task_dao")
        try {
            if (data.phase.size == 0) {
                data.phase = defaultPhaseForStatus(data.status)
            }
            let rows = DatabaseConfig.driver().query("""
                INSERT INTO tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, started_at, completed_at, phase, waiting_reason, active_key)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17) RETURNING id
            """, [
                DbText(data.name),
                DbText(data.taskType),
                DbText(data.status),
                DbInt(Int64(data.progress)),
                DbText(data.message),
                DbText(data.pluginNamespace),
                DbText(data.parameters),
                DbText(data.result),
                DbInt(Int64(data.priority)),
                if (data.groupId.size > 0) { DbText(data.groupId) } else { DbNull },
                if (data.timeoutAt.size > 0) { DbText(data.timeoutAt) } else { DbNull },
                if (data.triggerSource.size > 0) { DbText(data.triggerSource) } else { DbNull },
                if (data.startedAt.size > 0) { DbText(data.startedAt) } else { DbNull },
                if (data.completedAt.size > 0) { DbText(data.completedAt) } else { DbNull },
                if (data.phase.size > 0) { DbText(data.phase) } else { DbNull },
                if (data.waitingReason.size > 0) { DbText(data.waitingReason) } else { DbNull },
                if (data.activeKey.size > 0) { DbText(data.activeKey) } else { DbNull }
            ])
            if (rows.size > 0) {
                data.id = rows[0].getInt("id")
                logger.info("创建任务", ("id", data.id.toString()))
                return true
            } else {
                logger.error("获取自增ID失败")
                return false
            }
        } catch (e: Exception) {
            logger.error("创建任务失败", ("id", data.id), ("error", e.message))
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
        try {
            let phase = defaultPhaseForStatus(status)
            let rows = DatabaseConfig.driver().query("""
                INSERT INTO tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, started_at, completed_at, phase, waiting_reason, active_key)
                VALUES ($1, $2, $3, $4, $5, '', $6, '', $7, NULL, NULL, $8, NULL, NULL, $9, NULL, NULL) RETURNING id
            """, [
                DbText(name),
                DbText(taskType),
                DbText(status),
                DbInt(Int64(progress)),
                DbText(message),
                DbText(parameters),
                DbInt(Int64(priority)),
                DbText(triggerSource),
                DbText(phase)
            ])
            if (rows.size > 0) {
                let id = rows[0].getInt("id")
                logger.debug("创建完整任务", ("id", id.toString()))
                return Some(id)
            }
            return None
        } catch (e: Exception) {
            logger.error("创建完整任务失败", ("error", e.message))
            return None
        }
    }

    /**
     * 根据ID获取任务
     */
    public static func getTaskDataById(id: Int64): TaskData {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                       priority, group_id, timeout_at, trigger_source,
                       created_at, started_at, completed_at, phase, waiting_reason, active_key
                FROM tasks WHERE id = $1
            """, [DbInt(id)])
            if (rows.size > 0) {
                return mapRowToTaskData(rows[0])
            } else {
                return TaskData()
            }
        } catch (e: Exception) {
            logger.error("查询任务失败", ("id", id), ("error", e.message))
            return TaskData()
        }
    }

    /**
     * 更新任务状态
     */
    public static func updateTaskStatus(id: Int64, status: String, message: String, progress: Int32): Bool {
        let logger = getLogger("task_dao")
        try {
            let phase = defaultPhaseForStatus(status)
            let result = DatabaseConfig.driver().exec("""
                UPDATE tasks SET status = $1, message = $2, progress = $3, phase = $4,
                    waiting_reason = CASE WHEN $5 = 'waiting' THEN waiting_reason ELSE NULL END
                WHERE id = $6
            """, [DbText(status), DbText(message), DbInt(Int64(progress)), DbText(phase), DbText(status), DbInt(id)])
            if (result > 0) {
                TaskEventHub.getInstance().publishTaskChanged(id)
            }
            logger.debug("更新任务状态", ("id", id), ("status", status))
            return result > 0
        } catch (e: Exception) {
            logger.error("更新任务状态失败", ("id", id), ("error", e.message))
            return false
        }
    }

    /**
     * 更新任务进度与消息，但保留当前主状态。
     */
    public static func updateTaskProgressPreserveStatus(id: Int64, progress: Int32, message: String): Bool {
        let logger = getLogger("task_dao")
        try {
            let result = DatabaseConfig.driver().exec("""
                UPDATE tasks
                SET message = $1, progress = $2
                WHERE id = $3
            """, [DbText(message), DbInt(Int64(progress)), DbInt(id)])
            if (result > 0) {
                let eventHub = TaskEventHub.getInstance()
                eventHub.publishTaskChanged(id)
                eventHub.publishTaskProgress(id)
            }
            logger.debug("更新任务进度(保留状态)",
                [("id", id.toString()), ("progress", progress.toString())])
            return result > 0
        } catch (e: Exception) {
            logger.error("更新任务进度失败", ("id", id), ("error", e.message))
            return false
        }
    }

    /**
     * 更新 waiting 相关元数据。
     */
    public static func updateTaskWaitingState(id: Int64, message: String, progress: Int32, phase: String,
        waitingReason: String): Bool {
        let logger = getLogger("task_dao")
        try {
            let result = DatabaseConfig.driver().exec("""
                UPDATE tasks
                SET status = 'waiting',
                    message = $1,
                    progress = $2,
                    phase = $3,
                    waiting_reason = $4
                WHERE id = $5
            """, [DbText(message), DbInt(Int64(progress)), DbText(phase), DbText(waitingReason), DbInt(id)])
            if (result > 0) {
                let eventHub = TaskEventHub.getInstance()
                eventHub.publishTaskChanged(id)
                eventHub.publishTaskWaiting(id)
            }
            return result > 0
        } catch (e: Exception) {
            logger.error("更新等待任务状态失败", ("id", id), ("error", e.message))
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

        try {
            let result = DatabaseConfig.driver().exec("""
                UPDATE tasks
                SET timeout_at = CURRENT_TIMESTAMP + ($1 * INTERVAL '1 second')
                WHERE id = $2 AND status = 'running'
            """, [DbInt(Int64(timeoutSeconds)), DbInt(id)])
            return result > 0
        } catch (e: Exception) {
            logger.error("延长任务超时失败", ("id", id.toString()), ("error", e.message))
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

        try {
            let result = DatabaseConfig.driver().exec("""
                UPDATE tasks
                SET timeout_at = CURRENT_TIMESTAMP + ($1 * INTERVAL '1 second'),
                    message = $2,
                    progress = $3
                WHERE id = $4 AND status = 'running'
            """, [DbInt(Int64(timeoutSeconds)), DbText(message), DbInt(Int64(progress)), DbInt(id)])
            if (result > 0) {
                TaskEventHub.getInstance().publishTaskChanged(id)
            }
            return result > 0
        } catch (e: Exception) {
            logger.error("延长超时并更新进度失败", ("id", id.toString()), ("error", e.message))
            return false
        }
    }

    /**
     * 定期清理超时的上传占位任务（running 且 timeout_at 已过期）
     */
    public static func failTimedOutUploadTasks(): Int64 {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                UPDATE tasks
                SET status = 'failed',
                    message = '上传任务超时：10分钟内未完成',
                    completed_at = CURRENT_TIMESTAMP,
                    phase = 'failed'
                WHERE task_type IN ('upload', 'asset_upload', 'asset_upload_process', 'archive_asset_consume', 'tag_asset_consume', 'avatar_asset_consume', 'metadata_asset_consume', 'plugin_asset_consume')
                  AND status = 'running'
                  AND timeout_at IS NOT NULL
                  AND timeout_at <= CURRENT_TIMESTAMP
                RETURNING id
            """, [])
            let timedOutIds = ArrayList<Int64>()
            for (r in rows) {
                timedOutIds.add(r.getInt("id"))
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
        } catch (e: Exception) {
            logger.error("清理超时上传任务失败", ("error", e.message))
            return 0
        }
    }

    /**
     * 更新任务完整信息
     */
    public static func updateTaskData(data: TaskData): Bool {
        let logger = getLogger("task_dao")
        try {
            if (data.phase.size == 0) {
                data.phase = defaultPhaseForStatus(data.status)
            }
            let result = DatabaseConfig.driver().exec("""
                UPDATE tasks SET
                    name = $1, task_type = $2, status = $3, progress = $4, message = $5,
                    plugin_namespace = $6, parameters = $7, result = $8, priority = $9, group_id = $10,
                    timeout_at = $11, trigger_source = $12, started_at = $13, completed_at = $14,
                    phase = $15, waiting_reason = $16, active_key = $17
                WHERE id = $18
            """, [
                DbText(data.name),
                DbText(data.taskType),
                DbText(data.status),
                DbInt(Int64(data.progress)),
                DbText(data.message),
                DbText(data.pluginNamespace),
                DbText(data.parameters),
                DbText(data.result),
                DbInt(Int64(data.priority)),
                if (data.groupId.size > 0) { DbText(data.groupId) } else { DbNull },
                if (data.timeoutAt.size > 0) { DbText(data.timeoutAt) } else { DbNull },
                if (data.triggerSource.size > 0) { DbText(data.triggerSource) } else { DbNull },
                if (data.startedAt.size > 0) { DbText(data.startedAt) } else { DbNull },
                if (data.completedAt.size > 0) { DbText(data.completedAt) } else { DbNull },
                if (data.phase.size > 0) { DbText(data.phase) } else { DbNull },
                if (data.waitingReason.size > 0) { DbText(data.waitingReason) } else { DbNull },
                if (data.activeKey.size > 0) { DbText(data.activeKey) } else { DbNull },
                DbInt(data.id)
            ])
            if (result > 0) {
                TaskEventHub.getInstance().publishTaskChanged(data.id)
            }
            logger.debug("更新任务", ("id", data.id))
            return result > 0
        } catch (e: Exception) {
            logger.error("更新任务失败", ("id", data.id), ("error", e.message))
            return false
        }
    }

    /**
     * 删除任务
     */
    public static func deleteTask(id: Int64): Bool {
        let logger = getLogger("task_dao")
        try {
            DatabaseConfig.driver().exec("DELETE FROM tasks WHERE id = $1", [DbInt(id)])
            logger.info("删除任务", ("id", id))
            return true
        } catch (e: Exception) {
            logger.error("删除任务失败", ("id", id), ("error", e.message))
            return false
        }
    }

    /**
     * 检查任务是否存在
     */
    public static func taskExists(id: Int64): Bool {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) FROM tasks WHERE id = $1", [DbInt(id)])
            if (rows.size > 0) {
                let count = rows[0].getInt("count")
                return count > 0
            } else {
                return false
            }
        } catch (e: Exception) {
            logger.error("检查任务存在性失败", ("id", id), ("error", e.message))
            return false
        }
    }

    /**
     * 获取任务总数
     */
    public static func getTaskCount(): Int32 {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) FROM tasks", [])
            if (rows.size > 0) {
                return Int32(rows[0].getInt("count"))
            } else {
                return 0
            }
        } catch (e: Exception) {
            logger.error("获取任务总数失败", ("error", e.message))
            return 0
        }
    }

    /**
     * 获取指定状态的任务总数
     */
    public static func getTaskCountByStatus(status: String): Int32 {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) FROM tasks WHERE status = $1", [DbText(status)])
            if (rows.size > 0) {
                return Int32(rows[0].getInt("count"))
            } else {
                return 0
            }
        } catch (e: Exception) {
            logger.error("获取指定状态任务总数失败", ("status", status), ("error", e.message))
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
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, created_at, started_at, completed_at, phase, waiting_reason, active_key
                FROM tasks
                ORDER BY id DESC
                LIMIT $1 OFFSET $2
            """, [DbInt(Int64(limit)), DbInt(Int64(offset))])
            let taskList = ArrayList<TaskData>()
            for (r in rows) {
                taskList.add(mapRowToTaskData(r))
            }
            return taskList.toArray()
        } catch (e: Exception) {
            logger.error("分页查询任务失败", ("error", e.message))
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
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, created_at, started_at, completed_at, phase, waiting_reason, active_key
                FROM tasks
                WHERE status = $1
                ORDER BY id DESC
                LIMIT $2 OFFSET $3
            """, [DbText(status), DbInt(Int64(limit)), DbInt(Int64(offset))])
            let taskList = ArrayList<TaskData>()
            for (r in rows) {
                taskList.add(mapRowToTaskData(r))
            }
            return taskList.toArray()
        } catch (e: Exception) {
            logger.error("分页查询指定状态任务失败", ("status", status), ("error", e.message))
            return Array<TaskData>()
        }
    }

    /**
     * 更新任务参数
     */
    public static func updateTaskParameters(id: Int64, parameters: String): Bool {
        let logger = getLogger("task_dao")
        try {
            let result = DatabaseConfig.driver().exec("UPDATE tasks SET parameters = $1 WHERE id = $2", [DbText(parameters), DbInt(id)])
            logger.debug("更新任务参数", ("id", id.toString()), ("parameters", parameters))
            if (result > 0) {
                TaskEventHub.getInstance().publishTaskChanged(id)
            }
            return result > 0
        } catch (e: Exception) {
            logger.error("更新任务参数失败", ("id", id.toString()), ("error", e.message))
            return false
        }
    }

    /**
     * 更新任务类型
     */
    public static func updateTaskType(id: Int64, taskType: String): Bool {
        let logger = getLogger("task_dao")
        try {
            let result = DatabaseConfig.driver().exec("UPDATE tasks SET task_type = $1 WHERE id = $2", [DbText(taskType), DbInt(id)])
            if (result > 0) {
                TaskEventHub.getInstance().publishTaskChanged(id)
            }
            return result > 0
        } catch (e: Exception) {
            logger.error("更新任务类型失败", ("id", id.toString()), ("error", e.message))
            return false
        }
    }

    /**
     * 更新任务的插件命名空间
     */
    public static func updateTaskPluginNamespace(id: Int64, pluginNamespace: String): Bool {
        let logger = getLogger("task_dao")
        try {
            let result = DatabaseConfig.driver().exec("UPDATE tasks SET plugin_namespace = $1 WHERE id = $2", [DbText(pluginNamespace), DbInt(id)])
            if (result > 0) {
                TaskEventHub.getInstance().publishTaskChanged(id)
            }
            return result > 0
        } catch (e: Exception) {
            logger.error("更新任务插件命名空间失败", ("id", id.toString()), ("error", e.message))
            return false
        }
    }

    /**
     * 恢复非终态任务（服务重启时调用）
     * 将running状态的任务标记为failed，因为进程已重启，这些任务未真正完成
     */
    public static func recoverOrphanedTasks(): Int64 {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                UPDATE tasks
                SET status = 'failed',
                    message = '服务端重启，任务未完成',
                    progress = 0,
                    completed_at = CURRENT_TIMESTAMP
                WHERE status NOT IN ('completed', 'failed', 'stopped')
                RETURNING id
            """, [])
            let recoveredIds = ArrayList<Int64>()
            for (r in rows) {
                recoveredIds.add(r.getInt("id"))
            }
            let rowCount = Int64(recoveredIds.size)
            for (taskId in recoveredIds) {
                if (taskId > 0) {
                    TaskEventHub.getInstance().publishTaskChanged(taskId)
                }
            }
            logger.debug("恢复孤儿任务完成", [("count", rowCount.toString())])
            return rowCount
        } catch (e: Exception) {
            logger.error("恢复孤儿任务失败", ("error", e.message))
            return 0
        }
    }

    /**
     * 检查最近时间内是否存在指定类型和触发源的任务（防重复）
     */
    public static func hasRecentTask(taskType: String, triggerSource: String, withinSeconds: Int32): Bool {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COUNT(*) FROM tasks
                WHERE task_type = $1
                AND trigger_source = $2
                AND created_at >= NOW() - ($3 * INTERVAL '1 second')
            """, [DbText(taskType), DbText(triggerSource), DbInt(Int64(withinSeconds))])
            if (rows.size > 0) {
                let count = rows[0].getInt("count")
                return count > 0
            } else {
                return false
            }
        } catch (e: Exception) {
            logger.error("检查最近任务失败", ("error", e.message))
            return false
        }
    }

    /**
     * 按 trigger_source 查询任务
     */
    public static func getTasksByTriggerSource(triggerSource: String, limit: Int32): Array<TaskData> {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                       priority, group_id, timeout_at, trigger_source,
                       created_at, started_at, completed_at, phase, waiting_reason, active_key
                FROM tasks
                WHERE trigger_source = $1
                ORDER BY created_at DESC
                LIMIT $2
            """, [DbText(triggerSource), DbInt(Int64(limit))])
            let taskList = ArrayList<TaskData>()
            for (r in rows) {
                taskList.add(mapRowToTaskData(r))
            }
            return taskList.toArray()
        } catch (e: Exception) {
            logger.error("按触发源查询任务失败", ("error", e.message))
            return Array<TaskData>()
        }
    }

    /**
     * 按 group_id 查询任务
     */
    public static func getTasksByGroupId(groupId: String): Array<TaskData> {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                       priority, group_id, timeout_at, trigger_source,
                       created_at, started_at, completed_at, phase, waiting_reason, active_key
                FROM tasks
                WHERE group_id = $1
                ORDER BY created_at ASC
            """, [DbText(groupId)])
            let taskList = ArrayList<TaskData>()
            for (r in rows) {
                taskList.add(mapRowToTaskData(r))
            }
            return taskList.toArray()
        } catch (e: Exception) {
            logger.error("按分组ID查询任务失败", ("error", e.message))
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

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT 1
                FROM tasks
                WHERE group_id = $1
                  AND status NOT IN ('completed', 'failed', 'stopped')
                LIMIT 1
            """, [DbText(groupId)])
            return rows.size > 0
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 查询指定类型与 group_id 是否已存在活动任务。
     */
    public static func existsActiveTaskByTypeAndGroupId(taskType: String, groupId: String): Bool {
        if (taskType.trimAscii().size == 0 || groupId.trimAscii().size == 0) {
            return false
        }

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT 1
                FROM tasks
                WHERE task_type = $1
                  AND group_id = $2
                  AND status IN ('pending', 'running', 'waiting')
                LIMIT 1
            """, [DbText(taskType), DbText(groupId)])
            return rows.size > 0
        } catch (_: Exception) {
            return false
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

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT 1
                FROM tasks
                WHERE active_key = $1
                  AND status IN ('pending', 'running', 'waiting')
                LIMIT 1
            """, [DbText(normalized)])
            return rows.size > 0
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 批量更新任务状态（用于批量取消）
     */
    public static func updateTaskStatusByGroupId(groupId: String, status: String, message: String): Int64 {
        let logger = getLogger("task_dao")
        try {
            let rowCount = DatabaseConfig.driver().exec("""
                UPDATE tasks
                SET status = $1, message = $2, completed_at = CURRENT_TIMESTAMP
                WHERE group_id = $3 AND status IN ('pending', 'running')
            """, [DbText(status), DbText(message), DbText(groupId)])
            logger.debug("批量更新任务状态", ("group_id", groupId), ("count", rowCount.toString()))
            return rowCount
        } catch (e: Exception) {
            logger.error("批量更新任务状态失败", ("error", e.message))
            return 0
        }
    }

    /**
     * 领取一个待执行任务（原子地将pending置为running）
     */
    public static func claimNextPendingTask(): Option<TaskData> {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
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
            """, [])
            if (rows.size > 0) {
                let r = rows[0]
                let data = TaskData()
                data.id = r.getInt("id")
                data.name = r.getText("name")
                data.taskType = r.getText("task_type")
                data.status = r.getText("status")
                data.progress = Int32(r.getInt("progress"))
                data.message = r.getText("message")
                data.pluginNamespace = r.getText("plugin_namespace")
                data.parameters = r.getText("parameters")
                data.result = r.getText("result")
                data.priority = Int32(r.getInt("priority"))
                data.groupId = r.getText("group_id")
                data.timeoutAt = r.getText("timeout_at")
                data.triggerSource = r.getText("trigger_source")
                data.createdAt = r.getText("created_at")
                data.startedAt = r.getText("started_at")
                data.completedAt = r.getText("completed_at")
                return Option<TaskData>.Some(data)
            }
            return Option<TaskData>.None
        } catch (e: Exception) {
            logger.error("领取待执行任务失败", ("error", e.message))
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

        try {
            let rows = DatabaseConfig.driver().query("""
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
                    LIMIT $1
                )
                AND status = 'pending'
                RETURNING id, name, task_type, status, progress, message,
                          plugin_namespace, parameters, result,
                          priority, group_id, timeout_at, trigger_source,
                          created_at, started_at, completed_at, phase, waiting_reason, active_key
            """, [DbInt(Int64(limit))])
            for (r in rows) {
                result.add(mapRowToTaskData(r))
            }
            for (task in result) {
                if (task.id > 0) {
                    TaskEventHub.getInstance().publishTaskChanged(task.id)
                }
            }
            return result
        } catch (e: Exception) {
            logger.error("批量领取待执行任务失败", ("error", e.message))
            return result
        }
    }

    /**
     * 创建等待状态的任务（条件驱动）
     * 任务创建后处于 waiting 状态，等待 waitForTaskId 指定的任务完成后自动转为 pending
     */
    public static func createWaitingTaskData(data: TaskData, waitForTaskId: Int64): Bool {
        let logger = getLogger("task_dao")
        try {
            data.phase = "awaiting_dependency"
            data.waitingReason = "task_dependency"
            let rows = DatabaseConfig.driver().query("""
                INSERT INTO tasks (name, task_type, status, progress, message, plugin_namespace, parameters, result, priority, group_id, timeout_at, trigger_source, wait_for_task_id, started_at, completed_at, phase, waiting_reason, active_key)
                VALUES ($1, $2, 'waiting', $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NULL, NULL, $13, $14, $15) RETURNING id
            """, [
                DbText(data.name),
                DbText(data.taskType),
                DbInt(Int64(data.progress)),
                DbText(data.message),
                DbText(data.pluginNamespace),
                DbText(data.parameters),
                DbText(data.result),
                DbInt(Int64(data.priority)),
                if (data.groupId.size > 0) { DbText(data.groupId) } else { DbNull },
                if (data.timeoutAt.size > 0) { DbText(data.timeoutAt) } else { DbNull },
                if (data.triggerSource.size > 0) { DbText(data.triggerSource) } else { DbNull },
                DbInt(waitForTaskId),
                DbText(data.phase),
                DbText(data.waitingReason),
                if (data.activeKey.size > 0) { DbText(data.activeKey) } else { DbNull }
            ])
            if (rows.size > 0) {
                data.id = rows[0].getInt("id")
                data.status = "waiting"
                data.waitForTaskId = waitForTaskId
                logger.info("创建等待任务", ("id", data.id.toString()),
                    ("wait_for", waitForTaskId.toString()))
                return true
            }
            return false
        } catch (e: Exception) {
            logger.error("创建等待任务失败", ("error", e.message))
            return false
        }
    }

    /**
     * 查询等待指定任务完成的所有任务
     */
    public static func getTasksWaitingFor(taskId: Int64): Array<TaskData> {
        let logger = getLogger("task_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, name, task_type, status, progress, message, plugin_namespace, parameters, result,
                       priority, group_id, timeout_at, trigger_source, wait_for_task_id,
                       created_at, started_at, completed_at, phase, waiting_reason, active_key
                FROM tasks
                WHERE wait_for_task_id = $1 AND status = 'waiting'
            """, [DbInt(taskId)])
            let taskList = ArrayList<TaskData>()
            for (r in rows) {
                taskList.add(mapRowToTaskDataWithWaitFor(r))
            }
            return taskList.toArray()
        } catch (e: Exception) {
            logger.error("查询等待任务失败", ("error", e.message))
            return Array<TaskData>()
        }
    }

    /**
     * 激活等待任务（将 waiting 状态转为 pending）
     */
    public static func activateWaitingTask(taskId: Int64): Bool {
        let logger = getLogger("task_dao")
        try {
            let result = DatabaseConfig.driver().exec("""
                UPDATE tasks SET status = 'pending', message = '依赖任务已完成，等待执行', phase = 'queued', waiting_reason = NULL
                WHERE id = $1 AND status = 'waiting'
            """, [DbInt(taskId)])
            if (result > 0) {
                logger.debug("激活等待任务", ("id", taskId.toString()))
                let eventHub = TaskEventHub.getInstance()
                eventHub.publishTaskChanged(taskId)
                eventHub.publishWaitingActivated(taskId)
                return true
            }
            return false
        } catch (e: Exception) {
            logger.error("激活等待任务失败", ("id", taskId.toString()), ("error", e.message))
            return false
        }
    }

    /**
     * 将等待任务标记为失败（依赖任务失败时调用）
     */
    public static func failWaitingTask(taskId: Int64, errorMessage: String): Bool {
        let logger = getLogger("task_dao")
        try {
            let result = DatabaseConfig.driver().exec("""
                UPDATE tasks SET status = 'failed', message = $1, completed_at = CURRENT_TIMESTAMP
                WHERE id = $2 AND status = 'waiting'
            """, [DbText(errorMessage), DbInt(taskId)])
            if (result > 0) {
                logger.debug("等待任务标记失败", ("id", taskId.toString()))
                TaskEventHub.getInstance().publishTaskChanged(taskId)
                return true
            }
            return false
        } catch (e: Exception) {
            logger.error("标记等待任务失败", ("id", taskId.toString()), ("error", e.message))
            return false
        }
    }
}