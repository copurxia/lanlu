package lrr4cj.models

import std.sync.*
import std.collection.*
import std.time.*

/**
 * 任务通知回调类型
 */
public type TaskNotifier = () -> Unit

/**
 * TaskRunner 运行时路径配置
 */
public class TaskRunnerPaths {
    public let cachePath: String
    public let thumbnailPath: String
    public let pluginPath: String

    public init(
        cachePath!: String = "",
        thumbnailPath!: String = "",
        pluginPath!: String = ""
    ) {
        this.cachePath = cachePath
        this.thumbnailPath = thumbnailPath
        this.pluginPath = pluginPath
    }
}

/**
 * KV 存储条目
 */
public class KVEntry {
    public var value: String
    public var createdAt: Int64
    public var ttlSeconds: Int64

    public init(value: String, ttlSeconds!: Int64 = 0) {
        this.value = value
        this.createdAt = DateTime.now().toUnixTimeStamp().toSeconds()
        this.ttlSeconds = ttlSeconds
    }

    public func isExpired(): Bool {
        if (ttlSeconds <= 0) {
            return false
        }
        let now = DateTime.now().toUnixTimeStamp().toSeconds()
        return (now - createdAt) > ttlSeconds
    }
}

/**
 * Task 组 KV 存储
 */
public class TaskGroupKVStore {
    private static var instance: Option<TaskGroupKVStore> = Option.None
    private static let instanceMutex: Mutex = Mutex()

    private var stores: HashMap<String, HashMap<String, KVEntry>>
    private let storeMutex: Mutex = Mutex()
    private var groupRefCounts: HashMap<String, Int32>

    private init() {
        stores = HashMap<String, HashMap<String, KVEntry>>()
        groupRefCounts = HashMap<String, Int32>()
    }

    public static func getInstance(): TaskGroupKVStore {
        instanceMutex.lock()
        match (instance) {
            case Some(s) =>
                instanceMutex.unlock()
                return s
            case None =>
                let s = TaskGroupKVStore()
                instance = Some(s)
                instanceMutex.unlock()
                return s
        }
    }

    public func acquireGroup(groupId: String): Unit {
        storeMutex.lock()
        match (groupRefCounts.get(groupId)) {
            case Some(count) =>
                groupRefCounts[groupId] = count + 1
            case None =>
                groupRefCounts[groupId] = 1
                stores[groupId] = HashMap<String, KVEntry>()
        }
        storeMutex.unlock()
    }

    public func releaseGroup(groupId: String): Unit {
        storeMutex.lock()
        match (groupRefCounts.get(groupId)) {
            case Some(count) =>
                if (count <= 1) {
                    groupRefCounts.remove(groupId)
                    stores.remove(groupId)
                } else {
                    groupRefCounts[groupId] = count - 1
                }
            case None => ()
        }
        storeMutex.unlock()
    }

    public func set(groupId: String, key: String, value: String, ttlSeconds!: Int64 = 0): Bool {
        storeMutex.lock()
        match (stores.get(groupId)) {
            case Some(store) =>
                store[key] = KVEntry(value, ttlSeconds: ttlSeconds)
                storeMutex.unlock()
                return true
            case None =>
                storeMutex.unlock()
                return false
        }
    }

    public func get(groupId: String, key: String): Option<String> {
        storeMutex.lock()
        match (stores.get(groupId)) {
            case Some(store) =>
                match (store.get(key)) {
                    case Some(entry) =>
                        if (entry.isExpired()) {
                            store.remove(key)
                            storeMutex.unlock()
                            return Option.None
                        }
                        let value = entry.value
                        storeMutex.unlock()
                        return Option<String>.Some(value)
                    case None =>
                        storeMutex.unlock()
                        return Option.None
                }
            case None =>
                storeMutex.unlock()
                return Option.None
        }
    }

    public func delete(groupId: String, key: String): Bool {
        storeMutex.lock()
        match (stores.get(groupId)) {
            case Some(store) =>
                store.remove(key)
                storeMutex.unlock()
                return true
            case None =>
                storeMutex.unlock()
                return false
        }
    }

    public func hasGroup(groupId: String): Bool {
        storeMutex.lock()
        let exists = stores.contains(groupId)
        storeMutex.unlock()
        return exists
    }

    public func getKeys(groupId: String): Array<String> {
        storeMutex.lock()
        match (stores.get(groupId)) {
            case Some(store) =>
                var keys = ArrayList<String>()
                for ((k, _) in store) {
                    keys.add(k)
                }
                storeMutex.unlock()
                return keys.toArray()
            case None =>
                storeMutex.unlock()
                return Array<String>()
        }
    }
}

/**
 * TaskRunner 上下文，包含运行时所需的所有依赖
 */
public class TaskRunnerContext {
    public let paths: TaskRunnerPaths
    public let notifyTaskAvailable: TaskNotifier
    public let kvStore: TaskGroupKVStore

    public init(
        paths: TaskRunnerPaths,
        notifyTaskAvailable: TaskNotifier,
        kvStore: TaskGroupKVStore
    ) {
        this.paths = paths
        this.notifyTaskAvailable = notifyTaskAvailable
        this.kvStore = kvStore
    }
}
