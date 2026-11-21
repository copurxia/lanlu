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
    private let listTopic: TaskEventTopic

    private init() {
        topics = HashMap<Int64, TaskEventTopic>()
        listTopic = TaskEventTopic()
    }

    public static func getInstance(): TaskEventHub {
        return synchronized(instanceMutex) {
            match (instance) {
                case Some(s) => s
                case None =>
                    let hub = TaskEventHub()
                    instance = Some(hub)
                    hub
            }
        }
    }

    public func currentRevision(taskId: Int64): Int64 {
        let topic = getOrCreateTopic(taskId)
        return synchronized(topic.mutex) {
            topic.lastTouchedMillis = TaskEventHub.nowMillis()
            topic.revision
        }
    }

    public func awaitNext(taskId: Int64, lastRevision: Int64, timeoutMillis: Int64): TaskEventSnapshot {
        let topic = getOrCreateTopic(taskId)
        return synchronized(topic.mutex) {
            topic.lastTouchedMillis = TaskEventHub.nowMillis()
            if (topic.revision != lastRevision) {
                TaskEventSnapshot(topic.revision, true, eventType: topic.lastEventType)
            } else {
                let waitMillis = if (timeoutMillis <= 0) { 1 } else { timeoutMillis }
                let _ = topic.cond.waitUntil(
                    { => topic.revision != lastRevision },
                    timeout: Duration.millisecond * waitMillis
                )
                topic.lastTouchedMillis = TaskEventHub.nowMillis()
                TaskEventSnapshot(topic.revision, topic.revision != lastRevision, eventType: topic.lastEventType)
            }
        }
    }

    public func currentListRevision(): Int64 {
        return synchronized(listTopic.mutex) {
            listTopic.lastTouchedMillis = TaskEventHub.nowMillis()
            listTopic.revision
        }
    }

    public func awaitListNext(lastRevision: Int64, timeoutMillis: Int64): TaskEventSnapshot {
        return synchronized(listTopic.mutex) {
            listTopic.lastTouchedMillis = TaskEventHub.nowMillis()
            if (listTopic.revision != lastRevision) {
                TaskEventSnapshot(listTopic.revision, true, eventType: listTopic.lastEventType)
            } else {
                let waitMillis = if (timeoutMillis <= 0) { 1 } else { timeoutMillis }
                let _ = listTopic.cond.waitUntil(
                    { => listTopic.revision != lastRevision },
                    timeout: Duration.millisecond * waitMillis
                )
                listTopic.lastTouchedMillis = TaskEventHub.nowMillis()
                TaskEventSnapshot(listTopic.revision, listTopic.revision != lastRevision, eventType: listTopic.lastEventType)
            }
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
        synchronized(topic.mutex) {
            topic.revision += 1
            topic.lastTouchedMillis = TaskEventHub.nowMillis()
            topic.lastEventType = eventType
            topic.cond.notifyAll()
        }
        publishList(eventType)
    }

    private func publishList(eventType: String): Unit {
        synchronized(listTopic.mutex) {
            listTopic.revision += 1
            listTopic.lastTouchedMillis = TaskEventHub.nowMillis()
            listTopic.lastEventType = eventType
            listTopic.cond.notifyAll()
        }
    }

    private func getOrCreateTopic(taskId: Int64): TaskEventTopic {
        return synchronized(topicsMutex) {
            pruneExpiredTopicsLocked()
            match (topics.get(taskId)) {
                case Some(topic) => topic
                case None =>
                    let topic = TaskEventTopic()
                    topics[taskId] = topic
                    topic
            }
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
