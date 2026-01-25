package lanlu.utils

import std.fs.*

/**
 * 任务IO：用于存储任务日志与最终输出（避免塞进数据库字段）
 */
public class TaskIO {
    // 新目录：与 ./data/logs/plugins.log 保持一致，统一放到 data/logs 下
    private static let rootDir: Path = Path("./data/logs/task")

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

    public static func appendLog(taskId: Int64, line: String): Unit {
        try {
            let logPath = getLogPath(taskId)
            let file = File(logPath, OpenMode.Append)
            unsafe { file.write((line + "\n").rawData()) }
            file.flush()
            file.close()
        } catch (_: Exception) {
            // 忽略IO异常，避免影响任务主流程
        }
    }

    public static func writeOutput(taskId: Int64, content: String): Unit {
        try {
            let outputPath = getOutputPath(taskId)
            let file = File(outputPath, Write)
            unsafe { file.write(content.rawData()) }
            file.flush()
            file.close()
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
            // 读取固定大小（避免一次性读超大文件）
            let capped = if (maxBytes < 1) { 1 } else if (maxBytes > 1024 * 1024) { 1024 * 1024 } else { maxBytes }
            let buffer = Array<Byte>(capped, {_ => 0})
            let bytesRead = file.read(buffer)
            file.close()
            if (bytesRead <= 0) {
                return ""
            }
            return String.fromUtf8(buffer.slice(0, bytesRead))
        } catch (_: Exception) {
            return ""
        }
    }
}
