package lanlu.contexts.task.application

import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.system.application.*
import lanlu.infrastructure.kv.*
import lanlu.shared.utils.*

/**
 * Owns worker spawning and per-worker lifecycle.
 */
public class TaskWorkerExecutor {
    private let pipeline: TaskExecutionPipeline
    private let onComplete: TaskWorkerCompletion
    private let notifyTaskAvailable: TaskNotifier
    private let requestDispatch: TaskNotifier

    public init(
        pipeline: TaskExecutionPipeline,
        onComplete: TaskWorkerCompletion,
        notifyTaskAvailable: TaskNotifier,
        requestDispatch: TaskNotifier
    ) {
        this.pipeline = pipeline
        this.onComplete = onComplete
        this.notifyTaskAvailable = notifyTaskAvailable
        this.requestDispatch = requestDispatch
    }

    public func start(task: TaskData, workerId: Int32): Unit {
        let taskData = task
        let id = workerId
        spawn {
            runWorker(taskData, id)
        }
    }

    private func runWorker(task: TaskData, workerId: Int32): Unit {
        let logger = getLogger("taskpool")
        let groupId = task.groupId.trimAscii()
        let kvStore = TaskKVService.getStore()
        if (groupId.size > 0) {
            kvStore.acquireGroup(groupId)
        }

        logger.debug(
            "TaskPool worker executing",
            ("worker", workerId.toString()),
            ("task_id", task.id.toString()),
            ("task_type", task.taskType)
        )

        try {
            try {
                let context = createTaskRunnerContext(kvStore)
                pipeline.run(task, workerId, context)
            } catch (e: Exception) {
                TaskIO.appendLog(task.id, "ERROR: task worker crashed before runner completed: ${e.message}")
                if (TaskModel.failTask(task.id, "Task worker crashed: ${e.message}")) {
                    triggerDependentTasks(task.id)
                }
            }
        } finally {
            if (groupId.size > 0) {
                kvStore.releaseGroup(groupId)
            }
            onComplete(TaskWorkerResult(task.id, workerId))
        }
    }

    private func createTaskRunnerContext(kvStore: TaskKVStore): TaskRunnerContext {
        let paths = TaskRunnerPaths(
            cachePath: SystemSettingsService.getPath("CACHE_PATH"),
            assetPath: SystemSettingsService.getPath("ASSET_PATH"),
            pluginPath: SystemSettingsService.getPath("PLUGIN_PATH")
        )
        return TaskRunnerContext(paths, notifyTaskAvailable, requestDispatch, kvStore)
    }

    private func triggerDependentTasks(completedTaskId: Int64): Unit {
        let waitingTasks = TaskDao.getTasksWaitingFor(completedTaskId)
        if (waitingTasks.size == 0) {
            return
        }
        for (waitingTask in waitingTasks) {
            TaskDao.activateWaitingTask(waitingTask.id)
        }
        notifyTaskAvailable()
    }
}
