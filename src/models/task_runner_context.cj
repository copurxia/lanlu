package lrr4cj.models

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
 * Task 组 KV 存储接口
 *
 * 具体实现放在 services/dao 层，避免 models <-> dao 循环依赖。
 */
public interface TaskKVStore {
    func acquireGroup(groupId: String): Unit
    func releaseGroup(groupId: String): Unit
    func set(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool
    func get(groupId: String, key: String): Option<String>
    func delete(groupId: String, key: String): Bool
    func hasGroup(groupId: String): Bool
    func getKeys(groupId: String): Array<String>
}

/**
 * TaskRunner 上下文，包含运行时所需的所有依赖
 */
public class TaskRunnerContext {
    public let paths: TaskRunnerPaths
    public let notifyTaskAvailable: TaskNotifier
    public let kvStore: TaskKVStore

    public init(
        paths: TaskRunnerPaths,
        notifyTaskAvailable: TaskNotifier,
        kvStore: TaskKVStore
    ) {
        this.paths = paths
        this.notifyTaskAvailable = notifyTaskAvailable
        this.kvStore = kvStore
    }
}
