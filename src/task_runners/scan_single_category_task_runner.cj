package lrr4cj.task_runners

import std.convert.*
import stdx.log.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import lrr4cj.archivehandler.*

/**
 * 扫描单个分类任务运行器
 * 负责扫描一个具体分类的目录并创建 scan_archive 子任务
 */
public class ScanSingleCategoryTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("scan_single_category")
        TaskIO.appendLog(taskId, "scan_single_category task started")
        TaskIO.appendLog(taskId, "Task parameters: ${parameters}")

        try {
            let (catidParam, triggerSourceParam, childPriorityParam) = parseParameters(parameters)
            if (catidParam.size == 0) {
                let errorMsg = "category_id is required"
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                TaskModel.failTask(taskId, errorMsg)
                TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(errorMsg)}\"}")
                return
            }

            // 获取分类信息
            var scanPath = ""
            match (CategoryDao.getCategoryById(catidParam)) {
                case Some(cat) =>
                    scanPath = cat.scanPath
                    TaskIO.appendLog(taskId, "Got category: ${cat.name} -> ${scanPath}")
                case None =>
                    let errorMsg = "Category not found: ${catidParam}"
                    TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                    TaskModel.failTask(taskId, errorMsg)
                    TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(errorMsg)}\"}")
                    return
            }

            let triggerSource = if (triggerSourceParam.size > 0) { triggerSourceParam } else { "manual" }
            let childPriority = if (childPriorityParam > 0) { childPriorityParam } else { 30i32 }
            let categoryInternalId = CategoryDao.getInternalId(catidParam)
            if (categoryInternalId <= 0) {
                let errorMsg = "Category not found: ${catidParam}"
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                TaskModel.failTask(taskId, errorMsg)
                TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(errorMsg)}\"}")
                return
            }
            let groupId = "scan_single_category:${taskId}"

            TaskIO.appendLog(taskId, "Parsed parameters: scanPath=${scanPath}, triggerSource=${triggerSource}, childPriority=${childPriority}, categoryId=${categoryInternalId.toString()}")
            TaskModel.updateTaskProgress(taskId, 10, "Scanning directory ${scanPath}")

            TaskIO.appendLog(taskId, "Starting directory scan with streaming task submission...")

            // 使用流式遍历，发现即提交
            var total: Int64 = 0
            var created: Int64 = 0
            let scanContext = ScanContext(groupId, triggerSource, childPriority, categoryInternalId, scanPath, context.notifyTaskAvailable)
            let (scannedTotal, createdCount) = scanDirectoryRecursive(scanPath, scanContext)
            total = scannedTotal
            created = createdCount

            let summary = "{\"success\":1,\"created\":${created},\"total\":${total}}"
            TaskIO.appendLog(taskId, "Task creation completed: created=${created}, total=${total}")
            TaskModel.updateTaskProgress(taskId, 100, "Created ${created} scan_archive tasks")
            TaskModel.completeTask(taskId, summary)
            TaskIO.writeOutput(taskId, summary)
            TaskIO.appendLog(taskId, "scan_single_category task completed: created=${created}, total=${total}")
        } catch (e: Exception) {
            let errorMsg = "Unexpected error: ${e.message}"
            logger.error(errorMsg, ("exception", e.message), ("stack", e.toString()))
            TaskIO.appendLog(taskId, "FATAL ERROR: ${errorMsg}")
            TaskIO.appendLog(taskId, "Stack trace: ${e.toString()}")
            TaskModel.failTask(taskId, errorMsg)
            TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(errorMsg)}\"}")
        }
    }

    /**
     * 递归扫描目录，发现路径立即提交任务
     * 返回 (扫描总数, 创建任务数)
     */
    private static func scanDirectoryRecursive(dirPath: String, ctx: ScanContext): (Int64, Int64) {
        let logger = getLogger("scan_single_category")
        var total: Int64 = 0
        var created: Int64 = 0

        if (!DirectoryScanner.directoryExists(dirPath)) {
            logger.warn("Directory does not exist: ${dirPath}")
            return (total, created)
        }

        let entries = DirectoryScanner.listDirectory(dirPath)

        // Optimization: leaf media folders are treated as a single "folder archive".
        // Avoid scanning each contained media file (which would be skipped anyway) and
        // avoid redundant DirectoryScanner.listDirectory() calls inside FolderHandler.canHandle().
        if (dirPath != ctx.basePath && entries.size > 0) {
            var leafOk = true
            var hasMedia = false
            for (entry in entries) {
                let fullPath = DirectoryScanner.joinPath(dirPath, entry)
                if (DirectoryScanner.isDirectory(fullPath)) {
                    leafOk = false
                    break
                }
                if (!DirectoryScanner.fileExists(fullPath)) {
                    leafOk = false
                    break
                }
                if (FolderHandler.isAllowedMediaFileName(entry)) {
                    hasMedia = true
                } else if (FolderHandler.isAllowedAuxFileName(entry)) {
                    // Allow aux files (e.g. meta.json) in leaf media folders.
                } else {
                    leafOk = false
                    break
                }
            }

            if (leafOk && hasMedia) {
                total = Int64(entries.size)
                if (enqueueScanArchiveTask(dirPath, ctx)) {
                    created = 1
                }
                return (total, created)
            }
        }

        for (entry in entries) {
            try {
                let fullPath = DirectoryScanner.joinPath(dirPath, entry)
                total++

                if (DirectoryScanner.isDirectory(fullPath)) {
                    // Directory handling is done by recursion; folder archives are detected in the callee.
                    let (subTotal, subCreated) = scanDirectoryRecursive(fullPath, ctx)
                    total += subTotal
                    created += subCreated
                } else {
                    // Only files can be handled here (pdf/epub/archive files).
                    if (enqueueScanArchiveTask(fullPath, ctx)) {
                        created++
                    }
                }
            } catch (e: Exception) {
                logger.warn("Failed to process entry '${entry}' in ${dirPath}: ${e.message}, skipping")
            }
        }

        return (total, created)
    }

    private static func enqueueScanArchiveTask(filePath: String, ctx: ScanContext): Bool {
        // 首先检查是否有处理器能处理该文件，如果没有则直接跳过
        let factory = ArchiveHandlerFactory.getInstance()
        let handlerOpt = factory.getHandlerByPath(filePath)
        match (handlerOpt) {
            case None =>
                getLogger("scan_single_category").debug("No handler can handle this path, skipping: ${filePath}")
                return false
            case Some(_) => ()
        }

        let relativePath = ArchiveUtils.calculateRelativePath(filePath, ctx.basePath)
        let fileName = ArchiveUtils.getFullFileName(filePath)

        let existingArchive = ArchiveDao.getByPathAndFilename(relativePath, fileName)
        match (existingArchive) {
            case Some(archive) =>
                // 档案已存在
                if (archive.thumbhash.size > 0) {
                    // 已有缩略图，完全跳过
                    getLogger("scan_single_category").debug("Archive already exists with thumbnail, skipping: ${filePath}")
                    return false
                } else {
                    // 档案存在但缺少缩略图，直接提交缩略图生成任务
                    getLogger("scan_single_category").debug("Archive exists but no thumbnail, submitting thumbnail task: ${filePath}")
                    return submitThumbnailTaskDirectly(filePath, archive.id, ctx)
                }
            case None =>
                // 档案不存在，创建 scan_archive 任务进行完整处理
                getLogger("scan_single_category").debug("Archive not found, creating scan_archive task: ${filePath}")
        }

        let params = "{\"archive_path\":\"${escapeJson(filePath)}\",\"category_id\":${ctx.categoryId}}"
        let childTask = TaskModel.createTaskWithOptions("扫描档案", "scan_archive", params, ctx.priority, ctx.groupId, ctx.triggerSource)
        if (childTask.id > 0) {
            ctx.notifier()
            return true
        }
        return false
    }

    private static func parseParameters(parameters: String): (String, String, Int32) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", 30)
        }
        var catid: String = ""
        var triggerSource: String = ""
        var childPriority: Int32 = 30
        try {
            if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
                let content = trimmed[1..trimmed.size - 2]
                let pairs = content.split(",")
                for (pair in pairs) {
                    let kv = pair.split(":")
                    if (kv.size == 2) {
                        let key = kv[0].trimAscii().replace("\"", "")
                        let value = kv[1].trimAscii().replace("\"", "")
                        match (key) {
                            case "category_id" => catid = value
                            case "trigger_source" => triggerSource = value
                            case "child_priority" =>
                                childPriority = try {
                                    Int32.parse(value)
                                } catch (_) {
                                    30
                                }
                            case _ => ()
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return (catid, triggerSource, childPriority)
    }

    /**
     * 直接提交缩略图生成任务（用于已存在但缺少缩略图的档案）
     */
    private static func submitThumbnailTaskDirectly(filePath: String, archiveId: String, ctx: ScanContext): Bool {
        try {
            // 获取文件类型以传递给缩略图生成器
            let factory = ArchiveHandlerFactory.getInstance()
            let handlerOpt = factory.getHandlerByPath(filePath)
            let archiveType = match (handlerOpt) {
                case Some(handler) => handler.getType()
                case None => "archive"  // 默认类型
            }

            let parameters = "{\"archive_path\":\"${escapeJson(filePath)}\",\"archive_id\":\"${escapeJson(archiveId)}\",\"type\":\"${archiveType}\"}"
            let task = TaskModel.createTaskWithOptions(
                "生成封面",
                "generate_thumbnail",
                parameters,
                10i32,
                archiveId,
                "scan_single_category"
            )

            if (task.id > 0) {
                ctx.notifier()
                getLogger("scan_single_category").debug("Submitted thumbnail generation task for existing archive")
                return true
            } else {
                getLogger("scan_single_category").error("Failed to submit thumbnail generation task")
                return false
            }
        } catch (e: Exception) {
            getLogger("scan_single_category").error("Exception submitting thumbnail task")
            return false
        }
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

/**
 * 扫描上下文，用于传递参数到递归函数
 */
class ScanContext {
    public let groupId: String
    public let triggerSource: String
    public let priority: Int32
    public let categoryId: Int64
    public let basePath: String
    public let notifier: TaskNotifier

    public init(groupId: String, triggerSource: String, priority: Int32, categoryId: Int64, basePath: String, notifier: TaskNotifier) {
        this.groupId = groupId
        this.triggerSource = triggerSource
        this.priority = priority
        this.categoryId = categoryId
        this.basePath = basePath
        this.notifier = notifier
    }
}
