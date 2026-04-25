package lanlu.contexts.task.application

import stdx.log.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.shared.utils.*

/**
 * Shared worker execution pipeline around concrete task runners.
 */
public class TaskExecutionPipeline {
    private let registry: TaskRunnerRegistry

    public init(registry: TaskRunnerRegistry) {
        this.registry = registry
    }

    public func run(task: TaskData, workerId: Int32, context: TaskRunnerContext): Unit {
        let logger = getLogger("taskpool")
        TaskIO.appendLog(task.id, "[worker ${workerId}] start task ${task.id} type=${task.taskType}")
        TaskEventHub.getInstance().publishTaskStarted(task.id)

        try {
            try {
                let handled = registry.run(task, context)
                if (!handled) {
                    TaskIO.appendLog(task.id, "Unknown task type: ${task.taskType}")
                    TaskModel.failTask(task.id, "Unknown task type: ${task.taskType}")
                    TaskIO.writeOutput(task.id, "{\"success\":0,\"error\":\"Unknown task type: ${task.taskType}\"}")
                }
            } catch (e: Exception) {
                TaskIO.appendLog(task.id, "ERROR: task runner crashed: ${e.message}")
                TaskModel.failTask(task.id, "Task runner crashed: ${e.message}")
            }

            let latestTask = TaskDao.getTaskDataById(task.id)
            if (isTerminalStatus(latestTask.status)) {
                triggerDependentTasks(task.id, context)
            } else {
                logger.debug(
                    "Skip triggering dependents because task is not terminal",
                    ("task_id", task.id.toString()),
                    ("status", latestTask.status),
                    ("task_type", latestTask.taskType)
                )
            }
        } finally {
            logger.debug(
                "TaskPool task finished",
                ("id", task.id.toString()),
                ("type", task.taskType),
                ("worker", workerId.toString())
            )
        }
    }

    private func triggerDependentTasks(completedTaskId: Int64, context: TaskRunnerContext): Unit {
        let logger = getLogger("taskpool")
        let completedTask = TaskDao.getTaskDataById(completedTaskId)
        if (completedTask.id == 0) {
            return
        }

        let waitingTasks = TaskDao.getTasksWaitingFor(completedTaskId)
        if (waitingTasks.size == 0) {
            return
        }

        logger.debug(
            "触发依赖任务",
            ("completed_id", completedTaskId.toString()),
            ("waiting_count", waitingTasks.size.toString())
        )

        for (waitingTask in waitingTasks) {
            TaskDao.activateWaitingTask(waitingTask.id)
            logger.debug(
                "激活等待任务",
                ("id", waitingTask.id.toString()),
                ("wait_for_status", completedTask.status)
            )
        }

        context.notifyTaskAvailable()
    }

    private static func isTerminalStatus(status: String): Bool {
        return status == "completed" || status == "failed" || status == "stopped"
    }
}
