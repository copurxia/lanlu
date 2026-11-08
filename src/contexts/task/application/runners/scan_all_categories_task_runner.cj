package lanlu.contexts.task.application.runners

import std.collection.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

/**
 * 扫描所有分类任务运行器
 * 负责列出所有启用的分类并为每个分类创建扫描任务
 */
public class ScanAllCategoriesTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("scan_all_categories")
        TaskIO.appendLog(taskId, "scan_all_categories task started")
        TaskIO.appendLog(taskId, "Task parameters: ${parameters}")

        try {
            TaskModel.updateTaskProgress(taskId, 10, "获取启用的分类列表...")
            let categories = CategoryDao.getEnabledCategories()

            if (categories.size == 0) {
                let summary = "{\"success\":1,\"created\":0,\"total\":0,\"message\":\"No enabled categories found\"}"
                TaskIO.appendLog(taskId, "No enabled categories found")
                TaskModel.updateTaskProgress(taskId, 100, "No enabled categories found")
                TaskModel.completeTask(taskId, summary)
                TaskIO.writeOutput(taskId, summary)
                return
            }

            TaskIO.appendLog(taskId, "Found ${categories.size} enabled categories")
            TaskModel.updateTaskProgress(taskId, 20, "准备创建分类扫描任务...")

            var created = 0
            var errors = ArrayList<String>()
            let groupId = "scan_all_categories:${taskId}"
            var dispatchRequested = false

            // 为每个分类创建 scan_single_category 任务
            for (cat in categories) {
                let taskIdStr = enqueueSingleCategoryScan(cat, groupId)
                if (taskIdStr > 0) {
                    created++
                    dispatchRequested = true
                    TaskIO.appendLog(taskId, "Created scan_single_category task for category: ${cat.name} (task_id: ${taskIdStr})")
                } else {
                    let error = "Failed to create task for category: ${cat.name}"
                    errors.add(error)
                    TaskIO.appendLog(taskId, "ERROR: ${error}")
                }
            }

            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(1)
            w.writeName("created").writeValue(created)
            w.writeName("total").writeValue(categories.size)
            w.writeName("errors").writeValue(errors.size)
            w.endObject()
            w.flush()
            let summary = String.fromUtf8(readToEnd(out))
            if (dispatchRequested) {
                context.requestDispatch()
            }
            TaskIO.appendLog(taskId, "Task creation completed: created=${created}, total=${categories.size}, errors=${errors.size}")
            TaskModel.updateTaskProgress(taskId, 100, "Created ${created} scan_single_category tasks")
            TaskModel.completeTask(taskId, summary)
            TaskIO.writeOutput(taskId, summary)
            TaskIO.appendLog(taskId, "scan_all_categories task completed")
        } catch (e: Exception) {
            let errorMsg = "Unexpected error: ${e.message}"
            logger.error(errorMsg, ("exception", e.message), ("stack", e.toString()))
            TaskIO.appendLog(taskId, "FATAL ERROR: ${errorMsg}")
            TaskRunnerOutput.fail(taskId, errorMsg)
        }
    }

    private static func enqueueSingleCategoryScan(category: CategoryData, groupId: String): Int64 {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("category_id").writeValue(category.catid)
        w.endObject()
        w.flush()
        let params = String.fromUtf8(readToEnd(out))
        let triggerSource = "scan_all_categories"
        let childTask = TaskModel.createTaskWithOptions(
            "扫描分类: ${category.name}",
            "scan_single_category",
            params,
            30,
            groupId,
            triggerSource
        )
        return childTask.id
    }

}
