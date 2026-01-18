package lrr4cj.kv

import std.sync.*
import std.collection.*
import lrr4cj.models.*
import lrr4cj.dao.*

/**
 * Task 组 KV 存储（DB-backed）
 *
 * 约束/语义保持与旧实现一致：
 * - 只有 acquire 过的 group 才允许 set/get/delete/getKeys
 * - release refcount 归零时删除整组 KV
 */
public class TaskGroupKVStore <: TaskKVStore {
    private static var instance: Option<TaskGroupKVStore> = Option.None
    private static let instanceMutex: Mutex = Mutex()

    private let storeMutex: Mutex = Mutex()
    private var groupRefCounts: HashMap<String, Int32>

    private init() {
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
        }
        storeMutex.unlock()
    }

    public func releaseGroup(groupId: String): Unit {
        storeMutex.lock()
        match (groupRefCounts.get(groupId)) {
            case Some(count) =>
                if (count <= 1) {
                    groupRefCounts.remove(groupId)
                    storeMutex.unlock()
                    TaskGroupKVDao.deleteGroup(groupId)
                    return
                } else {
                    groupRefCounts[groupId] = count - 1
                }
            case None => ()
        }
        storeMutex.unlock()
    }

    public func set(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        storeMutex.lock()
        let acquired = groupRefCounts.contains(groupId)
        storeMutex.unlock()
        if (!acquired) {
            return false
        }
        return TaskGroupKVDao.upsert(groupId, key, value, ttlSeconds)
    }

    public func get(groupId: String, key: String): Option<String> {
        storeMutex.lock()
        let acquired = groupRefCounts.contains(groupId)
        storeMutex.unlock()
        if (!acquired) {
            return Option.None
        }
        return TaskGroupKVDao.get(groupId, key)
    }

    public func delete(groupId: String, key: String): Bool {
        storeMutex.lock()
        let acquired = groupRefCounts.contains(groupId)
        storeMutex.unlock()
        if (!acquired) {
            return false
        }
        return TaskGroupKVDao.delete(groupId, key)
    }

    public func hasGroup(groupId: String): Bool {
        storeMutex.lock()
        let exists = groupRefCounts.contains(groupId)
        storeMutex.unlock()
        return exists
    }

    public func getKeys(groupId: String): Array<String> {
        storeMutex.lock()
        let acquired = groupRefCounts.contains(groupId)
        storeMutex.unlock()
        if (!acquired) {
            return Array<String>()
        }
        return TaskGroupKVDao.getKeys(groupId)
    }
}
