package lrr4cj.models

import lrr4cj.dao.*
import lrr4cj.utils.*
import lrr4cj.config.*
import std.database.sql.*
import std.collection.*
import std.time.*

/**
 * Task任务数据模型
 */
public class Task {
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
    public var priority: Int32
    public var groupId: String
    public var timeoutAt: String
    public var triggerSource: String
    public var waitForTaskId: Int64  // 条件驱动：等待指定任务完成后才能执行

    public init(id: Int64, name: String, status: String, progress: Int32, message: String,
                taskType!: String = "", pluginNamespace!: String = "", parameters!: String = "",
                result!: String = "", createdAt!: String = "", startedAt!: String = "",
                completedAt!: String = "", priority!: Int32 = 50, groupId!: String = "",
                timeoutAt!: String = "", triggerSource!: String = "", waitForTaskId!: Int64 = 0) {
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
        this.priority = priority
        this.groupId = groupId
        this.timeoutAt = timeoutAt
        this.triggerSource = triggerSource
        this.waitForTaskId = waitForTaskId
    }

    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        var json = "{"
        json += "\"id\":${id},"
        json += "\"name\":\"${escapeJsonString(name)}\","
        json += "\"status\":\"${escapeJsonString(status)}\","
        json += "\"progress\":${progress},"
        json += "\"message\":\"${escapeJsonString(message)}\","
        json += "\"taskType\":\"${escapeJsonString(taskType)}\","
        json += "\"pluginNamespace\":\"${escapeJsonString(pluginNamespace)}\","
        // parameters 可能是字符串或JSON字符串，需要根据内容判断
        json += "\"parameters\":"
        if (parameters.size > 0 && parameters[0] == 123) {
            // 如果是JSON对象，直接拼接
            json += "${parameters},"
        } else {
            // 如果是普通字符串，用引号包围
            json += "\"${escapeJsonString(parameters)}\","
        }
        json += "\"result\":\"${escapeJsonString(result)}\","
        json += "\"createdAt\":\"${escapeJsonString(createdAt)}\","
        json += "\"startedAt\":\"${escapeJsonString(startedAt)}\","
        json += "\"completedAt\":\"${escapeJsonString(completedAt)}\","
        json += "\"priority\":${priority},"
        json += "\"groupId\":\"${escapeJsonString(groupId)}\","
        json += "\"timeoutAt\":\"${escapeJsonString(timeoutAt)}\","
        json += "\"triggerSource\":\"${escapeJsonString(triggerSource)}\""
        json += "}"
        return json
    }

    // 辅助函数：转义JSON字符串中的特殊字符
    private static func escapeJsonString(str: String): String {
        var escaped = str
        escaped = escaped.replace("\\", "\\\\")  // 转义反斜杠
        escaped = escaped.replace("\"", "\\\"")   // 转义双引号
        escaped = escaped.replace("\b", "\\b")    // 转义退格
        escaped = escaped.replace("\f", "\\f")    // 转义换页
        escaped = escaped.replace("\n", "\\n")    // 转义换行
        escaped = escaped.replace("\r", "\\r")    // 转义回车
        escaped = escaped.replace("\t", "\\t")    // 转义制表符
        return escaped
    }
}

/**
 * Task任务分页结果
 */
public class TaskPageResult {
    public var tasks: Array<Task>
    public var total: Int32
    public var page: Int32
    public var pageSize: Int32
    public var totalPages: Int32

    public init() {
        this.tasks = Array<Task>()
        this.total = 0
        this.page = 1
        this.pageSize = 10
        this.totalPages = 0
    }

    public init(tasks: Array<Task>, total: Int32, page: Int32, pageSize: Int32) {
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
 * Task数据访问层
 */
public class TaskModel {
    // 注意：数据库表初始化已由迁移系统处理
    // 原 initialize()、fixTableSchema() 和 ensureColumnExists() 方法已移除
    // 请参考 src/migrations/versions/v001_initial_schema.cj

    /**
     * 根据ID获取任务
     */
    public static func getTaskById(id: Int64): Task {
        let logger = getLogger("task_model")
        logger.debug("根据ID获取任务", [("id", id.toString())])
        let data = TaskDao.getTaskDataById(id)
        let task = convertToTask(data)

        // 从任务IO读取日志与最终输出（如果存在则覆盖DB中的message/result）
        if (task.id != 0) {
            let ioLog = TaskIO.readLog(task.id)
            if (ioLog.size > 0) {
                task.message = ioLog
            }
            let ioOutput = TaskIO.readOutput(task.id)
            if (ioOutput.size > 0) {
                task.result = ioOutput
            }
        }

        return task
    }

    /**
     * 分页获取任务列表
     */
    public static func getTasksWithPagination(page: Int32, pageSize: Int32): TaskPageResult {
        let logger = getLogger("task_model")
        logger.info("分页获取任务列表", [("page", page.toString()), ("pageSize", pageSize.toString())])

        // 获取总数
        let total = TaskDao.getTaskCount()

        // 计算偏移量
        let offset = (page - 1) * pageSize

        // 获取分页数据
        let tasksData = TaskDao.getTasksWithPagination(offset, pageSize)

        // 转换为Task数组
        var taskList = ArrayList<Task>()
        for (taskData in tasksData) {
            taskList.add(convertToTask(taskData))
        }
        // 转换 ArrayList 为 Array
        let taskListSize = taskList.size
        var tasks = Array<Task>()
        if (taskListSize > 0) {
            tasks = Array<Task>(taskListSize, { _ => Task(0, "", "", 0, "") })
            for (i in 0..taskListSize) {
                tasks[i] = taskList[i]
            }
        } else {
            tasks = Array<Task>()
        }

        let result = TaskPageResult(tasks, total, page, pageSize)
        logger.info("分页查询完成", [("total", total.toString()), ("returned", tasks.size.toString())])

        return result
    }

    /**
     * 创建新任务
     */
    public static func createTask(name: String, taskType: String): Task {
        let logger = getLogger("task_model")
        let currentTime = getCurrentTimeString()

        let task = Task(
            0, name, "pending", 0, "任务已创建",
            taskType: taskType, pluginNamespace: "", parameters: "",
            result: "", createdAt: currentTime, startedAt: "", completedAt: "",
            priority: 50, groupId: "", timeoutAt: "", triggerSource: "manual"
        )

        let data = convertToTaskData(task)
        let success = TaskDao.createTaskData(data)
        if (success) {
            task.id = data.id  // 设置数据库返回的自增ID
            logger.debug("创建任务成功", [("id", data.id.toString()), ("name", name)])
        } else {
            logger.error("创建任务失败", ("name", name))
        }

        return task
    }

    /**
     * 创建带参数的任务
     */
    public static func createTaskWithOptions(name: String, taskType: String, parameters: String, priority: Int32,
                                             groupId: String, triggerSource: String, timeoutSeconds!: Int32 = 0): Task {
        let logger = getLogger("task_model")
        let currentTime = getCurrentTimeString()

        let timeoutAt = calculateTimeoutAt(timeoutSeconds)

        let task = Task(
            0, name, "pending", 0, "任务已创建",
            taskType: taskType, pluginNamespace: "", parameters: parameters,
            result: "", createdAt: currentTime, startedAt: "", completedAt: "",
            priority: priority, groupId: groupId, timeoutAt: timeoutAt, triggerSource: triggerSource
        )

        let data = convertToTaskData(task)
        let success = TaskDao.createTaskData(data)
        if (success) {
            task.id = data.id
            logger.info("创建任务成功", [("id", data.id.toString()), ("name", name), ("task_type", taskType)])
        } else {
            logger.error("创建任务失败", ("name", name), ("task_type", taskType))
        }

        return task
    }

    /**
     * 创建任务（完整版，单次数据库操作）
     * 适用于需要同时设置 parameters、progress、message 的场景
     * 减少数据库连接次数，提升性能
     */
    public static func createTaskFull(
        name: String,
        taskType: String,
        parameters: String,
        progress: Int32,
        message: String
    ): Task {
        let logger = getLogger("task_model")
        let currentTime = getCurrentTimeString()

        let idOpt = TaskDao.createTaskDataFull(
            name,
            taskType,
            "running",
            progress,
            message,
            parameters,
            50,
            "manual"
        )

        match (idOpt) {
            case Some(id) =>
                logger.debug("创建完整任务成功", ("id", id.toString()), ("name", name))
                return Task(
                    id, name, "running", progress, message,
                    taskType: taskType, pluginNamespace: "", parameters: parameters,
                    result: "", createdAt: currentTime, startedAt: "",
                    completedAt: "", priority: 50, groupId: "",
                    timeoutAt: "", triggerSource: "manual"
                )
            case None =>
                logger.error("创建完整任务失败", ("name", name))
                return Task(
                    0, name, "failed", 0, "创建任务失败",
                    taskType: taskType, pluginNamespace: "", parameters: "",
                    result: "", createdAt: currentTime, startedAt: "",
                    completedAt: "", priority: 50, groupId: "",
                    timeoutAt: "", triggerSource: "manual"
                )
        }
    }

    private static func calculateTimeoutAt(timeoutSeconds: Int32): String {
        if (timeoutSeconds <= 0) {
            return ""
        }
        // TODO: 根据需要实现时间推算，这里暂返回空字符串以保持兼容
        return ""
    }

    /**
     * 启动任务
     */
    public static func startTask(id: Int64): Bool {
        let logger = getLogger("task_model")
        let success = TaskDao.updateTaskStatus(id, "running", "任务已启动", 0)
        if (success) {
            logger.debug("启动任务成功", ("id", id.toString()))
        } else {
            logger.error("启动任务失败", ("id", id.toString()))
        }
        return success
    }

    /**
     * 停止任务
     */
    public static func stopTask(id: Int64): Bool {
        let logger = getLogger("task_model")
        let success = TaskDao.updateTaskStatus(id, "stopped", "任务已停止", 0)
        if (success) {
            logger.debug("停止任务成功", ("id", id.toString()))
        } else {
            logger.error("停止任务失败", ("id", id.toString()))
        }
        return success
    }

    /**
     * 删除任务
     */
    public static func deleteTask(id: Int64): Bool {
        let logger = getLogger("task_model")
        let success = TaskDao.deleteTask(id)
        if (success) {
            logger.debug("删除任务成功", ("id", id.toString()))
        } else {
            logger.error("删除任务失败", ("id", id.toString()))
        }
        return success
    }

    /**
     * 更新任务进度
     */
    public static func updateTaskProgress(id: Int64, progress: Int32, message: String): Bool {
        let logger = getLogger("task_model")
        let success = TaskDao.updateTaskStatus(id, "running", message, progress)
        if (success) {
            logger.debug("更新任务进度", [("id", id.toString()), ("progress", progress.toString())])
        } else {
            logger.error("更新任务进度失败", ("id", id.toString()), ("progress", progress.toString()))
        }
        return success
    }

    /**
     * 完成任务
     */
    public static func completeTask(id: Int64, result: String): Bool {
        let logger = getLogger("task_model")
        let data = TaskDao.getTaskDataById(id)
        if (data.id == 0) {
            logger.error("任务不存在，无法完成", ("id", id.toString()))
            return false
        }

        data.status = "completed"
        data.progress = 100
        data.message = "任务完成"
        data.result = result
        data.completedAt = getCurrentTimeString()

        let success = TaskDao.updateTaskData(data)
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
        let logger = getLogger("task_model")
        let data = TaskDao.getTaskDataById(id)
        if (data.id == 0) {
            logger.error("任务不存在，无法标记失败", ("id", id.toString()))
            return false
        }

        data.status = "failed"
        data.message = errorMessage
        data.completedAt = getCurrentTimeString()

        let success = TaskDao.updateTaskData(data)
        if (success) {
            logger.debug("任务失败标记成功", ("id", id.toString()), ("error", errorMessage))
        } else {
            logger.error("任务失败标记失败", ("id", id))
        }
        return success
    }

    /**
     * TaskData转换为Task
     */
      private static func convertToTask(data: TaskData): Task {
        return Task(
            data.id, data.name, data.status, data.progress, data.message,
            taskType: data.taskType, pluginNamespace: data.pluginNamespace,
            parameters: data.parameters, result: data.result,
            createdAt: data.createdAt, startedAt: data.startedAt, completedAt: data.completedAt,
            priority: data.priority, groupId: data.groupId, timeoutAt: data.timeoutAt,
            triggerSource: data.triggerSource, waitForTaskId: data.waitForTaskId
        )
    }

    /**
     * Task转换为TaskData
     */
    private static func convertToTaskData(task: Task): TaskData {
        let data = TaskData()
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
        data.priority = task.priority
        data.groupId = task.groupId
        data.timeoutAt = task.timeoutAt
        data.triggerSource = task.triggerSource
        data.waitForTaskId = task.waitForTaskId
        return data
    }

    /**
     * 创建等待状态的任务（条件驱动）
     * 任务创建后处于 waiting 状态，等待 waitForTaskId 指定的任务完成后自动转为 pending
     */
    public static func createWaitingTask(
        name: String,
        taskType: String,
        parameters: String,
        waitForTaskId: Int64,
        groupId: String,
        triggerSource: String
    ): Task {
        let logger = getLogger("task_model")
        let currentTime = getCurrentTimeString()

        let data = TaskData()
        data.name = name
        data.taskType = taskType
        data.progress = 0
        data.message = "等待依赖任务完成"
        data.parameters = parameters
        data.priority = 50
        data.groupId = groupId
        data.triggerSource = triggerSource

        let success = TaskDao.createWaitingTaskData(data, waitForTaskId)
        if (success) {
            logger.info("创建等待任务成功", ("id", data.id.toString()), ("wait_for", waitForTaskId.toString()))
            return Task(
                data.id, name, "waiting", 0, "等待依赖任务完成",
                taskType: taskType, parameters: parameters,
                createdAt: currentTime, priority: 50, groupId: groupId,
                triggerSource: triggerSource, waitForTaskId: waitForTaskId
            )
        } else {
            logger.error("创建等待任务失败", ("name", name))
            return Task(0, name, "failed", 0, "创建任务失败", taskType: taskType)
        }
    }



    /**
     * 获取当前时间字符串
     */
    private static func getCurrentTimeString(): String {
        return DateTime.now().toString()
    }
}
