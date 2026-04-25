package lanlu.contexts.task.application

import std.collection.*
import std.sync.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.shared.utils.*

/**
 * Strongly typed internal TaskPool mailbox event.
 */
public enum TaskPoolEvent {
    Start
    | TaskAvailable
    | SafetyTick
    | ClaimCompleted(ArrayList<TaskData>)
    | WorkerFinished(Int64, Int32)
    | ReloadMaxWorkersConfig
    | ReconcileRequested
    | Shutdown
}

/**
 * TaskPool mailbox.
 *
 * The capacity is a pressure threshold, not a hard limit. Dropping TaskPool
 * events can corrupt worker accounting, so overflow is logged and preserved.
 */
public class TaskPoolMailbox {
    private static let pressureThreshold: Int64 = 4096

    private let mutex: Mutex
    private let cond: Condition
    private var events: ArrayQueue<TaskPoolEvent>
    private var queuedCount: Int64
    private var hasQueuedTaskAvailable: Bool

    public init() {
        mutex = Mutex()
        mutex.lock()
        cond = mutex.condition()
        mutex.unlock()
        events = ArrayQueue<TaskPoolEvent>()
        queuedCount = 0
        hasQueuedTaskAvailable = false
    }

    public func put(event: TaskPoolEvent): Unit {
        mutex.lock()
        try {
            match (event) {
                case TaskAvailable =>
                    if (hasQueuedTaskAvailable) {
                        return
                    }
                    hasQueuedTaskAvailable = true
                case _ => ()
            }
            events.add(event)
            queuedCount += 1
            if (queuedCount > TaskPoolMailbox.pressureThreshold) {
                getLogger("taskpool").warn(
                    "TaskPool mailbox pressure threshold exceeded",
                    ("queued_events", queuedCount.toString())
                )
            }
            cond.notifyAll()
        } finally {
            mutex.unlock()
        }
    }

    public func take(): TaskPoolEvent {
        mutex.lock()
        try {
            while (true) {
                let _ = cond.waitUntil({ => queuedCount > 0 })
                match (events.remove()) {
                    case Some(Start) =>
                        queuedCount -= 1
                        return Start
                    case Some(TaskAvailable) =>
                        queuedCount -= 1
                        hasQueuedTaskAvailable = false
                        return TaskAvailable
                    case Some(SafetyTick) =>
                        queuedCount -= 1
                        return SafetyTick
                    case Some(ClaimCompleted(tasks)) =>
                        queuedCount -= 1
                        return ClaimCompleted(tasks)
                    case Some(WorkerFinished(taskId, workerId)) =>
                        queuedCount -= 1
                        return WorkerFinished(taskId, workerId)
                    case Some(ReloadMaxWorkersConfig) =>
                        queuedCount -= 1
                        return ReloadMaxWorkersConfig
                    case Some(ReconcileRequested) =>
                        queuedCount -= 1
                        return ReconcileRequested
                    case Some(Shutdown) =>
                        queuedCount -= 1
                        return Shutdown
                    case None =>
                        queuedCount = 0
                        hasQueuedTaskAvailable = false
                }
            }
            throw Exception("TaskPool mailbox take loop exited unexpectedly")
        } finally {
            mutex.unlock()
        }
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
