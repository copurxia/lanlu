package lanlu.contexts.task.application.runners

import stdx.log.*
import std.convert.*
import std.collection.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.shared.utils.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.infrastructure.archivehandler.*

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

            let groupId = TaskDao.getTaskDataById(taskId).groupId
            let result = processArchiveInternal(config.archivePath, config, groupId, context.kvStore, context.notifyTaskAvailable)
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
        var folderScanKey = ""

        if (trimmed.size == 0) {
            return ArchiveConfig(archivePath, cachePath, thumbnailPath, archiveType, tags, categoryId, folderScanKey: folderScanKey)
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
                        case "folder_scan_key" => folderScanKey = r.readValue<String>().trimAscii()
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        return ArchiveConfig(archivePath, cachePath, thumbnailPath, archiveType, tags, categoryId, folderScanKey: folderScanKey)
    }

    private static func resolveCategory(categoryIdOrCatid: String): (Int64, String, Array<String>) {
        let trimmed = categoryIdOrCatid.trimAscii()
        if (trimmed.size == 0) {
            return (0, "", [])
        }

        // 优先按内部数字ID解析
        try {
            let internalId = Int64.parse(trimmed)
            match (CategoryDao.getCategoryByInternalIdLite(internalId)) {
                case Some(cat) => return (internalId, cat.scanPath, parsePluginsArray(cat.plugins))
                case None => return (0, "", [])
            }
        } catch (_: Exception) {
            // 再按 catid 解析（兼容旧参数）
            match (CategoryDao.getCategoryByIdLite(trimmed)) {
                case Some(cat) => return (cat.id, cat.scanPath, parsePluginsArray(cat.plugins))
                case None => return (0, "", [])
            }
        }
    }

    private static func resolveHandler(filePath: String, archiveTypeHint: String): Option<ArchiveHandler> {
        let factory = ArchiveHandlerFactory.getInstance()
        let hintedType = archiveTypeHint.trimAscii()
        if (hintedType.size > 0) {
            let hintedHandler = factory.getHandlerByType(hintedType)
            if (hintedHandler.canHandle(filePath)) {
                return Some(hintedHandler)
            }
        }
        return factory.getHandlerByPath(filePath)
    }

    private static func loadFolderScanSummary(kvStore: TaskKVStore, groupId: String, cacheKey: String): (Bool, Int32, String) {
        let normalizedKey = cacheKey.trimAscii()
        let normalizedGroupId = groupId.trimAscii()
        if (normalizedKey.size == 0 || normalizedGroupId.size == 0) {
            return (false, 0, "")
        }

        match (kvStore.get(normalizedGroupId, normalizedKey)) {
            case Some(payload) =>
                try {
                    var mediaCount: Int32 = 0
                    var coverEntry = ""
                    var buf = ByteBuffer()
                    unsafe { buf.write(payload.rawData()) }
                    let r = JsonReader(buf)
                    if (r.peek() != Some(BeginObject)) {
                        return (false, 0, "")
                    }
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let k = r.readName()
                        match (k) {
                            case "media_count" => mediaCount = r.readValue<Int32>()
                            case "cover_entry" => coverEntry = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    return (true, mediaCount, coverEntry)
                } catch (_: Exception) {
                    return (false, 0, "")
                }
            case None => return (false, 0, "")
        }
    }

    private static func processArchiveInternal(filePath: String, config: ArchiveConfig, groupId: String, kvStore: TaskKVStore, notifier: TaskNotifier): ProcessResultData {
        try {
            // 首先检查是否有 handler 能处理该路径
            let handlerOpt = resolveHandler(filePath, config.archiveType)
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

            let (categoryInternalId, archiveBasePath, pluginNamespaces) = resolveCategory(config.categoryId)
            if (categoryInternalId <= 0 || archiveBasePath.size == 0) {
                throw Exception("Category not found: ${config.categoryId}")
            }
            let relativePath = ArchiveUtils.calculateRelativePath(filePath, archiveBasePath)
            let fileName = ArchiveUtils.getFullFileName(filePath)
            let existingArchive = ArchiveDao.getByCategoryPathAndFilename(categoryInternalId, relativePath, fileName)
            let dirFullPath = if (relativePath.size > 0) { FileUtils.joinPath(archiveBasePath, relativePath) } else { archiveBasePath }
            var hasFolderScanSummary = false
            var cachedMediaCount: Int32 = 0
            var cachedCoverEntry = ""
            if (archiveType == "folder") {
                let (okFolderSummary, mediaCount, coverEntry) = loadFolderScanSummary(kvStore, groupId, config.folderScanKey)
                hasFolderScanSummary = okFolderSummary
                cachedMediaCount = mediaCount
                cachedCoverEntry = coverEntry
            }

            match (existingArchive) {
                case Some(archive) =>
                    logger.debug("Archive already exists in database: ${filePath}")

                    if (archive.relative_path.size == 0) {
                        logger.debug("Archive has empty relative_path, updating: ${archive.id}")
                    }

                    if (archive.thumbhash.size == 0) {
                        if (shouldSubmitThumbnailTask(archiveType, cachedCoverEntry, existingCoverAssetId: archive.cover_asset_id)) {
                            logger.debug("Thumbnail hash is empty, submitting thumbnail generation task for existing archive: ${archive.id}")

                            // 提交缩略图生成任务（异步）
                            let taskSubmitted = submitThumbnailTask(filePath, archive.id, archiveType, cachedCoverEntry, notifier)
                            if (!taskSubmitted) {
                                logger.error("Failed to submit thumbnail generation task for archive: ${archive.id}")
                            }

                            // 直接返回成功，不等待缩略图生成完成
                            try { let _ = TankoubonAutocreateService.ensureAndSync(categoryInternalId, relativePath, dirFullPath) } catch (_: Exception) {}
                            return ProcessResultData(true, archive.id, "")
                        }

                        logger.debug("Thumbnail hash is empty but local cover is not ready yet, deferring to metadata plugins",
                            ("archive_id", archive.id), ("archive_type", archiveType))
                        submitArchiveMetadataTasks(archive.id, categoryInternalId, relativePath, dirFullPath, pluginNamespaces, notifier)
                        return ProcessResultData(true, archive.id, "")
                    } else {
                        // Archive存在且已生成thumbhash - 跳过所有处理，直接返回成功
                        logger.debug("Archive already processed with thumbnail: ${filePath}")
                        try { let _ = TankoubonAutocreateService.ensureAndSync(categoryInternalId, relativePath, dirFullPath) } catch (_: Exception) {}
                        return ProcessResultData(true, archive.id, "")
                    }
                case None =>
                    logger.debug("Archive not found in database, processing new file: ${filePath}")
            }

            // 使用 Handler 获取媒体文件数量
            let pageCount = if (hasFolderScanSummary) { cachedMediaCount } else { handler.getMediaCount(filePath) }
            logger.debug("Archive media count resolved", [
                ("path", filePath),
                ("archive_type", archiveType),
                ("page_count", pageCount.toString())
            ])

            // 如果没有媒体文件，跳过入库和封面生成
            if (pageCount == 0) {
                logger.debug("No media files found in archive, skipping: ${filePath}")
                return ProcessResultData(true, "", "")
            }

            let dbResult = addArchiveToDatabase(filePath, archiveBasePath, categoryInternalId, archiveType, pageCount)
            if (!dbResult.success) {
                return dbResult
            }

            // 保存 tags（如果有）
            if (config.tags.size > 0) {
                let tagOk = TagDao.updateArchiveTags(dbResult.archiveId, config.tags)
                if (!tagOk) {
                    logger.error("Failed to update tags for archive", [("archive_id", dbResult.archiveId)])
                } else {
                    logger.debug("Successfully updated tags for archive", [
                        ("archive_id", dbResult.archiveId),
                        ("tags", config.tags)
                    ])
                }
            }

            if (shouldSubmitThumbnailTask(archiveType, cachedCoverEntry)) {
                // 提交缩略图生成任务（异步）
                let taskSubmitted = submitThumbnailTask(filePath, dbResult.archiveId, archiveType, cachedCoverEntry, notifier)
                if (!taskSubmitted) {
                    logger.error("Failed to submit thumbnail generation task for archive", [("archive_id", dbResult.archiveId)])
                }
            } else {
                logger.debug("Skip thumbnail generation until metadata plugin provides cover",
                    ("archive_id", dbResult.archiveId), ("archive_type", archiveType))
            }

            submitArchiveMetadataTasks(dbResult.archiveId, categoryInternalId, relativePath, dirFullPath, pluginNamespaces, notifier)

            // 页面元数据改为插件驱动（metadata_plugin_callback 写回 pages），扫描阶段不再自动提交 page_metadata。

            return ProcessResultData(true, dbResult.archiveId, "")
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Error processing file: ${e.message}")
        }
    }

    private static func addArchiveToDatabase(filePath: String, archiveBasePath: String, categoryId: Int64, archiveType: String, pageCount: Int32): ProcessResultData {
        try {
            let archiveId = ArchiveUtils.generateArchiveId(filePath)

            let fileName = ArchiveUtils.getFullFileName(filePath)
            let defaultTitle = ArchiveUtils.generateDefaultTitle(filePath)
            let fileSize = ArchiveUtils.getArchiveFileSize(filePath)

            let relativePath = ArchiveUtils.calculateRelativePath(filePath, archiveBasePath)

            if (categoryId == 0) {
                return ProcessResultData(false, "", "category_id is required")
            }

            let success = ArchiveDao.insertArchive(archiveId, defaultTitle, fileName, fileSize, relativePath, archiveType, categoryId, pageCount)
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

    private static func shouldSubmitThumbnailTask(archiveType: String, coverEntry: String, existingCoverAssetId!: Int64 = 0): Bool {
        if (archiveType.trimAscii() != "folder") {
            return true
        }
        if (coverEntry.trimAscii().size > 0) {
            return true
        }
        return existingCoverAssetId > 0
    }

    private static func submitArchiveMetadataTasks(archiveId: String, categoryInternalId: Int64, relativePath: String, dirFullPath: String, pluginNamespaces: Array<String>, notifier: TaskNotifier): Unit {
        // Auto-create/sync Tankoubon for this directory.
        let autoTankoubonId = try {
            TankoubonAutocreateService.ensureAndSync(categoryInternalId, relativePath, dirFullPath)
        } catch (_: Exception) {
            ""
        }

        if (autoTankoubonId.size > 0) {
            // For auto-created collections, scrape metadata once for the whole Tankoubon,
            // instead of running archive-level scraping on every member.
            if (TankoubonAutocreateService.hasAllCandidatesIndexed(categoryInternalId, relativePath, dirFullPath)) {
                submitTankoubonMetadataPluginTasks(autoTankoubonId, pluginNamespaces, notifier)
                // Some plugins (e.g. NFO sidecar) emit per-page patches that only apply at archive scope.
                // Keep collection-level scrape, but also run these archive-scoped plugins for this member.
                let archiveScopedPlugins = extractArchiveScopedMetadataPlugins(pluginNamespaces)
                if (archiveScopedPlugins.size > 0) {
                    submitMetadataPluginTasks(archiveId, archiveScopedPlugins, notifier)
                }
            } else {
                logger.debug("Auto Tankoubon not fully indexed yet, postpone metadata scraping",
                    ("tankoubon_id", autoTankoubonId), ("relative_path", relativePath))
            }
        } else {
            // Non-collection archive path: keep original archive-level metadata behavior.
            submitMetadataPluginTasks(archiveId, pluginNamespaces, notifier)
        }
    }

    /**
     * 提交缩略图生成任务到任务池
     */
    private static func submitThumbnailTask(archivePath: String, archiveId: String, archiveType: String, coverEntry: String, notifier: TaskNotifier): Bool {
        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("archive_path").writeValue(archivePath)
            w.writeName("archive_id").writeValue(archiveId)
            w.writeName("type").writeValue(archiveType)
            if (coverEntry.size > 0) {
                w.writeName("cover_entry").writeValue(coverEntry)
            }
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
    private static func submitMetadataPluginTasks(archiveId: String, pluginNamespaces: Array<String>, notifier: TaskNotifier): Unit {
        if (!submitMetadataPluginChainTask("archive", archiveId, pluginNamespaces, notifier)) {
            logger.error("Failed to submit metadata plugin chain task", ("archive_id", archiveId))
        }
    }

    private static func submitTankoubonMetadataPluginTasks(tankoubonId: String, pluginNamespaces: Array<String>, notifier: TaskNotifier): Unit {
        if (tankoubonId.size == 0) { return }
        if (!submitMetadataPluginChainTask("tankoubon", tankoubonId, pluginNamespaces, notifier)) {
            logger.error("Failed to submit tankoubon metadata plugin chain task", ("tankoubon_id", tankoubonId))
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

    private static func submitMetadataPluginChainTask(targetType: String, targetId: String, namespaces: Array<String>, notifier: TaskNotifier): Bool {
        let normalized = normalizeNamespaces(namespaces)
        if (normalized.size == 0) { return true }

        let firstNamespace = normalized[0]
        var fallbackBuilder = ArrayList<String>()
        for (i in 1..normalized.size) {
            fallbackBuilder.add(normalized[i])
        }
        let fallback = fallbackBuilder.toArray()
        return submitMetadataPluginTaskForTarget(targetType, targetId, firstNamespace, fallback, notifier)
    }

    private static func normalizeNamespaces(namespaces: Array<String>): Array<String> {
        var normalized = ArrayList<String>()
        for (ns in namespaces) {
            let namespace = ns.trimAscii()
            if (namespace.size > 0) {
                normalized.add(namespace)
            }
        }
        return normalized.toArray()
    }

    /**
     * Metadata plugins that must run on archive scope even when archive belongs to an auto tank.
     * Currently used for page-level patches (sort/hide/path).
     */
    private static func extractArchiveScopedMetadataPlugins(namespaces: Array<String>): Array<String> {
        var out = ArrayList<String>()
        for (ns in namespaces) {
            let key = ns.trimAscii().toAsciiLower()
            if (key == "nfo") {
                out.add(ns.trimAscii())
            }
        }
        return out.toArray()
    }

    private static func submitMetadataPluginTaskForTarget(targetType: String, targetId: String, namespace: String, fallbackNamespaces: Array<String>, notifier: TaskNotifier): Bool {
        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("target_type").writeValue(targetType)
            w.writeName("target_id").writeValue(targetId)
            w.writeName("namespace").writeValue(namespace)
            if (fallbackNamespaces.size > 0) {
                w.writeName("fallback_namespaces")
                w.startArray()
                for (ns in fallbackNamespaces) {
                    w.writeValue(ns)
                }
                w.endArray()
            }
            w.endObject()
            w.flush()
            let parameters = String.fromUtf8(readToEnd(out))
            let task = TaskModel.createTaskWithOptions(
                "元数据扫描: ${namespace}",
                "metadata_plugin",
                parameters,
                15i32,
                targetId,
                "scan_archive"
            )

            if (task.id > 0) {
                notifier()
                logger.debug("Submitted metadata plugin task",
                    ("target_type", targetType), ("target_id", targetId), ("namespace", namespace))
                return true
            } else {
                return false
            }
        } catch (e: Exception) {
            logger.error("Exception submitting metadata plugin task",
                ("target_type", targetType), ("target_id", targetId), ("namespace", namespace), ("error", e.message))
            return false
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

}
