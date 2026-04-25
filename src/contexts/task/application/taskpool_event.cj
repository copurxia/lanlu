package lanlu.contexts.task.application

/**
 * Internal TaskPool mailbox event.
 */
public class TaskPoolEvent {
    public let eventType: String
    public let taskId: Int64
    public let workerId: Int32

    private init(eventType: String, taskId!: Int64 = 0, workerId!: Int32 = 0) {
        this.eventType = eventType
        this.taskId = taskId
        this.workerId = workerId
    }

    public static func start(): TaskPoolEvent {
        return TaskPoolEvent("start")
    }

    public static func taskAvailable(): TaskPoolEvent {
        return TaskPoolEvent("task_available")
    }

    public static func safetyTick(): TaskPoolEvent {
        return TaskPoolEvent("safety_tick")
    }

    public static func workerFinished(taskId: Int64, workerId: Int32): TaskPoolEvent {
        return TaskPoolEvent("worker_finished", taskId: taskId, workerId: workerId)
    }

    public static func reloadMaxWorkersConfig(): TaskPoolEvent {
        return TaskPoolEvent("reload_max_workers_config")
    }

    public static func reconcileRequested(): TaskPoolEvent {
        return TaskPoolEvent("reconcile_requested")
    }
}

public class TaskWorkerResult {
    public let taskId: Int64
    public let workerId: Int32

    public init(taskId: Int64, workerId: Int32) {
        this.taskId = taskId
        this.workerId = workerId
    }
}

public type TaskWorkerCompletion = (TaskWorkerResult) -> Unit
