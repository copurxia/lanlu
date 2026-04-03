package lanlu.shared.utils

import std.collection.*
import std.sync.*
import std.time.*

private let TASK_EVENT_TOPIC_TTL_MILLIS: Int64 = 30 * 60 * 1000

private class TaskEventTopic {
    public let mutex: Mutex
    public let cond: Condition
    public var revision: Int64
    public var lastTouchedMillis: Int64
    public var lastEventType: String

    public init() {
        mutex = Mutex()
        mutex.lock()
        cond = mutex.condition()
        mutex.unlock()
        revision = 0
        lastTouchedMillis = TaskEventHub.nowMillis()
        lastEventType = "init"
    }
}

public class TaskEventSnapshot {
    public let revision: Int64
    public let changed: Bool
    public let eventType: String

    public init(revision: Int64, changed: Bool, eventType!: String = "heartbeat") {
        this.revision = revision
        this.changed = changed
        this.eventType = eventType
    }
}

/**
 * 进程内任务事件中心，仅负责唤醒等待方。
 */
public class TaskEventHub {
    private static var instance: Option<TaskEventHub> = Option.None
    private static let instanceMutex: Mutex = Mutex()

    private let topicsMutex: Mutex = Mutex()
    private var topics: HashMap<Int64, TaskEventTopic>

    private init() {
        topics = HashMap<Int64, TaskEventTopic>()
    }

    public static func getInstance(): TaskEventHub {
        instanceMutex.lock()
        match (instance) {
            case Some(s) =>
                instanceMutex.unlock()
                return s
            case None =>
                let hub = TaskEventHub()
                instance = Some(hub)
                instanceMutex.unlock()
                return hub
        }
    }

    public func currentRevision(taskId: Int64): Int64 {
        let topic = getOrCreateTopic(taskId)
        topic.mutex.lock()
        try {
            topic.lastTouchedMillis = TaskEventHub.nowMillis()
            return topic.revision
        } finally {
            topic.mutex.unlock()
        }
    }

    public func awaitNext(taskId: Int64, lastRevision: Int64, timeoutMillis: Int64): TaskEventSnapshot {
        let topic = getOrCreateTopic(taskId)
        topic.mutex.lock()
        try {
            topic.lastTouchedMillis = TaskEventHub.nowMillis()
            if (topic.revision != lastRevision) {
                return TaskEventSnapshot(topic.revision, true, eventType: topic.lastEventType)
            }

            let waitMillis = if (timeoutMillis <= 0) { 1 } else { timeoutMillis }
            let _ = topic.cond.waitUntil(
                { => topic.revision != lastRevision },
                timeout: Duration.millisecond * waitMillis
            )
            topic.lastTouchedMillis = TaskEventHub.nowMillis()
            return TaskEventSnapshot(topic.revision, topic.revision != lastRevision, eventType: topic.lastEventType)
        } finally {
            topic.mutex.unlock()
        }
    }

    public func publishTaskChanged(taskId: Int64): Unit {
        publish(taskId, "task_changed")
    }

    public func publishLogAppended(taskId: Int64): Unit {
        publish(taskId, "log_appended")
    }

    public func publishOutputWritten(taskId: Int64): Unit {
        publish(taskId, "output_written")
    }

    public func publishTaskStarted(taskId: Int64): Unit {
        publish(taskId, "task_started")
    }

    public func publishTaskProgress(taskId: Int64): Unit {
        publish(taskId, "task_progress")
    }

    public func publishTaskWaiting(taskId: Int64): Unit {
        publish(taskId, "task_waiting")
    }

    public func publishWaitingActivated(taskId: Int64): Unit {
        publish(taskId, "waiting_activated")
    }

    private func publish(taskId: Int64, eventType: String): Unit {
        let topic = getOrCreateTopic(taskId)
        topic.mutex.lock()
        try {
            topic.revision += 1
            topic.lastTouchedMillis = TaskEventHub.nowMillis()
            topic.lastEventType = eventType
            topic.cond.notifyAll()
        } finally {
            topic.mutex.unlock()
        }
    }

    private func getOrCreateTopic(taskId: Int64): TaskEventTopic {
        topicsMutex.lock()
        try {
            pruneExpiredTopicsLocked()
            match (topics.get(taskId)) {
                case Some(topic) => return topic
                case None =>
                    let topic = TaskEventTopic()
                    topics[taskId] = topic
                    return topic
            }
        } finally {
            topicsMutex.unlock()
        }
    }

    private func pruneExpiredTopicsLocked(): Unit {
        let now = TaskEventHub.nowMillis()
        let expiredIds = ArrayList<Int64>()
        for ((taskId, topic) in topics) {
            if (now - topic.lastTouchedMillis > TASK_EVENT_TOPIC_TTL_MILLIS) {
                expiredIds.add(taskId)
            }
        }
        for (taskId in expiredIds) {
            topics.remove(taskId)
        }
    }

    public static func nowMillis(): Int64 {
        return DateTime.now().toUnixTimeStamp().toMilliseconds()
    }
}
