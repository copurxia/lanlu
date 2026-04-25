package lanlu.contexts.task.application

import std.collection.*
import std.sync.*
import lanlu.shared.utils.*

/**
 * Strongly typed internal TaskPool mailbox event.
 */
public enum TaskPoolEvent {
    Start
    | TaskAvailable
    | SafetyTick
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
    private var events: ArrayList<TaskPoolEvent>

    public init() {
        mutex = Mutex()
        mutex.lock()
        cond = mutex.condition()
        mutex.unlock()
        events = ArrayList<TaskPoolEvent>()
    }

    public func put(event: TaskPoolEvent): Unit {
        mutex.lock()
        try {
            events.add(event)
            if (Int64(events.size) > TaskPoolMailbox.pressureThreshold) {
                getLogger("taskpool").warn(
                    "TaskPool mailbox pressure threshold exceeded",
                    ("queued_events", events.size.toString())
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
            let _ = cond.waitUntil({ => events.size > 0 })
            return events.remove(at: 0)
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
