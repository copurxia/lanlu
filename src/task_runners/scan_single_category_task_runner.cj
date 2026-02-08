package lanlu.task_runners

import std.convert.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.models.*
import lanlu.utils.*
import lanlu.dao.*
import lanlu.archivehandler.*

/**
 * 扫描单个分类任务运行器
 * 负责扫描一个具体分类的目录并创建 scan_archive 子任务
 */
public class ScanSingleCategoryTaskRunner {
    private static let notifyBatchSize: Int32 = 50

    private static func summaryJsonString(created: Int64, total: Int64): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("created").writeValue(created)
        w.writeName("total").writeValue(total)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("scan_single_category")
        TaskIO.appendLog(taskId, "scan_single_category task started")
        TaskIO.appendLog(taskId, "Task parameters: ${parameters}")

        try {
            let (catidParam, triggerSourceParam, childPriorityParam) = parseParameters(parameters)
            if (catidParam.size == 0) {
                let errorMsg = "category_id is required"
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                TaskRunnerOutput.fail(taskId, errorMsg)
                return
            }

            // 获取分类信息
            var scanPath = ""
            var categoryName = ""
            match (CategoryDao.getCategoryById(catidParam)) {
                case Some(cat) =>
                    scanPath = cat.scanPath
                    categoryName = cat.name
                    TaskIO.appendLog(taskId, "Got category: ${cat.name} -> ${scanPath}")
                case None =>
                    let errorMsg = "Category not found: ${catidParam}"
                    TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                    TaskRunnerOutput.fail(taskId, errorMsg)
                    return
            }

            let triggerSource = if (triggerSourceParam.size > 0) { triggerSourceParam } else { "manual" }
            let childPriority = if (childPriorityParam > 0) { childPriorityParam } else { 30i32 }
            let categoryInternalId = CategoryDao.getInternalId(catidParam)
            if (categoryInternalId <= 0) {
                let errorMsg = "Category not found: ${catidParam}"
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                TaskRunnerOutput.fail(taskId, errorMsg)
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
            flushPendingNotifications(scanContext)

            let summary = summaryJsonString(created, total)
            TaskIO.appendLog(taskId, "Task creation completed: created=${created}, total=${total}")
            TaskModel.updateTaskProgress(taskId, 100, "Created ${created} scan_archive tasks")
            TaskModel.completeTask(taskId, summary)
            TaskIO.writeOutput(taskId, summary)
            TaskIO.appendLog(taskId, "scan_single_category task completed: created=${created}, total=${total}")

            // After scan completes, submit a category cover generation task if new tasks were created.
            if (created > 0) {
                let coverTaskId = submitCategoryCoverTask(catidParam, categoryName, triggerSource, context.notifyTaskAvailable)
                if (coverTaskId > 0) {
                    TaskIO.appendLog(taskId, "Submitted generate_category_cover task: ${coverTaskId}")
                } else {
                    TaskIO.appendLog(taskId, "WARN: failed to submit generate_category_cover task")
                }
            } else {
                TaskIO.appendLog(taskId, "No new archives; skip generate_category_cover task")
            }
        } catch (e: Exception) {
            let errorMsg = "Unexpected error: ${e.message}"
            logger.error(errorMsg, ("exception", e.message), ("stack", e.toString()))
            TaskIO.appendLog(taskId, "FATAL ERROR: ${errorMsg}")
            TaskIO.appendLog(taskId, "Stack trace: ${e.toString()}")
            TaskRunnerOutput.fail(taskId, errorMsg)
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

        // Auto-create/sync Tankoubon for qualifying directories (2+ archives, no non-archive subdirs).
        // This also performs deletion cleanup (remove items missing from filesystem).
        try {
            let relDir = ArchiveUtils.calculateRelativeDirPath(dirPath, ctx.basePath)
            TankoubonAutocreateService.ensureAndSync(ctx.categoryId, relDir, dirPath)
        } catch (_: Exception) {}

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

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("archive_path").writeValue(filePath)
        w.writeName("category_id").writeValue(ctx.categoryId)
        w.endObject()
        w.flush()
        let params = String.fromUtf8(readToEnd(out))
        let childTask = TaskModel.createTaskWithOptions("扫描档案", "scan_archive", params, ctx.priority, ctx.groupId, ctx.triggerSource)
        if (childTask.id > 0) {
            notifyTaskEnqueued(ctx)
            return true
        }
        return false
    }

    private static func notifyTaskEnqueued(ctx: ScanContext): Unit {
        ctx.enqueuedSinceNotify += 1
        if (ctx.enqueuedSinceNotify >= notifyBatchSize) {
            ctx.notifier()
            ctx.enqueuedSinceNotify = 0
        }
    }

    private static func flushPendingNotifications(ctx: ScanContext): Unit {
        if (ctx.enqueuedSinceNotify > 0) {
            ctx.notifier()
            ctx.enqueuedSinceNotify = 0
        }
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

            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("archive_path").writeValue(filePath)
            w.writeName("archive_id").writeValue(archiveId)
            w.writeName("type").writeValue(archiveType)
            w.endObject()
            w.flush()
            let parameters = String.fromUtf8(readToEnd(out))
            let task = TaskModel.createTaskWithOptions(
                "生成封面",
                "generate_thumbnail",
                parameters,
                10i32,
                archiveId,
                "scan_single_category"
            )

            if (task.id > 0) {
                notifyTaskEnqueued(ctx)
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

    private static func submitCategoryCoverTask(catid: String, categoryName: String, triggerSource: String, notifier: TaskNotifier): Int64 {
        if (catid.trimAscii().size == 0) { return 0 }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("category_id").writeValue(catid)
        w.endObject()
        w.flush()
        let params = String.fromUtf8(readToEnd(out))
        let taskName = if (categoryName.trimAscii().size > 0) { "生成分类封面: ${categoryName}" } else { "生成分类封面" }
        let task = TaskModel.createTaskWithOptions(
            taskName,
            "generate_category_cover",
            params,
            40i32,
            "category_cover:${catid}",
            triggerSource
        )
        if (task.id > 0) {
            notifier()
        }
        return task.id
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
    public var enqueuedSinceNotify: Int32 = 0

    public init(groupId: String, triggerSource: String, priority: Int32, categoryId: Int64, basePath: String, notifier: TaskNotifier) {
        this.groupId = groupId
        this.triggerSource = triggerSource
        this.priority = priority
        this.categoryId = categoryId
        this.basePath = basePath
        this.notifier = notifier
    }
}
