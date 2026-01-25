package lrr4cj.task_runners

import stdx.log.*
import std.convert.*
import std.collection.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import lrr4cj.archivehandler.*

/**
 * 单个档案扫描任务：处理归档文件并入库
 */
public class ScanArchiveTaskRunner {
    private static var logger = getLogger("scan_archive_task")

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("scan_archive_task")
        TaskIO.appendLog(taskId, "scan_archive task started")
        TaskIO.appendLog(taskId, "Task parameters: ${parameters}")

        try {
            TaskIO.appendLog(taskId, "Parsing configuration...")
            let config = parseConfig(parameters)
            TaskIO.appendLog(taskId, "Parsed config: archivePath=${config.archivePath}, archiveType=${config.archiveType}, cachePath=${config.cachePath}, thumbnailPath=${config.thumbnailPath}")

            if (config.archivePath.size == 0) {
                TaskIO.appendLog(taskId, "ERROR: No archive path found in parameters")
                fail(taskId, "archive_path is required")
                return
            }

            TaskIO.appendLog(taskId, "Starting archive processing for: ${config.archivePath}")
            TaskModel.updateTaskProgress(taskId, 10, "Processing ${config.archivePath}")

            let result = processArchiveInternal(config.archivePath, config, context.notifyTaskAvailable)
            TaskIO.appendLog(taskId, "processArchiveInternal returned: success=${result.success}, archiveId=${result.archiveId}, error=${result.error}")

            if (!result.success) {
                let errorMsg = "scan_archive failed: ${config.archivePath}, error: ${result.error}"
                logger.error(errorMsg)
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                fail(taskId, result.error)
                return
            }

            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(1)
            w.writeName("archive_id").writeValue(result.archiveId)
            w.writeName("path").writeValue(config.archivePath)
            w.endObject()
            w.flush()
            let successJson = String.fromUtf8(readToEnd(out))
            TaskIO.appendLog(taskId, "Archive processed successfully, archiveId=${result.archiveId}")
            TaskModel.updateTaskProgress(taskId, 100, "Archive processed")
            TaskModel.completeTask(taskId, successJson)
            TaskIO.writeOutput(taskId, successJson)
            TaskIO.appendLog(taskId, "scan_archive completed for ${config.archivePath}")
        } catch (e: Exception) {
            let errorMsg = "Unexpected error: ${e.message}"
            logger.error(errorMsg, ("exception", e.message), ("stack", e.toString()))
            TaskIO.appendLog(taskId, "FATAL ERROR: ${errorMsg}")
            TaskIO.appendLog(taskId, "Stack trace: ${e.toString()}")
            fail(taskId, errorMsg)
        }
    }

    private static func parseConfig(parameters: String): ArchiveConfig {
        let trimmed = parameters.trimAscii()
        var archivePath = ""
        var cachePath = ""
        var thumbnailPath = ""
        var archiveType = "archive"
        var tags = ""
        var categoryId: String = ""

        if (trimmed.size == 0) {
            return ArchiveConfig(archivePath, cachePath, thumbnailPath, archiveType, tags, categoryId)
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "archive_path" => archivePath = r.readValue<String>().trimAscii()
                        case "cache_path" => cachePath = r.readValue<String>().trimAscii()
                        case "thumbnail_path" => thumbnailPath = r.readValue<String>().trimAscii()
                        case "archive_type" =>
                            archiveType = r.readValue<String>().trimAscii()
                            if (archiveType != "archive" && archiveType != "folder" && archiveType != "pdf" && archiveType != "epub") {
                                archiveType = "archive"
                            }
                        case "tags" => tags = r.readValue<String>().trimAscii()
                        case "category_id" => categoryId = r.readValue<String>().trimAscii()
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        return ArchiveConfig(archivePath, cachePath, thumbnailPath, archiveType, tags, categoryId)
    }

    private static func resolveCategory(categoryIdOrCatid: String): (Int64, String, String) {
        let trimmed = categoryIdOrCatid.trimAscii()
        if (trimmed.size == 0) {
            return (0, "", "")
        }

        // 优先按内部数字ID解析
        try {
            let internalId = Int64.parse(trimmed)
            match (CategoryDao.getCategoryByInternalId(internalId)) {
                case Some(cat) => return (internalId, cat.scanPath, cat.catid)
                case None => return (0, "", "")
            }
        } catch (_: Exception) {
            // 再按 catid 解析（兼容旧参数）
            match (CategoryDao.getCategoryById(trimmed)) {
                case Some(cat) => return (cat.id, cat.scanPath, cat.catid)
                case None => return (0, "", "")
            }
        }
    }

    private static func processArchiveInternal(filePath: String, config: ArchiveConfig, notifier: TaskNotifier): ProcessResultData {
        try {
            // 首先检查是否有 handler 能处理该路径
            let factory = ArchiveHandlerFactory.getInstance()
            let handlerOpt = factory.getHandlerByPath(filePath)
            match (handlerOpt) {
                case None =>
                    logger.debug("No handler can handle this path, skipping: ${filePath}")
                    return ProcessResultData(true, "", "")  // 返回成功但无 archiveId，表示跳过
                case Some(_) => ()
            }
            let handler = handlerOpt.getOrThrow()
            let archiveType = handler.getType()

            if (config.categoryId.size == 0) {
                throw Exception("category_id is required")
            }

            let (categoryInternalId, archiveBasePath, categoryCatid) = resolveCategory(config.categoryId)
            if (categoryInternalId <= 0 || archiveBasePath.size == 0) {
                throw Exception("Category not found: ${config.categoryId}")
            }
            let relativePath = ArchiveUtils.calculateRelativePath(filePath, archiveBasePath)
            let fileName = ArchiveUtils.getFullFileName(filePath)
            let existingArchive = ArchiveDao.getByPathAndFilename(relativePath, fileName)

            match (existingArchive) {
                case Some(archive) =>
                    logger.debug("Archive already exists in database: ${filePath}")

                    if (archive.relative_path.size == 0) {
                        logger.debug("Archive has empty relative_path, updating: ${archive.id}")
                    }

                    if (archive.thumbhash.size == 0) {
                        logger.debug("Thumbnail hash is empty, submitting thumbnail generation task for existing archive: ${archive.id}")

                        // 提交缩略图生成任务（异步）
                        let taskSubmitted = submitThumbnailTask(filePath, archive.id, archiveType, notifier)
                        if (!taskSubmitted) {
                            logger.error("Failed to submit thumbnail generation task for archive: ${archive.id}")
                        }

                        // 直接返回成功，不等待缩略图生成完成
                        return ProcessResultData(true, archive.id, "")
                    } else {
                        // Archive存在且已生成thumbhash - 跳过所有处理，直接返回成功
                        logger.debug("Archive already processed with thumbnail: ${filePath}")
                        return ProcessResultData(true, archive.id, "")
                    }
                case None =>
                    logger.debug("Archive not found in database, processing new file: ${filePath}")
            }

            // 使用 Handler 获取媒体文件数量
            let pageCount = handler.getMediaCount(filePath)
            logger.debug("Archive ${filePath} (type: ${archiveType}) contains ${pageCount} media files")

            // 如果没有媒体文件，跳过入库和封面生成
            if (pageCount == 0) {
                logger.debug("No media files found in archive, skipping: ${filePath}")
                return ProcessResultData(true, "", "")
            }

            let dbResult = addArchiveToDatabase(filePath, archiveBasePath, categoryInternalId, archiveType)
            if (!dbResult.success) {
                return dbResult
            }

            let pageUpdateResult = ArchiveDao.updatePageCount(dbResult.archiveId, pageCount)
            if (!pageUpdateResult) {
                logger.error("Failed to update page count for archive: ${dbResult.archiveId}")
            }

            // 保存 tags（如果有）
            if (config.tags.size > 0) {
                let tagOk = TagDao.updateArchiveTags(dbResult.archiveId, config.tags)
                if (!tagOk) {
                    logger.error("Failed to update tags for archive", ("archive_id", dbResult.archiveId))
                } else {
                    logger.debug("Successfully updated tags for archive", ("archive_id", dbResult.archiveId), ("tags", config.tags))
                }
            }

            // 提交缩略图生成任务（异步）
            let taskSubmitted = submitThumbnailTask(filePath, dbResult.archiveId, archiveType, notifier)
            if (!taskSubmitted) {
                logger.error("Failed to submit thumbnail generation task for archive: ${dbResult.archiveId}")
            }

            // 提交元数据插件任务（根据分类配置）
            submitMetadataPluginTasks(categoryInternalId, dbResult.archiveId, notifier)

            return ProcessResultData(true, dbResult.archiveId, "")
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Error processing file: ${e.message}")
        }
    }

    private static func addArchiveToDatabase(filePath: String, archiveBasePath: String, categoryId: Int64, archiveType: String): ProcessResultData {
        try {
            let archiveId = ArchiveUtils.generateArchiveId(filePath)

            let fileName = ArchiveUtils.getFullFileName(filePath)
            let defaultTitle = ArchiveUtils.generateDefaultTitle(filePath)
            let fileSize = ArchiveUtils.getArchiveFileSize(filePath)
            let fileModTime = ArchiveUtils.getArchiveFileModTime(filePath)

            let relativePath = ArchiveUtils.calculateRelativePath(filePath, archiveBasePath)

            if (categoryId == 0) {
                return ProcessResultData(false, "", "category_id is required")
            }

            let success = ArchiveDao.insertArchive(archiveId, defaultTitle, fileName, fileSize, fileModTime, relativePath, archiveType, categoryId)
            if (!success) {
                return ProcessResultData(false, "", "Failed to create archive record in database")
            }

            return ProcessResultData(true, archiveId, "")
        } catch (e: Exception) {
            let error = "Exception adding archive to database: ${e.message}"
            logger.error(error)
            return ProcessResultData(false, "", error)
        }
    }

    /**
     * 提交缩略图生成任务到任务池
     */
    private static func submitThumbnailTask(archivePath: String, archiveId: String, archiveType: String, notifier: TaskNotifier): Bool {
        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("archive_path").writeValue(archivePath)
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
                "scan_archive"
            )

            if (task.id > 0) {
                notifier()
                logger.debug("Submitted thumbnail generation task", ("archive_id", archiveId), ("task_id", task.id.toString()))
                return true
            } else {
                logger.error("Failed to submit thumbnail generation task", ("archive_id", archiveId))
                return false
            }
        } catch (e: Exception) {
            logger.error("Exception submitting thumbnail task", ("archive_id", archiveId), ("exception", e.message))
            return false
        }
    }

    /**
     * 根据分类配置提交元数据插件任务
     */
    private static func submitMetadataPluginTasks(categoryId: Int64, archiveId: String, notifier: TaskNotifier): Unit {
        if (categoryId <= 0) { return }

        let categoryOpt = CategoryDao.getCategoryByInternalId(categoryId)
        match (categoryOpt) {
            case Some(category) =>
                let pluginNamespaces = parsePluginsArray(category.plugins)
                for (namespace in pluginNamespaces) {
                    let submitted = submitMetadataPluginTask(archiveId, namespace, notifier)
                    if (!submitted) {
                        logger.error("Failed to submit metadata plugin task", ("archive_id", archiveId), ("namespace", namespace))
                    }
                }
            case None =>
                logger.debug("Category not found for metadata plugin tasks", ("category_id", categoryId))
        }
    }

    /**
     * 解析 plugins JSON 数组
     */
    private static func parsePluginsArray(pluginsJson: String): Array<String> {
        var namespaces = ArrayList<String>()
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(pluginsJson.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginArray)) { return namespaces.toArray() }
            r.startArray()
            while (r.peek() != EndArray) {
                let v = r.readValue<String>().trimAscii()
                if (v.size > 0) { namespaces.add(v) }
            }
            r.endArray()
        } catch (_: Exception) {}
        return namespaces.toArray()
    }

    /**
     * 提交单个元数据插件任务
     */
    private static func submitMetadataPluginTask(archiveId: String, namespace: String, notifier: TaskNotifier): Bool {
        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("archive_id").writeValue(archiveId)
            w.writeName("namespace").writeValue(namespace)
            w.endObject()
            w.flush()
            let parameters = String.fromUtf8(readToEnd(out))
            let task = TaskModel.createTaskWithOptions(
                "元数据扫描: ${namespace}",
                "metadata_plugin",
                parameters,
                15i32,
                archiveId,
                "scan_archive"
            )

            if (task.id > 0) {
                notifier()
                logger.debug("Submitted metadata plugin task", ("archive_id", archiveId), ("namespace", namespace))
                return true
            } else {
                return false
            }
        } catch (e: Exception) {
            logger.error("Exception submitting metadata plugin task", ("archive_id", archiveId), ("namespace", namespace), ("error", e.message))
            return false
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(0)
        w.writeName("error").writeValue(msg)
        w.endObject()
        w.flush()
        TaskIO.writeOutput(taskId, String.fromUtf8(readToEnd(out)))
    }

}
