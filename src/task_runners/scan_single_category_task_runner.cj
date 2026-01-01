package lrr4cj.task_runners

import std.fs.*
import std.convert.*
import stdx.log.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*

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
            let catid = catidParam

            TaskIO.appendLog(taskId, "Parsed parameters: scanPath=${scanPath}, triggerSource=${triggerSource}, childPriority=${childPriority}, categoryId=${catid}")
            TaskModel.updateTaskProgress(taskId, 10, "Scanning directory ${scanPath}")

            TaskIO.appendLog(taskId, "Starting directory scan...")
            let archiveFiles = DirectoryScanner.findArchiveFiles(scanPath)
            let total = archiveFiles.size
            TaskIO.appendLog(taskId, "Found ${total} archive candidates in ${scanPath}")

            if (total == 0) {
                let summary = "{\"success\":1,\"created\":0,\"total\":0}"
                TaskIO.appendLog(taskId, "No archives found, completing task")
                TaskModel.updateTaskProgress(taskId, 100, "No archives found")
                TaskModel.completeTask(taskId, summary)
                TaskIO.writeOutput(taskId, summary)
                TaskIO.appendLog(taskId, "scan_single_category task completed with no files")
                return
            }

            var created: Int64 = 0
            let groupId = "scan_single_category:${taskId}"
            TaskIO.appendLog(taskId, "Creating scan_archive tasks for ${total} files...")
            TaskModel.updateTaskProgress(taskId, 50, "Creating scan_archive tasks...")

            for (filePath in archiveFiles) {
                if (enqueueScanArchiveTask(filePath, groupId, triggerSource, childPriority, catid, scanPath, context.notifyTaskAvailable)) {
                    created++
                }
            }

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

    private static func enqueueScanArchiveTask(filePath: String, groupId: String, triggerSource: String, priority: Int32, catid: String, basePath: String, notifier: TaskNotifier): Bool {
        let relativePath = ArchiveUtils.calculateRelativePath(filePath, basePath)
        let fileName = ArchiveUtils.getFullFileName(filePath)

        let existingArchive = ArchiveDao.getByPathAndFilename(relativePath, fileName)
        match (existingArchive) {
            case Some(archive) =>
                if (archive.thumbhash.size > 0) {
                    getLogger("scan_single_category").debug("Archive already exists with thumbnail, skipping: ${filePath}")
                    return false
                } else {
                    getLogger("scan_single_category").debug("Archive exists but no thumbnail, will process: ${filePath}")
                }
            case None =>
                getLogger("scan_single_category").debug("Archive not found in database, will process: ${filePath}")
        }

        let params = "{\"archive_path\":\"${escapeJson(filePath)}\",\"category_id\":\"${escapeJson(catid)}\"}"
        let childTask = TaskModel.createTaskWithOptions("扫描档案", "scan_archive", params, priority, groupId, triggerSource)
        if (childTask.id > 0) {
            notifier()
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
