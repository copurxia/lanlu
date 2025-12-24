package lrr4cj.services

import std.convert.*
import stdx.encoding.json.*
import std.fs.*
import std.sync.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*

/**
 * 目录扫描任务：发现归档文件并创建 scan_archive 子任务
 * 使用 DirectoryScanner 工具类进行文件扫描
 */
public class ScanDirectoryTaskRunner {
    // 配置 - 使用静态变量存储配置
    private static var archivePath: Path = Path("")
    private static var cachePath: Path = Path("")
    private static var thumbnailPath: Path = Path("")
    private static var initialized: Bool = false
    private static let initMutex: Mutex = Mutex()

    // 私有初始化方法（懒加载）
    private static func ensureInitialized(): Unit {
        initMutex.lock()
        if (!initialized) {
            try {
                // 从数据库读取配置
                let archivePathStr = SystemSettingsService.getPath("ARCHIVE_PATH")
                let cachePathStr = SystemSettingsService.getPath("CACHE_PATH")
                let thumbnailPathStr = SystemSettingsService.getPath("THUMBNAIL_PATH")

                // 先确保目录存在，然后规范化路径
                // 注意：canonicalize() 要求路径存在，否则会失败
                let archivePathTemp = Path(archivePathStr)
                let cachePathTemp = Path(cachePathStr)
                let thumbnailPathTemp = Path(thumbnailPathStr)
                FileUtils.ensureDirectoryExists(archivePathTemp)
                FileUtils.ensureDirectoryExists(cachePathTemp)
                FileUtils.ensureDirectoryExists(thumbnailPathTemp)

                // 转换为 Path 类型并规范化
                archivePath = canonicalize(archivePathStr)
                cachePath = canonicalize(cachePathStr)
                thumbnailPath = canonicalize(thumbnailPathStr)

                initialized = true
            } catch (e: Exception) {
                // 即使初始化失败，也设置为 true 避免死锁
                initialized = true
                throw e
            }
        }
        initMutex.unlock()
    }

    public static func run(taskId: Int64, parameters: String): Unit {
        let logger = getLogger("scan_directory_task")
        TaskIO.appendLog(taskId, "scan_directory task started")
        TaskIO.appendLog(taskId, "Task parameters: ${parameters}")

        try {
            // 确保配置已初始化
            TaskIO.appendLog(taskId, "Initializing configuration...")
            ensureInitialized()
            TaskIO.appendLog(taskId, "Configuration initialized successfully")
            TaskIO.appendLog(taskId, "Archive path: ${archivePath.toString()}")
            TaskIO.appendLog(taskId, "Cache path: ${cachePath.toString()}")
            TaskIO.appendLog(taskId, "Thumbnail path: ${thumbnailPath.toString()}")

            let (scanPathParam, triggerSourceParam, childPriorityParam) = parseParameters(parameters)
            let scanPath = if (scanPathParam.size > 0) { scanPathParam } else { archivePath.toString() }
            let triggerSource = if (triggerSourceParam.size > 0) { triggerSourceParam } else { "manual" }
            let childPriority = if (childPriorityParam > 0) { childPriorityParam } else { 30i32 }

            TaskIO.appendLog(taskId, "Parsed parameters: scanPath=${scanPath}, triggerSource=${triggerSource}, childPriority=${childPriority}")
            TaskModel.updateTaskProgress(taskId, 5, "Scanning directory ${scanPath}")

            TaskIO.appendLog(taskId, "Starting directory scan...")
            // 使用 DirectoryScanner 进行文件扫描（与 scan_plugins 使用相同的文件系统操作方法）
            let archiveFiles = DirectoryScanner.findArchiveFiles(scanPath)
            let total = archiveFiles.size
            TaskIO.appendLog(taskId, "Found ${total} archive candidates in ${scanPath}")

            if (total == 0) {
                let summary = "{\"success\":1,\"created\":0,\"total\":0}"
                TaskIO.appendLog(taskId, "No archives found, completing task")
                TaskModel.updateTaskProgress(taskId, 100, "No archives found")
                TaskModel.completeTask(taskId, summary)
                TaskIO.writeOutput(taskId, summary)
                TaskIO.appendLog(taskId, "scan_directory task completed with no files")
                return
            }

            var created: Int64 = 0
            let groupId = "scan_directory:${taskId}"
            TaskIO.appendLog(taskId, "Creating scan_archive tasks for ${total} files...")

            for (filePath in archiveFiles) {
                if (enqueueScanArchiveTask(filePath, groupId, triggerSource, childPriority)) {
                    created++
                }
            }

            let summary = "{\"success\":1,\"created\":${created},\"total\":${total}}"
            TaskIO.appendLog(taskId, "Task creation completed: created=${created}, total=${total}")
            TaskModel.updateTaskProgress(taskId, 100, "Created ${created} scan_archive tasks")
            TaskModel.completeTask(taskId, summary)
            TaskIO.writeOutput(taskId, summary)
            TaskIO.appendLog(taskId, "scan_directory task completed: created=${created}, total=${total}")
        } catch (e: Exception) {
            let errorMsg = "Unexpected error: ${e.message}"
            logger.error(errorMsg, ("exception", e.message), ("stack", e.toString()))
            TaskIO.appendLog(taskId, "FATAL ERROR: ${errorMsg}")
            TaskIO.appendLog(taskId, "Stack trace: ${e.toString()}")
            TaskModel.failTask(taskId, errorMsg)
            TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(errorMsg)}\"}")
        }
    }

    private static func enqueueScanArchiveTask(filePath: String, groupId: String, triggerSource: String, priority: Int32): Bool {
        // 计算相对路径和文件名，用于检查档案是否已存在
        let relativePath = ArchiveUtils.calculateRelativePath(filePath, archivePath.toString())
        let fileName = ArchiveUtils.getFullFileName(filePath)

        // 检查档案是否已存在于数据库中
        let existingArchive = ArchiveDao.getByPathAndFilename(relativePath, fileName)
        match (existingArchive) {
            case Some(archive) =>
                if (archive.thumbhash.size > 0) {
                    // 档案已存在且已生成thumbhash，跳过
                    getLogger("scan_directory").debug("Archive already exists with thumbnail, skipping: ${filePath}")
                    return false
                } else {
                    // 档案存在但没有thumbhash，仍需处理
                    getLogger("scan_directory").debug("Archive exists but no thumbnail, will process: ${filePath}")
                }
            case None =>
                getLogger("scan_directory").debug("Archive not found in database, will process: ${filePath}")
        }

        // 获取配置
        let archiveBasePath = archivePath.toString()
        let cachePathStr = cachePath.toString()
        let thumbnailPathStr = thumbnailPath.toString()

        // 检测归档类型
        let archiveType = detectArchiveType(filePath)

        let params = "{\"archive_path\":\"${escapeJson(filePath)}\",\"archive_base_path\":\"${escapeJson(archiveBasePath)}\",\"cache_path\":\"${escapeJson(cachePathStr)}\",\"thumbnail_path\":\"${escapeJson(thumbnailPathStr)}\",\"archive_type\":\"${archiveType}\"}"
        let childTask = TaskModel.createTaskWithOptions("扫描档案", "scan_archive", params, priority, groupId, triggerSource)
        if (childTask.id > 0) {
            TaskPoolService.getInstance().notifyTaskAvailable()
            return true
        }
        return false
    }

    /**
     * 检测归档类型
     */
    private static func detectArchiveType(filePath: String): String {
        // 检查是否为目录
        if (DirectoryScanner.isDirectory(filePath)) {
            return "folder"
        }

        // 检查文件扩展名
        let ext = DirectoryScanner.getFileExtension(filePath)
        if (ext == "pdf") {
            return "pdf"
        }

        // 默认为压缩包
        return "archive"
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
