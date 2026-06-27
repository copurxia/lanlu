package lanlu.shared.utils

import std.fs.*
import std.collection.*
import std.sync.*

/**
 * 任务IO：用于存储任务日志与最终输出（避免塞进数据库字段）
 *
 * 日志写入采用按 taskId 缓存的常驻 Append 句柄，任务运行期间复用同一个
 * 文件描述符，避免每次 appendLog 都 open/close fd，降低并发任务下的 fd 压力。
 * 任务结束后由调度层调用 closeHandle(taskId) 释放句柄。
 */
public class TaskIO {
    // 新目录：与 ./data/logs/plugins.log 保持一致，统一放到 data/logs 下
    private static let rootDir: Path = Path("./data/logs/task")

    // 按 taskId 缓存的常驻 Append 句柄；任务运行期间复用，避免高频开关 fd
    private static let handles: HashMap<Int64, File> = HashMap<Int64, File>()
    private static let handlesMutex: Mutex = Mutex()

    private static func ensureReady(): Unit {
        if (!exists(rootDir)) {
            Directory.create(rootDir, recursive: true)
        }
    }

    public static func getLogPath(taskId: Int64): Path {
        ensureReady()
        return Path("${rootDir.toString()}/task_${taskId}.log")
    }

    public static func getOutputPath(taskId: Int64): Path {
        ensureReady()
        return Path("${rootDir.toString()}/task_${taskId}.out")
    }

    /**
     * 取（缓存命中）或创建 taskId 对应的 Append 句柄。
     * 缓存命中时直接复用，避免 open/close；句柄由 closeHandle(taskId) 统一释放。
     */
    private static func openOrCachedHandle(taskId: Int64, logPath: Path): File {
        synchronized(handlesMutex) {
            match (handles.get(taskId)) {
                case Some(f) =>
                    // 复用缓存的常驻句柄
                    return f
                case None =>
                    let f = File(logPath, OpenMode.Append)
                    handles[taskId] = f
                    return f
            }
        }
    }

    public static func appendLog(taskId: Int64, line: String): Unit {
        try {
            let logPath = getLogPath(taskId)
            let file = openOrCachedHandle(taskId, logPath)
            unsafe { file.write((line + "\n").rawData()) }
            file.flush()
            TaskEventHub.getInstance().publishLogAppended(taskId)
        } catch (_: Exception) {
            // 忽略IO异常，避免影响任务主流程
        }
    }

    /**
     * 任务结束后释放 taskId 对应的常驻句柄。
     * 由调度层（TaskPool）在 worker 完成时调用，避免句柄长期占用 fd。
     */
    public static func closeHandle(taskId: Int64): Unit {
        synchronized(handlesMutex) {
            match (handles.get(taskId)) {
                case Some(f) =>
                    try { f.close() } catch (_: Exception) {}
                    handles.remove(taskId)
                case None => ()
            }
        }
    }

    public static func writeOutput(taskId: Int64, content: String): Unit {
        try {
            let outputPath = getOutputPath(taskId)
            let file = File(outputPath, Write)
            try {
                unsafe { file.write(content.rawData()) }
                file.flush()
            } finally {
                try { file.close() } catch (_: Exception) {}
            }
            TaskEventHub.getInstance().publishOutputWritten(taskId)
        } catch (_: Exception) {
            // 忽略IO异常，避免影响任务主流程
        }
    }

    public static func readLog(taskId: Int64, maxBytes!: Int64 = 200 * 1024): String {
        return readText(getLogPath(taskId), maxBytes)
    }

    public static func readOutput(taskId: Int64, maxBytes!: Int64 = 200 * 1024): String {
        return readText(getOutputPath(taskId), maxBytes)
    }

    private static func readText(path: Path, maxBytes: Int64): String {
        try {
            if (!exists(path)) {
                return ""
            }
            let file = File(path, Read)
            try {
                // 读取固定大小（避免一次性读超大文件）
                let capped = if (maxBytes < 1) { 1 } else if (maxBytes > 1024 * 1024) { 1024 * 1024 } else { maxBytes }
                let buffer = Array<Byte>(capped, {_ => 0})
                let bytesRead = file.read(buffer)
                if (bytesRead <= 0) {
                    return ""
                }
                return String.fromUtf8(buffer.slice(0, bytesRead))
            } finally {
                try { file.close() } catch (_: Exception) {}
            }
        } catch (_: Exception) {
            return ""
        }
    }
}