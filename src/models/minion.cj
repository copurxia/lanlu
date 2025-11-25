package lrr4cj.models

import lrr4cj.dao.*
import lrr4cj.utils.*
import lrr4cj.config.*
import std.collection.*
import std.time.*
import std.random.*

/**
 * Minion任务数据模型
 */
public class MinionTask {
    public var id: Int64
    public var name: String
    public var status: String
    public var progress: Int32
    public var message: String

    // 扩展字段
    public var taskType: String
    public var pluginNamespace: String
    public var parameters: String
    public var result: String
    public var createdAt: String
    public var startedAt: String
    public var completedAt: String

    public init(id: Int64, name: String, status: String, progress: Int32, message: String,
                taskType!: String = "", pluginNamespace!: String = "", parameters!: String = "",
                result!: String = "", createdAt!: String = "", startedAt!: String = "",
                completedAt!: String = "") {
        this.id = id
        this.name = name
        this.status = status
        this.progress = progress
        this.message = message
        this.taskType = taskType
        this.pluginNamespace = pluginNamespace
        this.parameters = parameters
        this.result = result
        this.createdAt = createdAt
        this.startedAt = startedAt
        this.completedAt = completedAt
    }

    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        var json = "{"
        json += "\"id\":${id},"
        json += "\"name\":\"${name}\","
        json += "\"status\":\"${status}\","
        json += "\"progress\":${progress},"
        json += "\"message\":\"${message}\","
        json += "\"taskType\":\"${taskType}\","
        json += "\"pluginNamespace\":\"${pluginNamespace}\","
        json += "\"parameters\":\"${parameters}\","
        json += "\"result\":\"${result}\","
        json += "\"createdAt\":\"${createdAt}\","
        json += "\"startedAt\":\"${startedAt}\","
        json += "\"completedAt\":\"${completedAt}\""
        json += "}"
        return json
    }
}

/**
 * Minion任务分页结果
 */
public class MinionTaskPageResult {
    public var tasks: Array<MinionTask>
    public var total: Int32
    public var page: Int32
    public var pageSize: Int32
    public var totalPages: Int32

    public init() {
        this.tasks = Array<MinionTask>()
        this.total = 0
        this.page = 1
        this.pageSize = 10
        this.totalPages = 0
    }

    public init(tasks: Array<MinionTask>, total: Int32, page: Int32, pageSize: Int32) {
        this.tasks = tasks
        this.total = total
        this.page = page
        this.pageSize = pageSize
        this.totalPages = (total + pageSize - 1) / pageSize  // 向上取整
    }

    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        var json = "{"
        json += "\"tasks\":["
        for (i in 0..tasks.size) {
            if (i > 0) { json += "," }
            json += tasks[i].toJson()
        }
        json += "],"
        json += "\"total\":${total},"
        json += "\"page\":${page},"
        json += "\"pageSize\":${pageSize},"
        json += "\"totalPages\":${totalPages}"
        json += "}"
        return json
    }
}

/**
 * Minion数据访问层
 */
public class MinionModel {
    /**
     * 初始化数据库表
     */
    public static func initialize(): Bool {
        let logger = getLogger("minion_model")
        logger.info("初始化Minion任务数据库表")

        let tableCreated = MinionTaskDao.createTable()
        if (!tableCreated) {
            logger.error("创建minion_tasks表失败")
            return false
        }

        // 检查并修复表结构
        return fixTableSchema()
    }

    /**
     * 检查并修复表结构
     */
    private static func fixTableSchema(): Bool {
        let logger = getLogger("minion_model")
        let connOpt = DatabaseConfig.createConnection()

        match (connOpt) {
            case Some(conn) =>
                try {
                    // 检查message列是否存在
                    let checkMessageColumn = conn.prepareStatement("SELECT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'minion_tasks' AND column_name = 'message')")
                    let messageRs = checkMessageColumn.query()
                    var messageColumnExists = false
                    try {
                        if (messageRs.next()) {
                            messageColumnExists = messageRs.getOrNull<Bool>(0) ?? false
                        }
                    } finally {
                        messageRs.close()
                        checkMessageColumn.close()
                    }

                    if (!messageColumnExists) {
                        logger.info("添加缺失的message列")
                        let addMessageSql = "ALTER TABLE minion_tasks ADD COLUMN message TEXT"
                        let addStmt = conn.prepareStatement(addMessageSql)
                        let addResult = addStmt.update()
                        addStmt.close()
                        logger.info("message列添加成功")
                    } else {
                        logger.info("message列已存在，表结构正确")
                    }

                    return true
                } catch (e: Exception) {
                    logger.error("检查/修复表结构失败", ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法获取数据库连接")
                return false
        }
    }

    /**
     * 根据ID获取任务
     */
    public static func getTaskById(id: Int64): MinionTask {
        let logger = getLogger("minion_model")
        logger.info("根据ID获取任务", [("id", id.toString())])
        let data = MinionTaskDao.getTaskDataById(id)
        return convertToMinionTask(data)
    }

    /**
     * 分页获取任务列表
     */
    public static func getTasksWithPagination(page: Int32, pageSize: Int32): MinionTaskPageResult {
        let logger = getLogger("minion_model")
        logger.info("分页获取任务列表", [("page", page.toString()), ("pageSize", pageSize.toString())])

        // 获取总数
        let total = MinionTaskDao.getTaskCount()

        // 计算偏移量
        let offset = (page - 1) * pageSize

        // 获取分页数据
        let tasksData = MinionTaskDao.getTasksWithPagination(offset, pageSize)

        // 转换为MinionTask数组
        var taskList = ArrayList<MinionTask>()
        for (taskData in tasksData) {
            taskList.add(convertToMinionTask(taskData))
        }
        // 转换 ArrayList 为 Array
        let taskListSize = taskList.size
        var tasks = Array<MinionTask>()
        if (taskListSize > 0) {
            tasks = Array<MinionTask>(taskListSize, { i => MinionTask(0, "", "", 0, "") })
            for (i in 0..taskListSize) {
                tasks[i] = taskList[i]
            }
        } else {
            tasks = Array<MinionTask>(0, { i => MinionTask(0, "", "", 0, "") })
        }

        let result = MinionTaskPageResult(tasks, total, page, pageSize)
        logger.info("分页查询完成", [("total", total.toString()), ("returned", tasks.size.toString())])

        return result
    }

    /**
     * 创建新任务
     */
    public static func createTask(name: String, taskType: String): MinionTask {
        let logger = getLogger("minion_model")
        let currentTime = getCurrentTimeString()

        let task = MinionTask(
            0, name, "pending", 0, "任务已创建",
            taskType: taskType, pluginNamespace: "", parameters: "",
            result: "", createdAt: currentTime, startedAt: "", completedAt: ""
        )

        let data = convertToMinionTaskData(task)
        let success = MinionTaskDao.createTaskData(data)
        if (success) {
            task.id = data.id  // 设置数据库返回的自增ID
            logger.info("创建任务成功", [("id", data.id.toString()), ("name", name)])
        } else {
            logger.error("创建任务失败", ("name", name))
        }

        return task
    }

    /**
     * 启动任务
     */
    public static func startTask(id: Int64): Bool {
        let logger = getLogger("minion_model")
        let success = MinionTaskDao.updateTaskStatus(id, "running", "任务已启动", 0)
        if (success) {
            logger.info("启动任务成功", ("id", id.toString()))
        } else {
            logger.error("启动任务失败", ("id", id.toString()))
        }
        return success
    }

    /**
     * 停止任务
     */
    public static func stopTask(id: Int64): Bool {
        let logger = getLogger("minion_model")
        let success = MinionTaskDao.updateTaskStatus(id, "stopped", "任务已停止", 0)
        if (success) {
            logger.info("停止任务成功", ("id", id.toString()))
        } else {
            logger.error("停止任务失败", ("id", id.toString()))
        }
        return success
    }

    /**
     * 删除任务
     */
    public static func deleteTask(id: Int64): Bool {
        let logger = getLogger("minion_model")
        let success = MinionTaskDao.deleteTask(id)
        if (success) {
            logger.info("删除任务成功", ("id", id.toString()))
        } else {
            logger.error("删除任务失败", ("id", id.toString()))
        }
        return success
    }

    /**
     * 更新任务进度
     */
    public static func updateTaskProgress(id: Int64, progress: Int32, message: String): Bool {
        let logger = getLogger("minion_model")
        let success = MinionTaskDao.updateTaskStatus(id, "running", message, progress)
        if (success) {
            logger.info("更新任务进度", [("id", id.toString()), ("progress", progress.toString())])
        } else {
            logger.error("更新任务进度失败", ("id", id.toString()), ("progress", progress.toString()))
        }
        return success
    }

    /**
     * 完成任务
     */
    public static func completeTask(id: Int64, result: String): Bool {
        let logger = getLogger("minion_model")
        let data = MinionTaskDao.getTaskDataById(id)
        if (data.id == 0) {
            logger.error("任务不存在，无法完成", ("id", id.toString()))
            return false
        }

        data.status = "completed"
        data.progress = 100
        data.message = "任务完成"
        data.result = result
        data.completedAt = getCurrentTimeString()

        let success = MinionTaskDao.updateTaskData(data)
        if (success) {
            logger.info("完成任务成功", ("id", id))
        } else {
            logger.error("完成任务失败", ("id", id))
        }
        return success
    }

    /**
     * 任务失败
     */
    public static func failTask(id: Int64, errorMessage: String): Bool {
        let logger = getLogger("minion_model")
        let data = MinionTaskDao.getTaskDataById(id)
        if (data.id == 0) {
            logger.error("任务不存在，无法标记失败", ("id", id.toString()))
            return false
        }

        data.status = "failed"
        data.message = errorMessage
        data.completedAt = getCurrentTimeString()

        let success = MinionTaskDao.updateTaskData(data)
        if (success) {
            logger.info("任务失败标记成功", ("id", id.toString()), ("error", errorMessage))
        } else {
            logger.error("任务失败标记失败", ("id", id))
        }
        return success
    }

    /**
     * MinionTaskData转换为MinionTask
     */
      private static func convertToMinionTask(data: MinionTaskData): MinionTask {
        return MinionTask(
            data.id, data.name, data.status, data.progress, data.message,
            taskType: data.taskType, pluginNamespace: data.pluginNamespace,
            parameters: data.parameters, result: data.result,
            createdAt: data.createdAt, startedAt: data.startedAt, completedAt: data.completedAt
        )
    }

    /**
     * MinionTask转换为MinionTaskData
     */
    private static func convertToMinionTaskData(task: MinionTask): MinionTaskData {
        let data = MinionTaskData()
        data.id = task.id
        data.name = task.name
        data.taskType = task.taskType
        data.status = task.status
        data.progress = task.progress
        data.message = task.message
        data.pluginNamespace = task.pluginNamespace
        data.parameters = task.parameters
        data.result = task.result
        data.createdAt = task.createdAt
        data.startedAt = task.startedAt
        data.completedAt = task.completedAt
        return data
    }

    /**
     * 生成任务ID
     */
    private static func generateTaskId(): String {
        // 使用时间戳和随机数生成唯一的任务ID，确保不超过36字符
        let timestamp = DateTime.now().toString().replace("-", "").replace(" ", "").replace(":", "").replace(".", "").replace("+", "")
        let shortTime = if (timestamp.size > 20) {
            timestamp[0..20]
        } else {
            timestamp
        }
        let randomSuffix = Random(5).nextBits(8).toString()
        return "task_${shortTime}_${randomSuffix}"
    }

    /**
     * 获取当前时间字符串
     */
    private static func getCurrentTimeString(): String {
        return DateTime.now().toString()
    }
}