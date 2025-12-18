package lrr4cj.services

import std.convert.*
import stdx.encoding.json.*
import std.fs.*
import lrr4cj.models.*
import lrr4cj.utils.*
import dotenv.Dotenv

/**
 * 目录扫描任务：发现归档文件并创建 scan_archive 子任务
 * 使用 DirectoryScanner 工具类进行文件扫描
 */
public class ScanDirectoryTaskRunner {
    // 配置 - 使用静态变量存储配置
    private static var archivePath: Path
    private static var cachePath: Path
    private static var thumbnailPath: Path
    private static var bsdtarPath: String

    // 静态初始化器
    static init() {
        let config = Dotenv.createConfig()

        // 读取配置
        let archivePathStr = config.read("ARCHIVE_PATH", "./data/archive")
        let cachePathStr = config.read("CACHE_PATH", "./data/cache")
        let thumbnailPathStr = config.read("THUMBNAIL_PATH", "./data/thumb")
        bsdtarPath = config.read("BSDTAR_PATH", "bsdtar")

        // 转换为 Path 类型并规范化
        archivePath = canonicalize(archivePathStr)
        cachePath = canonicalize(cachePathStr)
        thumbnailPath = canonicalize(thumbnailPathStr)

        // 确保必要的目录存在
        FileUtils.ensureDirectoryExists(archivePath)
        FileUtils.ensureDirectoryExists(cachePath)
        FileUtils.ensureDirectoryExists(thumbnailPath)
    }

    public static func run(taskId: Int64, parameters: String): Unit {
        TaskIO.appendLog(taskId, "scan_directory task started")

        let (scanPathParam, triggerSourceParam, childPriorityParam) = parseParameters(parameters)
        let scanPath = if (scanPathParam.size > 0) { scanPathParam } else { archivePath.toString() }
        let triggerSource = if (triggerSourceParam.size > 0) { triggerSourceParam } else { "manual" }
        let childPriority = if (childPriorityParam > 0) { childPriorityParam } else { 30i32 }

        MinionModel.updateTaskProgress(taskId, 5, "Scanning directory ${scanPath}")

        // 使用 DirectoryScanner 进行文件扫描（与 scan_plugins 使用相同的文件系统操作方法）
        let archiveFiles = DirectoryScanner.findArchiveFiles(scanPath)
        let total = archiveFiles.size
        TaskIO.appendLog(taskId, "Found ${total} archive candidates in ${scanPath}")

        if (total == 0) {
            let summary = "{\"success\":1,\"created\":0,\"total\":0}"
            MinionModel.updateTaskProgress(taskId, 100, "No archives found")
            MinionModel.completeTask(taskId, summary)
            TaskIO.writeOutput(taskId, summary)
            TaskIO.appendLog(taskId, "scan_directory task completed with no files")
            return
        }

        var created: Int64 = 0
        let groupId = "scan_directory:${taskId}"

        for (filePath in archiveFiles) {
            if (enqueueScanArchiveTask(filePath, groupId, triggerSource, childPriority)) {
                created++
            }
        }

        let summary = "{\"success\":1,\"created\":${created},\"total\":${total}}"
        MinionModel.updateTaskProgress(taskId, 100, "Created ${created} scan_archive tasks")
        MinionModel.completeTask(taskId, summary)
        TaskIO.writeOutput(taskId, summary)
        TaskIO.appendLog(taskId, "scan_directory task completed: created=${created}, total=${total}")
    }

    private static func enqueueScanArchiveTask(filePath: String, groupId: String, triggerSource: String, priority: Int32): Bool {
        // 获取配置
        let archiveBasePath = archivePath.toString()
        let cachePathStr = cachePath.toString()
        let thumbnailPathStr = thumbnailPath.toString()

        let params = "{\"archive_path\":\"${escapeJson(filePath)}\",\"archive_base_path\":\"${escapeJson(archiveBasePath)}\",\"cache_path\":\"${escapeJson(cachePathStr)}\",\"thumbnail_path\":\"${escapeJson(thumbnailPathStr)}\",\"bsdtar_path\":\"${escapeJson(bsdtarPath)}\"}"
        let childTask = MinionModel.createTaskWithOptions("扫描档案", "scan_archive", params, priority, groupId, triggerSource)
        if (childTask.id > 0) {
            TaskPoolService.getInstance().notifyTaskAvailable()
            return true
        }
        return false
    }

    private static func parseParameters(parameters: String): (String, String, Int32) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", 30)
        }
        var scanPath = ""
        var triggerSource = ""
        var childPriority: Int32 = 30
        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("scan_path")) {
                        let value = fields["scan_path"]
                        match (value) {
                            case str: JsonString => scanPath = str.getValue().trimAscii()
                            case _ => throw Exception("scan_path must be a string")
                        }
                    }
                    if (fields.contains("trigger_source")) {
                        let value = fields["trigger_source"]
                        match (value) {
                            case str: JsonString => triggerSource = str.getValue().trimAscii()
                            case _ => throw Exception("trigger_source must be a string")
                        }
                    }
                    if (fields.contains("child_priority")) {
                        let priorityStr = fields["child_priority"].toString().trimAscii()
                        childPriority = try {
                            Int32.parse(priorityStr)
                        } catch (_) {
                            30
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {}
        return (scanPath, triggerSource, childPriority)
    }

    private static func escapeJson(s: String): String {
        var escaped = s
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }
}
