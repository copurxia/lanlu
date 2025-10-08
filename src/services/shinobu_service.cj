package lrr4cj.services

import std.env.*
import std.fs.*
import std.process.*
import std.time.*
import std.sync.*
import std.convert.*
import std.crypto.digest.*
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import cjoy.json.*
import lrr4cj.config.*
import lrr4cj.dao.*
import dotenv.Dotenv

// 简单的日志记录器
class Logger {
    public func info(message: String) {
        println("[INFO] ${message}")
    }
    
    public func error(message: String) {
        println("[ERROR] ${message}")
    }
    
    public func debug(message: String) {
        println("[DEBUG] ${message}")
    }
    
    public func warn(message: String) {
        println("[WARN] ${message}")
    }
}

let logger = Logger()

/**
 * Shinobu 后台工作服务
 * 负责扫描漫画文件并生成缩略图
 */
public class ShinobuService {

    // 单例实例
    private static var instance: Option<ShinobuService> = Option<ShinobuService>.None
    private static let instanceMutex: Mutex = Mutex()
    
    // 服务状态
    private var isRunning: Bool = false
    private var currentPid: Int64 = 0
    private var mutex: Mutex  = Mutex()
    
    // 配置 - 使用静态变量存储配置
    private static var archivePath: Path
    private static var thumbnailPath: Path
    private static var cachePath: Path
    private static var bsdtarPath: String
    
    // 扫描和缩略图配置 - 使用静态变量存储配置
    private static var enableAutoScan: Bool
    private static var enableInitialScan: Bool
    private static var scanIntervalCron: String
    private static var enableAutoThumbnail: Bool
    private static var thumbnailIntervalCron: String
    private static var maxConcurrentJobs: Int32
    private static var scanFallbackIntervalMs: Int64
    private static var enableFileWatcher: Bool
    
    // 任务管理
    private var currentJobs: Int32 = 0
    private var jobMutex: Mutex = Mutex()
    
    // 定时任务线程 - 使用字符串标识线程
    private var scanThread: Option<String> = Option<String>.None
    private var thumbnailThread: Option<String> = Option<String>.None
    private var fileWatcherThread: Option<String> = Option<String>.None
    
    // 任务控制标志
    private var isTaskRunning: Bool = false
    private let runningMutex: Mutex = Mutex()
    
    // 支持的压缩包格式
    private static let SUPPORTED_ARCHIVE_EXTENSIONS: Array<String> = [
        "zip", "rar", "7z", "tar", "cbz", "cbr", "cb7", "cbt", "tar.gz", "tgz"
    ]
    
    // 支持的图片格式
    private static let SUPPORTED_IMAGE_EXTENSIONS: Array<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp"
    ]
    
    // 静态初始化器 - 用于初始化静态成员和读取环境变量
    static init() {
        // 确保先加载 .env 文件
        Dotenv.config()
        
        // 读取配置
        let archivePathStr = getVariable("ARCHIVE_PATH") ?? "./data/archive"
        let thumbnailPathStr = getVariable("THUMBNAIL_PATH") ?? "./data/thumb"
        let cachePathStr = getVariable("CACHE_PATH") ?? "./data/cache"
        bsdtarPath = getVariable("BSDTAR_PATH") ?? "bsdtar"

        // 转换为 Path 类型并规范化
        archivePath = canonicalize(archivePathStr)
        thumbnailPath = canonicalize(thumbnailPathStr)
        cachePath = canonicalize(cachePathStr)

        // 读取扫描和缩略图配置
        let autoScanStr = getVariable("ENABLE_AUTO_SCAN") ?? "true"
        enableAutoScan = autoScanStr == "true"
        
        let initialScanStr = getVariable("ENABLE_INITIAL_SCAN") ?? "false"
        enableInitialScan = initialScanStr == "true"
        
        scanIntervalCron = getVariable("SCAN_INTERVAL_CRON") ?? "0 0 * * *"
        
        let autoThumbnailStr = getVariable("ENABLE_AUTO_THUMBNAIL") ?? "true"
        enableAutoThumbnail = autoThumbnailStr == "true"
        
        thumbnailIntervalCron = getVariable("THUMBNAIL_INTERVAL_CRON") ?? "0 0 * * *"
        
        let maxJobsStr = getVariable("MAX_CONCURRENT_JOBS") ?? "8"
        maxConcurrentJobs = Int32.parse(maxJobsStr)
        
        let fallbackIntervalStr = getVariable("SCAN_FALLBACK_INTERVAL_MS") ?? "300000"
        scanFallbackIntervalMs = Int64.parse(fallbackIntervalStr)
        
        enableFileWatcher = true
    }

    
    /**
     * 获取单例实例
     */
    public static func getInstance(): ShinobuService {
        instanceMutex.lock()
        if (instance.isNone()) {
            instance = Option<ShinobuService>.Some(ShinobuService())
        }
        let result = instance.getOrThrow()
        instanceMutex.unlock()
        return result
    }
    
    /**
     * 获取归档路径
     */
    public static func getArchivePath(): Path {
        return archivePath
    }
    
    /**
     * 获取缩略图路径
     */
    public static func getThumbnailPath(): Path {
        return thumbnailPath
    }
    
    /**
     * 获取缓存路径
     */
    public static func getCachePath(): Path {
        return cachePath
    }
    
    /**
     * 启动 Shinobu 服务
     */
    public func start(): Bool {
        mutex.lock()
        let result = startInternal()
        mutex.unlock()
        return result
    }
    
    /**
     * 内部启动方法
     */
    private func startInternal(): Bool {
        if (isRunning) {
            return true
        }
        
        isRunning = true
        currentPid = getCurrentProcessId()
        
        println("Shinobu service starting with configuration:")
        println("  Archive path: ${archivePath.toString()}")
        println("  Thumbnail path: ${thumbnailPath.toString()}")
        println("  Cache path: ${cachePath.toString()}")
        println("  BSDTAR path: ${bsdtarPath}")
        println("  Enable auto scan: ${enableAutoScan}")
        println("  Enable initial scan: ${enableInitialScan}")
        println("  Scan interval cron: ${scanIntervalCron}")
        println("  Enable auto thumbnail: ${enableAutoThumbnail}")
        println("  Thumbnail interval cron: ${thumbnailIntervalCron}")
        println("  Max concurrent jobs: ${maxConcurrentJobs}")
        println("  Scan fallback interval: ${scanFallbackIntervalMs}ms")
        println("  Enable file watcher: ${enableFileWatcher}")
        
        // 如果启用初始扫描，启动时进行一次扫描
        if (enableInitialScan) {
            println("Starting initial archive scan...")
            spawnScanThread()
        } else {
            println("Initial scan is disabled")
        }
        
        // 如果启用自动扫描，启动定时任务
        if (enableAutoScan) {
            startScheduledScan()
        } else {
            println("Auto scan is disabled")
        }
        
        // 如果启用自动缩略图生成，启动定时任务
        if (enableAutoThumbnail) {
            startScheduledThumbnail()
        } else {
            println("Auto thumbnail generation is disabled")
        }
        
        // 启动文件监视器（如果启用）
        if (enableFileWatcher) {
            startFileWatcher()
        }
        
        return true
    }
    
    /**
     * 停止 Shinobu 服务
     */
    public func stop(): Bool {
        mutex.lock()
        let result = stopInternal()
        mutex.unlock()
        return result
    }
    
    /**
     * 内部停止方法
     */
    private func stopInternal(): Bool {
        if (!isRunning) {
            return true
        }
        
        isRunning = false
        
        // 停止所有定时任务
        stopScheduledTasks()
        
        // 等待所有任务完成
        waitForAllJobs()
        
        return true
    }
    
    /**
     * 重启 Shinobu 服务
     */
    public func restart(): Bool {
        stop()
        return start()
    }
    
    /**
     * 获取服务状态
     */
    public func getStatus(): ShinobuStatusData {
        mutex.lock()
        let alive: Int32 = if (isRunning) { 1 } else { 0 }
        let status = ShinobuStatusData(1, alive, "shinobu_status", currentPid)
        mutex.unlock()
        return status
    }
    
    /**
     * 扫描压缩包文件
     */
    public func scanArchives(): ScanResultData {
        let startTime = getCurrentTimeMillis()
        var processedCount: Int64 = 0
        var errorCount: Int64 = 0
        var errors: Array<String> = Array<String>()
        
        println("Starting archive scan in directory: ${ShinobuService.archivePath.toString()}")

        // 检查目录是否存在
        if (!directoryExists(ShinobuService.archivePath.toString())) {
            println("Archive directory does not exist: ${ShinobuService.archivePath.toString()}")
            return ScanResultData(0, 0, 1, ["Archive directory does not exist: ${ShinobuService.archivePath.toString()}"])
        }

        // 递归扫描目录
        let archiveFiles = findArchiveFiles(ShinobuService.archivePath.toString())
        println("Found ${archiveFiles.size} archive files to process")
        
        for (filePath in archiveFiles) {
            if (!isRunning) {
                println("Scan interrupted: service stopped")
                break // 服务已停止
            }
            
            // 等待可用的任务槽位
            while (!canAddJob() && isRunning) {
                sleep(Duration.second * 1) // 等待1秒后重试
            }
            
            if (!isRunning) {
                println("Scan interrupted: service stopped")
                break // 服务已停止
            }
            
            println("Processing archive: ${filePath}")
            // 处理单个文件
            let result = processArchiveFile(filePath)
            if (result.success) {
                processedCount++
                println("Successfully processed: ${filePath} -> ${result.archiveId}")
            } else {
                errorCount++
                println("Failed to process: ${filePath} - ${result.error}")
                if (result.error.size > 0) {
                    errors = addError(errors, result.error)
                } else {
                    errors = addError(errors, "Unknown error")
                }
            }
        }
        
        let duration = getCurrentTimeMillis() - startTime
        println("Scan completed: ${processedCount} files processed, ${errorCount} errors, ${duration}ms")
        return ScanResultData(processedCount, errorCount, duration, errors)
    }
    
    /**
     * 递归查找压缩包文件
     */
    private func findArchiveFiles(dirPath: String): Array<String> {
        var result: Array<String> = Array<String>()
        
        try {
            if (!directoryExists(dirPath)) {
                return result
            }
            
            let entries = listDirectory(dirPath)
            println("Scanning directory: ${dirPath}, found ${entries.size} entries")
            
            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)
                println("Processing entry: ${entry}, full path: ${fullPath}")
                
                if (directoryExists(fullPath)) {
                    // 递归处理子目录
                    println("Entry is directory, recursing...")
                    let subFiles = findArchiveFiles(fullPath)
                    result = combineArrays(result, subFiles)
                } else if (fileExists(fullPath)) {
                    // 检查文件扩展名
                    let ext = getFileExtension(fullPath)
                    println("Entry is file, extension: ${ext}")
                    // 检查扩展名是否匹配
                    var isSupported = false
                    for (supportedExt in SUPPORTED_ARCHIVE_EXTENSIONS) {
                        if (ext == supportedExt) {
                            isSupported = true
                            println("Extension ${ext} matches supported format ${supportedExt}")
                            break
                        }
                    }
                    if (isSupported) {
                        result = addFile(result, fullPath)
                        println("Added file to result: ${fullPath}")
                    } else {
                        println("Extension ${ext} not supported")
                    }
                }
            }
        } catch (e: Exception) {
            // 记录错误但继续处理其他文件
            println("Error scanning directory ${dirPath}: ${e.message}")
        }
        
        return result
    }
    
    /**
     * 处理单个压缩包文件
     */
    private func processArchiveFile(filePath: String): ProcessResultData {
        // 检查是否可以添加新任务
        if (!canAddJob()) {
            return ProcessResultData(false, "", "Maximum concurrent jobs reached")
        }
        
        // 增加任务计数
        incrementJobCount()
        
        try {
            // 0. 检查文件是否已经存在于数据库中，并获取其信息
            let relativePath = calculateRelativePath(filePath)
            let fileName = getFullFileName(filePath)
            let existingArchive = ArchiveDao.getByPathAndFilename(relativePath, fileName)
            
            match (existingArchive) {
                case Some(archive) =>
                    logger.info("Archive already exists in database: ${filePath}")
                    
                    // 检查是否需要生成缩略图
                    if (archive.thumbhash.size == 0) {
                        logger.info("Thumbnail hash is empty, generating thumbnail for existing archive: ${archive.id}")
                        
                        // 生成缩略图
                        let thumbnailResult = generateThumbnail(filePath, archive.id)
                        if (!thumbnailResult.success) {
                            decrementJobCount()
                            return thumbnailResult
                        }
                        
                        // 生成缩略图的hash并更新到数据库
                        if (thumbnailResult.success && thumbnailResult.archiveId.size > 0) {
                            let thumbHash = generateFileHash(thumbnailResult.archiveId)
                            let hashUpdateResult = ArchiveDao.updateThumbHash(archive.id, thumbHash)
                            if (!hashUpdateResult) {
                                logger.error("Failed to update thumbnail hash for archive: ${archive.id}")
                            } else {
                                logger.info("Updated thumbnail hash for existing archive: ${archive.id}")
                            }
                        }
                        
                        decrementJobCount()
                        return ProcessResultData(true, archive.id, "")
                    } else {
                        decrementJobCount()
                        logger.info("Archive already has thumbnail: ${filePath}")
                        return ProcessResultData(false, "", "Archive already exists with thumbnail")
                    }
                case None =>
                    // 文件不存在，继续正常处理流程
                    logger.debug("Archive not found in database, processing new file: ${filePath}")
            }
            
            // 1. 计算归档中的图片数量
            let pageCount = countImagesInArchive(filePath)
            logger.info("Archive ${filePath} contains ${pageCount} images")
            
            // 2. 将文件信息添加到数据库
            let dbResult = addArchiveToDatabase(filePath)
            if (!dbResult.success) {
                decrementJobCount()
                return dbResult
            }
            
            // 3. 更新页数到数据库
            let pageUpdateResult = ArchiveDao.updatePageCount(dbResult.archiveId, pageCount)
            if (!pageUpdateResult) {
                logger.error("Failed to update page count for archive: ${dbResult.archiveId}")
            }
            
            // 4. 生成缩略图
            let thumbnailResult = generateThumbnail(filePath, dbResult.archiveId)
            if (!thumbnailResult.success) {
                decrementJobCount()
                return thumbnailResult
            }
            
            // 5. 生成缩略图的hash并更新到数据库
            if (thumbnailResult.success && thumbnailResult.archiveId.size > 0) {
                let thumbHash = generateFileHash(thumbnailResult.archiveId)
                let hashUpdateResult = ArchiveDao.updateThumbHash(dbResult.archiveId, thumbHash)
                if (!hashUpdateResult) {
                    logger.error("Failed to update thumbnail hash for archive: ${dbResult.archiveId}")
                } else {
                    logger.info("Updated thumbnail hash for archive: ${dbResult.archiveId}")
                }
            }
            
            // 任务完成，减少计数
            decrementJobCount()
            return ProcessResultData(true, dbResult.archiveId, "")
        } catch (e: Exception) {
            // 发生错误，减少计数
            decrementJobCount()
            return ProcessResultData(false, "", "Error processing file: ${e.message}")
        }
    }
    
    /**
     * 将压缩包信息添加到数据库
     */
    private func addArchiveToDatabase(filePath: String): ProcessResultData {
        try {
            // 生成基于 SHA1 的 archive ID
            let archiveId = generateArchiveId(filePath)
            
            // 获取文件信息
            let fileName = getFullFileName(filePath)  // 使用完整文件名
            let defaultTitle = generateDefaultTitle(filePath)  // 生成不带后缀的标题
            let fileSize = getArchiveFileSize(filePath)
            let fileModTime = getArchiveFileModTime(filePath)
            
            // 计算相对于 archivePath 的相对路径（不包含文件名）
            let relativePath = calculateRelativePath(filePath)
            
            // 使用 DAO 层执行数据库插入操作
            let success = ArchiveDao.insertArchive(archiveId, defaultTitle, fileName, fileSize, fileModTime, relativePath)
            if (!success) {
                return ProcessResultData(false, "", "Failed to create archive record in database")
            }
            
            // 生成缩略图
            let thumbnailResult = generateThumbnail(filePath, archiveId)
            if (!thumbnailResult.success) {
                logger.error("Failed to generate thumbnail for archive: ${archiveId}")
                // 缩略图生成失败不应该阻止归档添加，只记录错误
            }
            
            return ProcessResultData(true, archiveId, "")
        } catch (e: Exception) {
            let error = "Exception adding archive to database: ${e.message}"
            logger.error(error)
            return ProcessResultData(false, "", error)
        }
    }
    
    
    /**
     * 生成缩略图
     */
    private func generateThumbnail(archivePath: String, archiveId: String): ProcessResultData {
        // 1. 列出压缩包内容
        let entries = listArchiveEntries(archivePath)
        if (entries.size == 0) {
            return ProcessResultData(false, "", "No entries found in archive")
        }
        
        // 2. 找到第一个图片文件
        var firstImageEntry: String = ""
        for (entry in entries) {
            let ext = getFileExtension(entry)
            // 检查扩展名是否匹配
            var isImageFile = false
            for (imgExt in SUPPORTED_IMAGE_EXTENSIONS) {
                if (ext == imgExt) {
                    isImageFile = true
                    break
                }
            }
            if (isImageFile) {
                firstImageEntry = entry
                break
            }
        }
        
        if (firstImageEntry.size == 0) {
            return ProcessResultData(false, "", "No image files found in archive")
        }
        
        // 3. 提取图片文件到临时目录
        let tempImagePath = joinPath(cachePath.toString(), "${archiveId}_temp.${getFileExtension(firstImageEntry)}")
        let extractResult = extractArchiveEntry(archivePath, firstImageEntry, tempImagePath)
        if (!extractResult.success) {
            return extractResult
        }
        
        // 4. 使用ImageMagick进行分辨率转换和格式转换为JPG
        let thumbnailFilePath = joinPath(thumbnailPath.toString(), "${archiveId}.jpg")
        let convertResult = convertImageToJpg(tempImagePath, thumbnailFilePath)
        
        // 5. 清理临时文件
        try {
            if (fileExists(tempImagePath)) {
                // 使用系统命令删除文件
                let (exitCode, _, _) = executeWithOutput(
                    "rm",
                    ["-f", tempImagePath],
                    stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe
                )
                if (exitCode != 0) {
                    logger.warn("Failed to delete temp file: ${tempImagePath}")
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to delete temp file: ${tempImagePath}, error: ${e.message}")
        }
        
        if (!convertResult.success) {
            return convertResult
        }
        
        logger.info("Successfully generated thumbnail for archive: ${archiveId}")
        return ProcessResultData(true, thumbnailFilePath, "")
    }
    
    /**
     * 列出压缩包中的文件
     */
    private func listArchiveEntries(archivePath: String): Array<String> {
        try {
            // 检查文件是否存在
            if (!fileExists(archivePath)) {
                logger.error("Archive file does not exist: ${archivePath}")
                return Array<String>()
            }
            
            logger.debug("Attempting to list archive entries: ${archivePath}")
            
            // 使用 bsdtar 的 -tf 选项列出文件
            let (exitCode, stdout, stderr) = executeWithOutput(
                bsdtarPath,
                ["-tf", archivePath],
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe
            )
            
            if (exitCode == 0) {
                // 将字节数组转换为字符串
                let output = String.fromUtf8(stdout)
                // 将输出按行分割，去除空行
                let lines = output.split('\n')
                var entries = Array<String>()
                
                for (line in lines) {
                    // 简单处理：直接使用原字符串，如果非空则添加
                    if (line.size > 0) {
                        let newEntry = line
                        entries = combineArrays(entries, Array<String>(1, { _ => newEntry }))
                    }
                }
                
                logger.debug("Found ${entries.size} entries in archive (UTF-8)")
                return entries
            } else {
                let error = String.fromUtf8(stderr)
                logger.error("Failed to list archive entries: ${error}")
                return Array<String>()
            }
        } catch (e: Exception) {
            logger.error("Exception listing archive entries: ${e.message}")
            return Array<String>()
        }
    }
    
    /**
     * 计算归档文件中的图片数量
     */
    private func countImagesInArchive(archivePath: String): Int32 {
        let entries = listArchiveEntries(archivePath)
        var imageCount: Int32 = 0
        
        for (entry in entries) {
            let ext = getFileExtension(entry)
            // 检查扩展名是否匹配
            var isImageFile = false
            for (imgExt in SUPPORTED_IMAGE_EXTENSIONS) {
                if (ext == imgExt) {
                    isImageFile = true
                    break
                }
            }
            if (isImageFile) {
                imageCount++
            }
        }
        
        logger.debug("Found ${imageCount} images in archive: ${archivePath}")
        return imageCount
    }
    
    /**
     * 生成文件的hash值
     */
    private func generateFileHash(filePath: String): String {
        try {
            // 获取文件大小和修改时间
            let fileSize = getArchiveFileSize(filePath)
            let fileModTime = getArchiveFileModTime(filePath)
            
            // 组合内容：filePath + mtime + size
            let content = filePath + fileModTime.toString() + fileSize.toString()
            
            // 使用 SHA1 算法生成哈希
            var sha1Instance = SHA1()
            sha1Instance.write(content.toArray())
            let hash: Array<Byte> = sha1Instance.finish()
            
            // 转换为十六进制字符串
            let result = toHexString(hash)
            
            logger.debug("Generated file hash: ${result} for file: ${filePath}")
            return result
        } catch (e: Exception) {
            logger.error("Error calculating file hash: ${e.message}")
            // 简单哈希：使用文件路径
            return "${filePath.hashCode()}"
        }
    }
    
    /**
     * 从压缩包中提取单个文件
     */
    private func extractArchiveEntry(archivePath: String, entryName: String, outputPath: String): ProcessResultData {
        try {
            logger.debug("Attempting to extract entry: ${entryName} from archive: ${archivePath}")
            
            // 使用 bsdtar 的 -xO 选项直接输出到标准输出
            // 这样可以避免使用 -C 选项导致的问题
            let (exitCode, stdout, stderr) = executeWithOutput(
                bsdtarPath,
                ["-xO", "-f", archivePath, entryName],
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe
            )
            
            if (exitCode == 0) {
                // 将标准输出的内容写入目标文件
                try {
                    // 使用传入的 outputPath，而不是硬编码目录
                    let outputDir = getParentDirectory(outputPath)
                    if (!directoryExists(outputDir)) {
                        Directory.create(outputDir, recursive: true)
                    }
                    
                    // 直接使用传入的 outputPath，而不是生成 MD5 文件名
                    let finalOutputPath = outputPath
                    
                    // 使用仓颉语言的文件写入方式
                    let filePath = Path(finalOutputPath)
                    var file = File(filePath, Write)
                    file.write(stdout)
                    file.close()
                    
                    logger.info("Successfully extracted ${entryName} to ${finalOutputPath}")
                    return ProcessResultData(true, finalOutputPath, "")
                } catch (e: Exception) {
                    let error = "Failed to write extracted data to file: ${e.message}"
                    logger.error(error)
                    return ProcessResultData(false, "", error)
                }
            } else {
                let error = String.fromUtf8(stderr)
                logger.error("Failed to extract archive entry: ${error}")
                return ProcessResultData(false, "", error)
            }
        } catch (e: Exception) {
            let error = "Exception extracting archive entry: ${e.message}"
            logger.error(error)
            return ProcessResultData(false, "", error)
        }
    }
    
    /**
     * 获取文件扩展名
     */
    private func getFileExtension(filePath: String): String {
        let parts = filePath.split(".")
        if (parts.size > 1) {
            return parts[parts.size - 1]
        }
        return "tmp"  // 默认扩展名
    }

    
    /**
     * 生成归档ID
     */
    private func generateArchiveId(filePath: String): String {
        try {
            // 获取文件大小和修改时间
            let fileSize = getArchiveFileSize(filePath)
            let fileModTime = getArchiveFileModTime(filePath)
            
            // 组合内容：filePath + mtime + size
            let content = filePath + fileModTime.toString() + fileSize.toString()
            
            // 使用 SHA1 算法生成哈希
            var sha1Instance = SHA1()
            sha1Instance.write(content.toArray())
            let hash: Array<Byte> = sha1Instance.finish()
            
            // 转换为十六进制字符串
            let result = toHexString(hash)
            
            logger.debug("Generated archive ID: ${result} for file: ${filePath}")
            return result
        } catch (e: Exception) {
            logger.error("Failed to generate archive ID: ${e.message}")
            // 如果生成失败，返回一个基于文件名的备用 ID
            let fileName = getFileName(filePath)
            return "fallback_${fileName}"
        }
    }
    
    /**
     * 获取文件修改时间
     */
    private func getArchiveFileModTime(filePath: String): Int64 {
        try {
            logger.debug("Getting file modification time for: ${filePath}")
            let path = Path(filePath)
            let file = File(path, Read)
            let fileInfo = file.info
            file.close()
            
            // 获取最后修改时间并转换为毫秒时间戳
            let modTime = fileInfo.lastModificationTime
            logger.debug("File modification time: ${modTime}")
            // 这里需要将 DateTime 转换为毫秒时间戳
            // 简化实现：返回一个基于当前时间的模拟值
            return getTimeMillis()
        } catch (e: Exception) {
            logger.error("Failed to get file modification time for '${filePath}': ${e.message}")
            return getTimeMillis()
        }
    }
    
    /**
     * 获取文件大小
     */
    private func getArchiveFileSize(filePath: String): Int64 {
        try {
            logger.debug("Getting file size for: ${filePath}")
            let path = Path(filePath)
            let file = File(path, Read)
            let fileInfo = file.info
            file.close()
            
            // 获取文件大小
            let size = fileInfo.size
            logger.debug("File size: ${size}")
            return size
        } catch (e: Exception) {
            logger.error("Failed to get file size for '${filePath}': ${e.message}")
            return 0
        }
    }
    
    /**
     * 生成 MD5 哈希作为文件名
     */
    private func generateMD5Filename(arcid: String): String {
        try {
            // 获取当前时间戳
            let timestamp = getTimeMillis().toString()
            
            // 组合 arcid 和时间戳
            let input = arcid + timestamp
            
            // 使用真正的 MD5 算法
            var md5Instance = MD5()
            md5Instance.write(input.toArray())
            let md: Array<Byte> = md5Instance.finish()
            
            // 转换为十六进制字符串
            let result = toHexString(md)
            
            logger.debug("Generated MD5 filename: ${result} for arcid: ${arcid}")
            return result
        } catch (e: Exception) {
            logger.error("Failed to generate MD5 filename: ${e.message}")
            // 如果 MD5 生成失败，返回一个基于时间戳的备用文件名
            let timestamp = getTimeMillis().toString()
            return "fallback_${timestamp}"
        }
    }
    
    /**
     * 获取当前时间戳（毫秒）
     */
    private func getTimeMillis(): Int64 {
        // 简单实现：返回一个模拟的时间戳
        // 实际应该使用系统API获取当前时间
        return 1234567890123
    }
    
    /**
     * 获取文件名（不含扩展名）
     */
    private func getFileName(filePath: String): String {
        let parts = filePath.split("/")
        if (parts.size > 0) {
            let fileName = parts[parts.size - 1]
            let nameParts = fileName.split(".")
            if (nameParts.size > 0) {
                return nameParts[0]
            }
            return fileName
        }
        return filePath
    }
    
    /**
     * 计算相对于 archivePath 的相对路径（不包含文件名）
     */
    private func calculateRelativePath(fullPath: String): String {
        try {
            // 规范化完整路径
            let normalizedPath = canonicalize(Path(fullPath))
            let fullPathStr = normalizedPath.toString()
            
            // 获取父目录路径
            let parentDir = getParentDirectory(fullPathStr)
            
            // 计算相对于 archivePath 的相对路径
            let archivePathStr = archivePath.toString()
            
            // 确保 fullPath 以 archivePath 开头
            if (parentDir.startsWith(archivePathStr)) {
                // 移除 archivePath 前缀，获取相对路径
                let relativePath = parentDir.replace(archivePathStr, "")
                
                // 移除可能的前导斜杠
                if (relativePath.startsWith("/")) {
                    let parts = relativePath.split("/")
                    var result = ""
                    for (i in 1..parts.size) {
                        if (i > 1) {
                            result += "/"
                        }
                        result += parts[i]
                    }
                    return result
                } else {
                    return relativePath
                }
            } else {
                // 如果路径不在 archivePath 下，返回空字符串作为后备
                logger.error("Path ${fullPathStr} is not under archive path ${archivePathStr}")
                return ""
            }
        } catch (e: Exception) {
            logger.error("Failed to calculate relative path for ${fullPath}: ${e.message}")
            return ""
        }
    }
    
    /**
     * 获取完整文件名（包含后缀）
     */
    private func getFullFileName(filePath: String): String {
        let parts = filePath.split("/")
        if (parts.size > 0) {
            return parts[parts.size - 1]
        }
        return filePath
    }
    
    /**
     * 生成默认标题（去除文件后缀名）
     */
    private func generateDefaultTitle(filePath: String): String {
        let fileName = getFullFileName(filePath)
        let parts = fileName.split(".")
        if (parts.size > 1) {
            // 去除最后一个后缀
            var title = ""
            for (i in 0..(parts.size - 1)) {
                if (i > 0) {
                    title += "."
                }
                title += parts[i]
            }
            return title
        }
        return fileName
    }
    
    /**
     * 获取父目录
     */
    private func getParentDirectory(filePath: String): String {
        let parts = filePath.split("/")
        if (parts.size > 1) {
            var result = ""
            for (i in 0..parts.size - 1) {
                if (result.size > 0) {
                    result += "/"
                }
                result += parts[i]
            }
            return result
        }
        return ""
    }
    
    /**
     * 获取当前进程ID
     */
    private func getCurrentProcessId(): Int64 {
        // 简单实现，实际应该使用系统API
        return 12345
    }
    
    /**
     * 获取当前时间（毫秒）
     */
    private func getCurrentTimeMillis(): Int64 {
        // 获取当前时间的毫秒数
        return getTimeMillis()
    }
    
    
    private func directoryExists(path: String): Bool {
        try {
            // 检查路径是否包含有效的 Unicode 字符
            try {
                let dirPath = Path(path)
                if (exists(dirPath)) {
                    let fileInfo = FileInfo(dirPath)
                    return fileInfo.isDirectory()
                }
                return false
            } catch (unicodeError: Exception) {
                logger.error("Unicode error in directory path '${path}': ${unicodeError.message}")
                return false
            }
        } catch (e: Exception) {
            logger.error("Exception checking directory existence: ${e.message}")
            return false
        }
    }
    
    private func fileExists(path: String): Bool {
        try {
            try {
                let filePath = Path(path)
                if (exists(filePath)) {
                    let fileInfo = FileInfo(filePath)
                    return fileInfo.isRegular()
                }
                return false
            } catch (unicodeError: Exception) {
                logger.error("Unicode error in file path '${path}': ${unicodeError.message}")
                return false
            }
        } catch (e: Exception) {
            logger.error("Exception checking file existence: ${e.message}")
            return false
        }
    }
    
    private func listDirectory(path: String): Array<String> {
        try {
            // 检查路径是否包含有效的 Unicode 字符
            try {
                let dirPath = Path(path)
                var files = Array<String>()
                
                // 检查路径是否存在且是目录
                if (exists(dirPath)) {
                    let fileInfo = FileInfo(dirPath)
                    if (fileInfo.isDirectory()) {
                        // 使用 Directory.readFrom 获取目录中的文件和子目录
                        let entries = Directory.readFrom(dirPath)
                        
                        for (entry in entries) {
                            // 只添加文件，跳过子目录
                            if (entry.isRegular()) {
                                // 处理可能的 Unicode 问题
                                try {
                                    let fileName = entry.name.toString()
                                    files = addFile(files, fileName)
                                } catch (unicodeError: Exception) {
                                    logger.info("Skipping file with invalid Unicode name: ${unicodeError.message}")
                                }
                            }
                        }
                        
                        logger.info("Found ${files.size} files in directory: ${path}")
                        return files
                    } else {
                        logger.error("Path is not a directory: ${path}")
                        return Array<String>()
                    }
                } else {
                    logger.error("Directory does not exist: ${path}")
                    return Array<String>()
                }
            } catch (unicodeError: Exception) {
                logger.error("Unicode error in directory path '${path}': ${unicodeError.message}")
                return Array<String>()
            }
        } catch (e: Exception) {
            logger.error("Exception listing directory: ${e.message}")
            return Array<String>()
        }
    }
    
    private func joinPath(base: String, part: String): String {
        return "${base}/${part}"
    }
    
    /**
     * 执行命令
     */
    private func executeWithOutput(command: String, args: Array<String>, stdOut: ProcessRedirect, stdErr: ProcessRedirect): (Int32, Array<UInt8>, Array<UInt8>) {
        try {
            // 构建完整的命令字符串用于日志
            var fullCmd = command
            for (arg in args) {
                fullCmd += " " + arg
            }
            logger.info("Executing command with args: ${fullCmd}")
            
            // 使用仓颉语言的 launch 函数执行命令
            // 根据文档，我们需要正确传递参数
            if (args.size == 0) {
                // 没有参数的情况
                let process = launch(command, stdOut: stdOut, stdErr: stdErr)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 1) {
                // 一个参数的情况
                let process = launch(command, args[0], stdOut: stdOut, stdErr: stdErr)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 2) {
                // 两个参数的情况
                let process = launch(command, args[0], args[1], stdOut: stdOut, stdErr: stdErr)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 3) {
                // 三个参数的情况
                let process = launch(command, args[0], args[1], args[2], stdOut: stdOut, stdErr: stdErr)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 4) {
                // 四个参数的情况（bsdtar -xf archivepath entryname -C outputdir）
                let process = launch(command, args[0], args[1], args[2], args[3], stdOut: stdOut, stdErr: stdErr)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else {
                // 更多参数的情况，暂时返回错误
                logger.error("Too many arguments for command: ${fullCmd}")
                return (1, Array<UInt8>(), Array<UInt8>())
            }
        } catch (e: Exception) {
            logger.error("Error executing command '${command}': ${e.message}")
            return (1, Array<UInt8>(), Array<UInt8>())
        }
    }
    
    /**
     * 使用ImageMagick将图片转换为JPG格式并进行分辨率转换
     */
    private func convertImageToJpg(inputPath: String, outputPath: String): ProcessResultData {
        try {
            logger.debug("Converting image to JPG: ${inputPath} -> ${outputPath}")
            
            // 确保输出目录存在
            let outputDir = getParentDirectory(outputPath)
            if (!directoryExists(outputDir)) {
                Directory.create(outputDir, recursive: true)
            }
            
            // 使用ImageMagick的convert工具进行转换
            // 由于executeWithOutput函数限制参数数量，我们分两步执行
            // 第一步：调整大小 - 宽500px，最大高1000px（保持比例）
            let resizedPath = joinPath(cachePath.toString(), "temp_resized.jpg")
            let (resizeExitCode, resizeStdout, resizeStderr) = executeWithOutput(
                "convert",
                [inputPath, "-resize", "500x1000>", resizedPath],
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe
            )
            
            if (resizeExitCode != 0) {
                let error = String.fromUtf8(resizeStderr)
                logger.error("Failed to resize image: ${error}")
                return ProcessResultData(false, "", error)
            }
            
            // 第二步：设置质量并输出到最终路径
            let (qualityExitCode, qualityStdout, qualityStderr) = executeWithOutput(
                "convert",
                [resizedPath, "-quality", "85", outputPath],
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe
            )
            
            // 清理临时文件
            try {
                if (fileExists(resizedPath)) {
                    let (rmExitCode, _, _) = executeWithOutput(
                        "rm",
                        ["-f", resizedPath],
                        stdOut: ProcessRedirect.Pipe,
                        stdErr: ProcessRedirect.Pipe
                    )
                    if (rmExitCode != 0) {
                        logger.warn("Failed to delete temp resized file: ${resizedPath}")
                    }
                }
            } catch (e: Exception) {
                logger.warn("Failed to delete temp resized file: ${resizedPath}, error: ${e.message}")
            }
            
            if (qualityExitCode == 0) {
                logger.info("Successfully converted image to JPG: ${outputPath}")
                return ProcessResultData(true, outputPath, "")
            } else {
                let error = String.fromUtf8(qualityStderr)
                logger.error("Failed to convert image to JPG: ${error}")
                return ProcessResultData(false, "", error)
            }
        } catch (e: Exception) {
            let error = "Exception converting image to JPG: ${e.message}"
            logger.error(error)
            return ProcessResultData(false, "", error)
        }
    }

    private func addError(errors: Array<String>, error: String): Array<String> {
        // 简单实现：返回原数组（实际应该添加错误）
        return errors
    }
    
    private func combineArrays(arr1: Array<String>, arr2: Array<String>): Array<String> {
        // 合并两个数组
        let result = Array<String>(arr1.size + arr2.size, { i =>
            if (i < arr1.size) {
                arr1[i]
            } else {
                arr2[i - arr1.size]
            }
        })
        return result
    }
    
    private func addFile(arr: Array<String>, file: String): Array<String> {
        // 添加文件到数组
        let result = Array<String>(arr.size + 1, { i =>
            if (i < arr.size) {
                arr[i]
            } else {
                file
            }
        })
        return result
    }
    
    /**
     * 检查文件是否是压缩包（根据路径）
     */
    private func isArchiveFileByPath(filePath: String): Bool {
        let ext = getFileExtension(filePath)
        for (supportedExt in SUPPORTED_ARCHIVE_EXTENSIONS) {
            if (ext == supportedExt) {
                return true
            }
        }
        return false
    }
    
    /**
     * 简单的文件哈希计算
     */
    private func calculateFileHashSimple(filePath: String): String {
        try {
            let content = File.readFrom(Path(filePath))
            // 简单哈希：使用文件大小和路径
            return "${content.size}_${filePath.hashCode()}"
        } catch (e: Exception) {
            println("Error calculating file hash: ${e.message}")
            return "${filePath.hashCode()}"
        }
    }
    
    /**
     * 启动扫描线程
     */
    private func spawnScanThread() {
        if (enableInitialScan) {
            // 生成线程ID
            let threadId = "scan-${DateTime.nowUTC().toUnixTimeStamp()}"
            scanThread = Option<String>.Some(threadId)
            
            spawn {
                println("Starting initial archive scan...")
                scanArchives()
                println("Initial archive scan completed")
            }
        }
    }
    
    /**
     * 启动定时扫描任务
     */
    private func startScheduledScan() {
        if (enableAutoScan) {
            // 生成线程ID
            let threadId = "scheduled-scan-${DateTime.nowUTC().toUnixTimeStamp()}"
            scanThread = Option<String>.Some(threadId)
            
            spawn {
                println("Starting scheduled scan with cron: ${scanIntervalCron}")
                
                // 简单的定时实现：每隔一定时间执行一次
                // 实际应该解析 cron 表达式并精确调度
                let intervalSeconds = parseCronToSeconds(scanIntervalCron)
                
                runningMutex.lock()
                let running = isTaskRunning
                runningMutex.unlock()
                
                while (running) {
                    sleep(Duration.second * intervalSeconds)
                    
                    runningMutex.lock()
                    let stillRunning = isTaskRunning
                    runningMutex.unlock()
                    
                    if (!stillRunning) {
                        break
                    }
                    
                    println("Executing scheduled scan...")
                    scanArchives()
                }
                
                println("Scheduled scan thread stopped")
            }
        }
    }
    
    /**
     * 启动定时缩略图任务
     */
    private func startScheduledThumbnail() {
        if (enableAutoThumbnail) {
            // 生成线程ID
            let threadId = "thumbnail-${DateTime.nowUTC().toUnixTimeStamp()}"
            thumbnailThread = Option<String>.Some(threadId)
            
            spawn {
                println("Starting scheduled thumbnail generation with cron: ${thumbnailIntervalCron}")
                
                // 简单的定时实现：每隔一定时间执行一次
                // 实际应该解析 cron 表达式并精确调度
                let intervalSeconds = parseCronToSeconds(thumbnailIntervalCron)
                
                runningMutex.lock()
                let running = isTaskRunning
                runningMutex.unlock()
                
                while (running) {
                    sleep(Duration.second * intervalSeconds)
                    
                    runningMutex.lock()
                    let stillRunning = isTaskRunning
                    runningMutex.unlock()
                    
                    if (!stillRunning) {
                        break
                    }
                    
                    println("Executing scheduled thumbnail generation...")
                    generateAllThumbnails()
                }
                
                println("Scheduled thumbnail generation thread stopped")
            }
        }
    }
    
    /**
     * 启动文件监视器
     */
    private func startFileWatcher() {
        if (enableAutoScan) {
            // 生成线程ID
            let threadId = "file-watcher-${DateTime.nowUTC().toUnixTimeStamp()}"
            fileWatcherThread = Option<String>.Some(threadId)
            
            spawn {
                println("Starting file watcher for directory: ${archivePath}")
                println("File watcher polling interval: ${scanFallbackIntervalMs}ms")
                
                // 简单的轮询实现：每隔一定时间检查目录变化
                // 实际应该使用文件系统监视 API
                var lastFileCount = countFilesInDirectory(archivePath.toString())
                println("Initial file count in archive directory: ${lastFileCount}")
                
                runningMutex.lock()
                let running = isTaskRunning
                runningMutex.unlock()
                
                while (running) {
                    sleep(Duration.second * (scanFallbackIntervalMs / 1000))
                    
                    runningMutex.lock()
                    let stillRunning = isTaskRunning
                    runningMutex.unlock()
                    
                    if (!stillRunning) {
                        break
                    }
                    
                    // 检查目录中的文件数量是否变化
                    let currentFileCount = countFilesInDirectory(archivePath.toString())
                    if (currentFileCount != lastFileCount) {
                        println("File change detected: ${lastFileCount} -> ${currentFileCount} files, triggering scan...")
                        scanArchives()
                        lastFileCount = currentFileCount
                    } else {
                        println("File watcher check: no changes detected (current count: ${currentFileCount})")
                    }
                }
                
                println("File watcher thread stopped")
            }
        } else {
            println("File watcher is disabled")
        }
    }
    
    /**
     * 停止所有定时任务
     */
    private func stopScheduledTasks() {
        runningMutex.lock()
        isTaskRunning = false
        runningMutex.unlock()
        
        // 等待所有线程结束 - 仓颉中无法直接join线程，线程会在isTaskRunning=false时自动退出
        match (scanThread) {
            case Option<String>.Some(_) =>
                // 线程会在 isTaskRunning = false 时自动退出
                ()
            case Option<String>.None => ()
        }
        
        match (thumbnailThread) {
            case Option<String>.Some(_) =>
                // 线程会在 isTaskRunning = false 时自动退出
                ()
            case Option<String>.None => ()
        }
        
        match (fileWatcherThread) {
            case Option<String>.Some(_) =>
                // 线程会在 isTaskRunning = false 时自动退出
                ()
            case Option<String>.None => ()
        }
        
        scanThread = Option<String>.None
        thumbnailThread = Option<String>.None
        fileWatcherThread = Option<String>.None
        
        println("All scheduled tasks stopped")
    }
    
    /**
     * 简单解析 cron 表达式为秒数
     * 这是一个简化实现，实际应该使用完整的 cron 解析库
     */
    private func parseCronToSeconds(cronExpression: String): Int64 {
        // 简单实现：只处理数字格式（表示秒数）
        // 实际应该解析完整的 cron 表达式
        try {
            let seconds = Int64.parse(cronExpression)
            return seconds
        } catch (e: Exception) {
            // 默认 1 小时
            return 3600
        }
    }
    
    /**
     * 计算目录中的文件数量
     */
    private func countFilesInDirectory(dirPath: String): Int64 {
        var count: Int64 = 0
        
        try {
            let entries = listDirectory(dirPath)
            for (entry in entries) {
                let entryPath = joinPath(dirPath, entry)
                if (fileExists(entryPath)) {
                    count += 1
                }
            }
        } catch (e: Exception) {
            println("Error counting files in directory: ${dirPath}")
        }
        
        return count
    }
    
    /**
     * 生成所有缺失的缩略图
     */
    private func generateAllThumbnails() {
        println("Starting thumbnail generation for archives without thumbnails...")
        var processedCount: Int64 = 0
        var skippedCount: Int64 = 0
        var errorCount: Int64 = 0
        
        try {
            // 获取所有没有缩略图的归档记录
            let archives = ArchiveDao.getArchivesWithoutThumbnails()
            println("Found ${archives.size} archives without thumbnails")
            
            for (archive in archives) {
                // 组装完整路径：archivePath + relative_path + filename
                let dirPath = if (archive.relative_path.size > 0) {
                    joinPath(archivePath.toString(), archive.relative_path)
                } else {
                    archivePath.toString()
                }
                let archiveFilePath = joinPath(dirPath, archive.filename)

                if (fileExists(archiveFilePath)) {
                    println("Generating thumbnail for: ${archive.filename} (${archive.id})")
                    let result = generateThumbnail(archiveFilePath, archive.id)
                    
                    if (result.success) {
                        // 更新数据库中的缩略图hash
                        if (ArchiveDao.updateThumbHash(archive.id, archive.id)) {
                            processedCount++
                            println("Thumbnail generated and database updated for: ${archive.filename}")
                        } else {
                            errorCount++
                            println("Failed to update database for: ${archive.filename}")
                        }
                    } else {
                        errorCount++
                        println("Failed to generate thumbnail for ${archive.filename}: ${result.error}")
                    }
                } else {
                    skippedCount++
                    println("Archive file not found, skipping: ${archive.relative_path}")
                }
            }
            
            println("Thumbnail generation completed: ${processedCount} generated, ${skippedCount} skipped, ${errorCount} errors")
        } catch (e: Exception) {
            println("Error generating thumbnails: ${e}")
        }
    }
    
    /**
     * 检查是否可以添加新任务
     */
    private func canAddJob(): Bool {
        jobMutex.lock()
        let result = currentJobs < maxConcurrentJobs
        jobMutex.unlock()
        return result
    }
    
    /**
     * 增加任务计数
     */
    private func incrementJobCount() {
        jobMutex.lock()
        currentJobs++
        jobMutex.unlock()
    }
    
    /**
     * 减少任务计数
     */
    private func decrementJobCount() {
        jobMutex.lock()
        if (currentJobs > 0) {
            currentJobs--
        }
        jobMutex.unlock()
    }
    
    /**
     * 获取当前任务数量
     */
    public func getCurrentJobCount(): Int32 {
        jobMutex.lock()
        let count = currentJobs
        jobMutex.unlock()
        return count
    }
    
    /**
     * 获取最大并发任务数
     */
    public func getMaxConcurrentJobs(): Int32 {
        return maxConcurrentJobs
    }
    
    /**
     * 等待所有任务完成
     */
    public func waitForAllJobs(): Bool {
        let maxWaitTime = Duration.second * 300 // 最多等待5分钟
        let startTime = DateTime.nowUTC()
        
        while (getCurrentJobCount() > 0) {
            if (DateTime.nowUTC() - startTime > maxWaitTime) {
                return false // 超时
            }
            sleep(Duration.second * 1)
        }
        
        return true
    }
    
    /**
     * 强制停止所有任务
     */
    public func forceStopAllJobs(): Int32 {
        jobMutex.lock()
        let stoppedJobs = currentJobs
        currentJobs = 0
        jobMutex.unlock()
        return stoppedJobs
    }
    
    /**
     * 获取配置信息
     */
    public func getConfiguration(): ShinobuConfiguration {
        return ShinobuConfiguration(
            ShinobuService.enableAutoScan,
            ShinobuService.enableInitialScan,
            ShinobuService.scanIntervalCron,
            ShinobuService.enableAutoThumbnail,
            ShinobuService.thumbnailIntervalCron,
            ShinobuService.maxConcurrentJobs,
            ShinobuService.scanFallbackIntervalMs
        )
    }
    
    /**
     * 获取文件监视器状态
     */
    public func getFileWatcherStatus(): FileWatcherStatusData {
        // 检查文件监视器是否活跃
        let isActive = isFileWatcherActive()
        
        // 获取监视器数量（简化实现）
        let watcherCount: Int32 = if (isActive) { 1 } else { 0 }
        
        // 获取最后事件时间（简化实现）
        let lastEventTime = if (isActive) {
            DateTime.nowUTC().toString()
        } else {
            "Never"
        }
        
        // 获取总事件数（简化实现）
        let totalEvents: Int64 = 0 // 实际应该跟踪事件数量
        
        // 获取错误数（简化实现）
        let errorCount: Int64 = 0 // 实际应该跟踪错误数量
        
        // 获取最后错误（简化实现）
        let lastError = "" // 实际应该记录最后错误
        
        return FileWatcherStatusData(
            isActive,
            watcherCount,
            lastEventTime,
            totalEvents,
            errorCount,
            lastError
        )
    }
    
    /**
     * 检查文件监视器是否活跃
     */
    private func isFileWatcherActive(): Bool {
        match (fileWatcherThread) {
            case Option<String>.Some(_) =>
                return isRunning && ShinobuService.enableFileWatcher
            case Option<String>.None =>
                return false
        }
    }
    
    /**
     * 重启文件监视器
     */
    public func restartFileWatcher(): Bool {
        // 停止现有的文件监视器
        stopFileWatcher()
        
        // 等待一段时间
        sleep(Duration.second * 2)
        
        // 重新启动文件监视器
        if (enableFileWatcher && isRunning) {
            startFileWatcher()
            return true
        }
        
        return false
    }
    
    /**
     * 停止文件监视器
     */
    private func stopFileWatcher() {
        match (fileWatcherThread) {
            case Option<String>.Some(_) =>
                // 线程会在 isTaskRunning = false 时自动退出
                fileWatcherThread = Option<String>.None
                println("File watcher stopped")
            case Option<String>.None =>
                ()
        }
    }
}

/**
 * Shinobu配置信息
 */
public class ShinobuConfiguration {
    public var enableAutoScan: Bool
    public var enableInitialScan: Bool
    public var scanIntervalCron: String
    public var enableAutoThumbnail: Bool
    public var thumbnailIntervalCron: String
    public var maxConcurrentJobs: Int32
    public var scanFallbackIntervalMs: Int64
    
    public init(
        enableAutoScan: Bool,
        enableInitialScan: Bool,
        scanIntervalCron: String,
        enableAutoThumbnail: Bool,
        thumbnailIntervalCron: String,
        maxConcurrentJobs: Int32,
        scanFallbackIntervalMs: Int64
    ) {
        this.enableAutoScan = enableAutoScan
        this.enableInitialScan = enableInitialScan
        this.scanIntervalCron = scanIntervalCron
        this.enableAutoThumbnail = enableAutoThumbnail
        this.thumbnailIntervalCron = thumbnailIntervalCron
        this.maxConcurrentJobs = maxConcurrentJobs
        this.scanFallbackIntervalMs = scanFallbackIntervalMs
    }
    
    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        return "{"
            + "\"enableAutoScan\":${enableAutoScan},"
            + "\"enableInitialScan\":${enableInitialScan},"
            + "\"scanIntervalCron\":\"${scanIntervalCron}\","
            + "\"enableAutoThumbnail\":${enableAutoThumbnail},"
            + "\"thumbnailIntervalCron\":\"${thumbnailIntervalCron}\","
            + "\"maxConcurrentJobs\":${maxConcurrentJobs},"
            + "\"scanFallbackIntervalMs\":${scanFallbackIntervalMs}"
            + "}"
    }
}

/**
 * Shinobu状态数据
 */
public class ShinobuStatusData {
    public var success: Int32
    public var isAlive: Int32
    public var operation: String
    public var pid: Int64
    
    public init(success: Int32, isAlive: Int32, operation: String, pid: Int64) {
        this.success = success
        this.isAlive = isAlive
        this.operation = operation
        this.pid = pid
    }
}

/**
 * 处理结果数据
 */
public class ProcessResultData {
    public var success: Bool
    public var archiveId: String
    public var error: String
    
    public init(success: Bool, archiveId: String, error: String) {
        this.success = success
        this.archiveId = archiveId
        this.error = error
    }
}

/**
 * 文件监视器状态数据
 */
public class FileWatcherStatusData {
    public var isActive: Bool
    public var watcherCount: Int32
    public var lastEventTime: String
    public var totalEvents: Int64
    public var errorCount: Int64
    public var lastError: String
    
    public init(isActive: Bool, watcherCount: Int32, lastEventTime: String,
                totalEvents: Int64, errorCount: Int64, lastError: String) {
        this.isActive = isActive
        this.watcherCount = watcherCount
        this.lastEventTime = lastEventTime
        this.totalEvents = totalEvents
        this.errorCount = errorCount
        this.lastError = lastError
    }
    
    /**
     * 转换为JSON字符串
     */
    public func toJson(): String {
        return "{"
            + "\"isActive\":${isActive},"
            + "\"watcherCount\":${watcherCount},"
            + "\"lastEventTime\":\"${lastEventTime}\","
            + "\"totalEvents\":${totalEvents},"
            + "\"errorCount\":${errorCount},"
            + "\"lastError\":\"${lastError}\""
            + "}"
    }
}

/**
 * 扫描结果数据
 */
public class ScanResultData {
    public var processedCount: Int64
    public var errorCount: Int64
    public var duration: Int64
    public var errors: Array<String>
    
    public init(processedCount: Int64, errorCount: Int64, duration: Int64, errors: Array<String>) {
        this.processedCount = processedCount
        this.errorCount = errorCount
        this.duration = duration
        this.errors = errors
    }
}
