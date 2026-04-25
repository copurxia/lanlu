package lanlu.contexts.task.application

import std.collection.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.task.application.runners.*
import lanlu.contexts.plugin.application.PluginTaskService

public type TaskRunnerHandler = (Int64, String, TaskRunnerContext) -> Unit

/**
 * Registry of TaskPool runner handlers.
 */
public class TaskRunnerRegistry {
    private let handlers: HashMap<String, TaskRunnerHandler>
    private let taskTypes: Array<String>

    public init() {
        handlers = HashMap<String, TaskRunnerHandler>()
        taskTypes = [
            "upload",
            "asset_upload",
            "download_url",
            "upload_process",
            "asset_upload_process",
            "archive_asset_consume",
            "tag_asset_consume",
            "avatar_asset_consume",
            "metadata_asset_consume",
            "plugin_asset_consume",
            "metadata_plugin",
            "download_url_callback",
            "tag_import",
            "scan_all_categories",
            "scan_single_category",
            "scan_archive",
            "generate_thumbnail",
            "generate_category_cover",
            "check_database",
            "scan_plugins",
            "wasm_task",
            "metadata_plugin_callback",
            "clear_cache",
            "clear_log",
            "regenerate_cover",
            "backfill_metadata",
            "page_metadata"
        ]
        registerHandlers()
    }

    public func supportedTaskTypes(): Array<String> {
        return taskTypes
    }

    public func run(task: TaskData, context: TaskRunnerContext): Bool {
        match (handlers.get(task.taskType)) {
            case Some(handler) =>
                handler(task.id, task.parameters, context)
                return true
            case None =>
                return false
        }
    }

    private func registerHandlers(): Unit {
        handlers["upload"] = { taskId: Int64, _: String, _: TaskRunnerContext =>
            UploadPlaceholderTaskRunner.run(taskId, "upload")
        }
        handlers["asset_upload"] = { taskId: Int64, _: String, _: TaskRunnerContext =>
            UploadPlaceholderTaskRunner.run(taskId, "asset_upload")
        }
        handlers["download_url"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            DownloadUrlTaskRunner.run(taskId, parameters, context)
        }
        handlers["upload_process"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            UploadProcessTaskRunner.run(taskId, parameters, context)
        }
        handlers["asset_upload_process"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            let _ = TaskDao.extendTaskTimeout(taskId, 600)
            AssetUploadProcessTaskRunner.run(taskId, parameters, context)
        }
        handlers["archive_asset_consume"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            let _ = TaskDao.extendTaskTimeout(taskId, 600)
            ArchiveAssetConsumeTaskRunner.run(taskId, parameters, context)
        }
        handlers["tag_asset_consume"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            let _ = TaskDao.extendTaskTimeout(taskId, 600)
            TagAssetConsumeTaskRunner.run(taskId, parameters, context)
        }
        handlers["avatar_asset_consume"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            let _ = TaskDao.extendTaskTimeout(taskId, 600)
            AvatarAssetConsumeTaskRunner.run(taskId, parameters, context)
        }
        handlers["metadata_asset_consume"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            let _ = TaskDao.extendTaskTimeout(taskId, 600)
            MetadataAssetConsumeTaskRunner.run(taskId, parameters, context)
        }
        handlers["plugin_asset_consume"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            let _ = TaskDao.extendTaskTimeout(taskId, 600)
            PluginAssetConsumeTaskRunner.run(taskId, parameters, context)
        }
        handlers["metadata_plugin"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            MetadataPluginTaskRunner.run(taskId, parameters, context)
        }
        handlers["download_url_callback"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            DownloadUrlCallbackRunner.run(taskId, parameters, context)
        }
        handlers["tag_import"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            TagI18nImportTaskRunner.run(taskId, parameters, context)
        }
        handlers["scan_all_categories"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            ScanAllCategoriesTaskRunner.run(taskId, parameters, context)
        }
        handlers["scan_single_category"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            ScanSingleCategoryTaskRunner.run(taskId, parameters, context)
        }
        handlers["scan_archive"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            ScanArchiveTaskRunner.run(taskId, parameters, context)
        }
        handlers["generate_thumbnail"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            GenerateThumbnailTaskRunner.run(taskId, parameters, context)
        }
        handlers["generate_category_cover"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            GenerateCategoryCoverTaskRunner.run(taskId, parameters, context)
        }
        handlers["check_database"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            CheckDatabaseTaskRunner.run(taskId, parameters, context)
        }
        handlers["scan_plugins"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            PluginTaskService.runScanPluginsTask(taskId, parameters, context)
        }
        handlers["wasm_task"] = { taskId: Int64, parameters: String, _: TaskRunnerContext =>
            WasmTaskRunner.run(taskId, parameters)
        }
        handlers["metadata_plugin_callback"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            MetadataPluginCallbackRunner.run(taskId, parameters, context)
        }
        handlers["clear_cache"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            ClearCacheTaskRunner.run(taskId, parameters, context)
        }
        handlers["clear_log"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            ClearLogTaskRunner.run(taskId, parameters, context)
        }
        handlers["regenerate_cover"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            RegenerateCoverTaskRunner.run(taskId, parameters, context)
        }
        handlers["backfill_metadata"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            BackfillMetadataTaskRunner.run(taskId, parameters, context)
        }
        handlers["page_metadata"] = { taskId: Int64, parameters: String, context: TaskRunnerContext =>
            PageMetadataTaskRunner.run(taskId, parameters, context)
        }
    }
}
