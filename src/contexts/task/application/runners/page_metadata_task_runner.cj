package lanlu.contexts.task.application.runners

import std.collection.*
import std.io.*
import std.io.ByteBuffer
import stdx.encoding.json.stream.*
import std.fs.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.metadata.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*
import lanlu.infrastructure.archivehandler.*

/**
 * page_metadata 任务执行器（运行在TaskPool中）
 * 为档案的每个页面获取元数据（标题、描述、缩略图）
 */
public class PageMetadataTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let cachePath = context.paths.cachePath
        let assetPath = context.paths.assetPath

        TaskIO.appendLog(taskId, "page_metadata task started")
        TaskModel.updateTaskProgress(taskId, 1, "页面元数据任务开始")

        let (archiveId, archivePath, archiveType) = parseParameters(parameters)
        if (archiveId.size == 0 || archivePath.size == 0) {
            fail(taskId, "archive_id and archive_path are required")
            return
        }

        TaskIO.appendLog(taskId, "Processing page metadata for archive: ${archiveId}, type: ${archiveType}")

        let archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            fail(taskId, "Archive not found: ${archiveId}")
            return
        }

        let archiveInternalId = ArchiveDao.getArchiveInternalId(archiveId)
        if (archiveInternalId <= 0) {
            fail(taskId, "Invalid archive internal id: ${archiveId}")
            return
        }

        let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)
        
        TaskIO.appendLog(taskId, "Getting page entries for archive")
        let entriesWithTitle = handler.listEntriesWithTitle(archivePath)
        var pageEntries = ArrayList<String>()
        for (pair in entriesWithTitle) {
            pageEntries.add(pair[0])
        }
        if (pageEntries.size == 0) {
            TaskIO.appendLog(taskId, "No pages found in archive, skipping page metadata")
            TaskModel.updateTaskProgress(taskId, 100, "无页面需要处理")
            TaskModel.completeTask(taskId, "{\"success\":1,\"archive_id\":\"${archiveId}\",\"pages_processed\":0}")
            TaskIO.writeOutput(taskId, "{\"success\":1,\"archive_id\":\"${archiveId}\",\"pages_processed\":0}")
            return
        }

        TaskIO.appendLog(taskId, "Found ${pageEntries.size} pages in archive")

        let pageCount = pageEntries.size
        var processedCount: Int64 = 0
        var thumbGeneratedCount: Int64 = 0
        let existingMetadata = MetadataDao.listPageMetadata(archiveId)
        let metadataByPath = HashMap<String, PageMetadataData>()
        let metadataByPage = HashMap<Int32, PageMetadataData>()
        for (meta in existingMetadata) {
            let pathKey = meta.entry_path.trimAscii()
            if (pathKey.size > 0 && !metadataByPath.contains(pathKey)) {
                metadataByPath[pathKey] = meta
            }
            if (meta.page_number > 0 && !metadataByPage.contains(meta.page_number)) {
                metadataByPage[meta.page_number] = meta
            }
        }
        let items = ArrayList<PageMetadataData>()

        for (i in 0..pageEntries.size) {
            let pageNumber = Int32(i + 1)
            let entryName = pageEntries[i]

            TaskModel.updateTaskProgress(taskId, Int32(10 + (i * 80) / pageCount), "处理页面 ${pageNumber}/${pageCount}")

            let pageData = PageMetadataData()
            pageData.archive_id = archiveInternalId
            pageData.page_number = pageNumber
            pageData.entry_path = entryName

            if (entryName.size > 0) {
                let title = extractTitleFromEntryName(entryName, pageNumber)
                pageData.title = title
            }

            var hasThumb = false
            var existingMeta: Option<PageMetadataData> = Option<PageMetadataData>.None
            match (metadataByPath.get(entryName.trimAscii())) {
                case Some(meta) => existingMeta = Some(meta)
                case None => ()
            }
            match (existingMeta) {
                case Some(existing) =>
                    if (existing.title.trimAscii().size > 0) {
                        pageData.title = existing.title
                    }
                    pageData.description = existing.description
                    pageData.sort_index = existing.sort_index
                    pageData.hidden_in_files = existing.hidden_in_files
                    pageData.extra_data = existing.extra_data
                    if (existing.thumb_asset_id > 0 && existing.thumbhash.size > 0) {
                        pageData.thumb_asset_id = existing.thumb_asset_id
                        pageData.thumbhash = existing.thumbhash
                        hasThumb = true
                    }
                case None =>
                    match (metadataByPage.get(pageNumber)) {
                        case Some(existing) =>
                            if (existing.title.trimAscii().size > 0) {
                                pageData.title = existing.title
                            }
                            pageData.description = existing.description
                            pageData.sort_index = existing.sort_index
                            pageData.hidden_in_files = existing.hidden_in_files
                            pageData.extra_data = existing.extra_data
                            if (existing.thumb_asset_id > 0 && existing.thumbhash.size > 0) {
                                pageData.thumb_asset_id = existing.thumb_asset_id
                                pageData.thumbhash = existing.thumbhash
                                hasThumb = true
                            }
                        case None => ()
                    }
            }

            if (!hasThumb) {
                let thumbResult = generatePageThumbnail(
                    taskId,
                    archiveId,
                    archivePath,
                    archiveType,
                    entryName,
                    pageNumber,
                    cachePath,
                    assetPath
                )

                if (thumbResult.success && thumbResult.assetId > 0) {
                    pageData.thumb_asset_id = thumbResult.assetId
                    pageData.thumbhash = thumbResult.thumbHash
                    thumbGeneratedCount += 1
                }
            }

            items.add(pageData)
            processedCount += 1

        }

        let saveOk = MetadataDao.upsertPageMetadataBatch(archiveId, items.toArray(), sourceNamespace: "page_metadata")
        if (!saveOk) {
            fail(taskId, "Failed to save page metadata to unified metadata store")
            return
        }

        TaskModel.updateTaskProgress(taskId, 100, "页面元数据处理完成")

        let resultJson = "{\"success\":1,\"archive_id\":\"${archiveId}\",\"pages_processed\":${processedCount},\"thumbs_generated\":${thumbGeneratedCount}}"
        TaskModel.completeTask(taskId, resultJson)
        TaskIO.writeOutput(taskId, resultJson)
        TaskIO.appendLog(taskId, "page_metadata completed: processed=${processedCount}, thumbs=${thumbGeneratedCount}")
    }

    private static func parseParameters(parameters: String): (String, String, String) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", "")
        }

        var archiveId = ""
        var archivePath = ""
        var archiveType = "archive"

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                        case "archive_path" => archivePath = r.readValue<String>().trimAscii()
                        case "type" =>
                            archiveType = r.readValue<String>().trimAscii()
                            if (archiveType != "archive" && archiveType != "folder" && archiveType != "pdf" && archiveType != "epub") {
                                archiveType = "archive"
                            }
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        return (archiveId, archivePath, archiveType)
    }

    private static func extractTitleFromEntryName(entryName: String, pageNumber: Int32): String {
        if (entryName.size == 0) {
            return "Page ${pageNumber}"
        }

        let slashParts = entryName.split("/")
        var fileName = if (slashParts.size > 0) { slashParts[slashParts.size - 1] } else { entryName }
        match (fileName.lastIndexOf(".")) {
            case Some(idx) =>
                if (idx > 0) {
                    fileName = fileName[0..idx]
                }
            case None => ()
        }
        let trimmed = fileName.trimAscii()
        if (trimmed.size == 0) {
            return "Page ${pageNumber}"
        }
        return trimmed
    }

    private static func generatePageThumbnail(
        taskId: Int64,
        archiveId: String,
        archivePath: String,
        archiveType: String,
        entryName: String,
        pageNumber: Int32,
        cachePath: String,
        assetPath: String
    ): ThumbnailResult {
        let taskTempDir = FileUtils.joinPath(cachePath, "task/page_${taskId}_${pageNumber}")
        FileUtils.ensureDirectoryExists(Path(taskTempDir))

        let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)

        let inferredExt = inferExtensionFromName(entryName)
        let tempImagePath = FileUtils.joinPath(taskTempDir, "page_${pageNumber}.${inferredExt}")

        let (readerExitCode, readerOpt, _) = handler.getEntryReader(archivePath, entryName)

        if (readerExitCode == 0) {
            match (readerOpt) {
                case Some(reader) =>
                    try {
                        let tempFile = File(Path(tempImagePath), Write)
                        let bufSize: Int64 = 1024 * 1024
                        var buf = Array<Byte>(bufSize, repeat: 0)
                        var total: Int64 = 0
                        while (true) {
                            let n = reader.read(buf)
                            if (n <= 0) {
                                break
                            }
                            tempFile.write(buf[0..n])
                            total += n
                        }
                        tempFile.close()
                        reader.close()
                        TaskIO.appendLog(taskId, "Page ${pageNumber}: extracted ${total} bytes")
                    } catch (e: Exception) {
                        try { reader.close() } catch (_: Exception) {}
                        TaskIO.appendLog(taskId, "WARN: Page ${pageNumber} extraction failed: ${e.message}")
                        return ThumbnailResult(false, 0, "")
                    }
                case None =>
                    TaskIO.appendLog(taskId, "WARN: getEntryReader returned None for page ${pageNumber}, falling back")
                    let (exitCode, data, _) = handler.extractEntryToStream(archivePath, entryName)
                    if (exitCode != 0 || data.size == 0) {
                        return ThumbnailResult(false, 0, "")
                    }
                    try {
                        let tempFile = File(Path(tempImagePath), Write)
                        tempFile.write(data)
                        tempFile.close()
                    } catch (e: Exception) {
                        return ThumbnailResult(false, 0, "")
                    }
            }
        } else {
            let (exitCode, data, _) = handler.extractEntryToStream(archivePath, entryName)
            if (exitCode != 0 || data.size == 0) {
                return ThumbnailResult(false, 0, "")
            }
            try {
                let tempFile = File(Path(tempImagePath), Write)
                tempFile.write(data)
                tempFile.close()
            } catch (e: Exception) {
                return ThumbnailResult(false, 0, "")
            }
        }

        let tempAvifPath = FileUtils.joinPath(taskTempDir, "page_${pageNumber}.avif")
        let (convertResult, thumbHashFromConvert) = ArchiveUtils.convertImageToAvifWithThumbHash(tempImagePath, tempAvifPath, taskTempDir)

        try {
            if (fileExists(tempImagePath)) {
                remove(Path(tempImagePath))
            }
        } catch (_: Exception) {}

        if (!convertResult.success) {
            try { remove(Path(tempAvifPath)) } catch (_: Exception) {}
            try { FileUtils.removeFileOrDirectory(taskTempDir) } catch (_: Exception) {}
            return ThumbnailResult(false, 0, "")
        }

        var thumbHash = thumbHashFromConvert
        if (thumbHash.size == 0) {
            thumbHash = ThumbHashUtils.calculateAvifThumbHashFromFile(tempAvifPath)
        }

        let avifSize = try { Int64(FileInfo(Path(tempAvifPath)).size) } catch (_: Exception) { 0 }
        let assetFileName = "archive_${archiveId}_page_${pageNumber}.avif"
        let assetIdOpt = AssetDao.create(None, "page_thumbnail", assetFileName, "image/avif", "avif", avifSize, thumbHash)
        var savedAssetId: Int64 = 0

        match (assetIdOpt) {
            case Some(assetId) =>
                savedAssetId = assetId
                let finalAssetPath = FileUtils.joinPath(assetPath, "${assetId}.avif")
                try {
                    FileUtils.safeReplaceFile(Path(finalAssetPath), Path(tempAvifPath))
                } catch (e: Exception) {
                    TaskIO.appendLog(taskId, "WARN: Failed to move page thumbnail: ${e.message}")
                    return ThumbnailResult(false, 0, "")
                }
            case None =>
                return ThumbnailResult(false, 0, "")
        }

        try {
            FileUtils.removeFileOrDirectory(taskTempDir)
        } catch (_: Exception) {}

        return ThumbnailResult(true, savedAssetId, thumbHash)
    }

    private static func inferExtensionFromName(name: String): String {
        if (name.size == 0) {
            return "jpg"
        }
        let parts = name.split(".")
        if (parts.size <= 1) {
            return "jpg"
        }
        let ext = parts[parts.size - 1].toAsciiLower()
        if (ext == "jpeg") {
            return "jpg"
        }
        return ext
    }

    private static func fileExists(path: String): Bool {
        return DirectoryScanner.fileExists(path)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}

private class ThumbnailResult {
    public var success: Bool = false
    public var assetId: Int64 = 0
    public var thumbHash: String = ""

    public init(success: Bool, assetId: Int64, thumbHash: String) {
        this.success = success
        this.assetId = assetId
        this.thumbHash = thumbHash
    }
}
