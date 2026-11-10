/**
 * EPUB 解析库主入口
 */
package epub

import std.collection.*
import epub.models.*
import epub.parser.*
import epub.archive.*

/**
 * EPUB 文件解析器
 */
public class Epub {
    public let metadata: Metadata
    public let chapters: ArrayList<Chapter>
    public let tableOfContents: TableOfContents
    public let allFiles: ArrayList<EpubFile>
    private let extractor: ZipExtractor
    private let packageDoc: PackageDocument

    private init(
        metadata!: Metadata,
        chapters!: ArrayList<Chapter>,
        tableOfContents!: TableOfContents,
        allFiles!: ArrayList<EpubFile>,
        extractor!: ZipExtractor,
        packageDoc!: PackageDocument
    ) {
        this.metadata = metadata
        this.chapters = chapters
        this.tableOfContents = tableOfContents
        this.allFiles = allFiles
        this.extractor = extractor
        this.packageDoc = packageDoc
    }

    /**
     * 从文件路径打开 EPUB
     */
    public static func open(filePath: String): Epub {
        let extractor = ZipExtractor.fromPath(filePath)
        return parseEpub(extractor)
    }

    /**
     * 从内存数据打开 EPUB
     */
    public static func fromBytes(data: Array<UInt8>): Epub {
        let extractor = ZipExtractor.fromBytes(data)
        return parseEpub(extractor)
    }

    /**
     * 解析 EPUB 文件
     */
    private static func parseEpub(extractor: ZipExtractor): Epub {
        // 1. 读取 container.xml
        let containerXml = extractor.extractToString("META-INF/container.xml")
        let opfPath = ContainerParser.parse(containerXml)

        // 2. 读取并解析 OPF 文件
        let opfXml = extractor.extractToString(opfPath)
        var packageDoc = OpfParser.parse(opfXml)
        packageDoc.opfPath = opfPath

        // 3. 查找并解析导航文件 (EPUB 3 nav.xhtml 或 EPUB 2 toc.ncx)
        var navTitles = HashMap<String, String>()

        // 首先尝试 EPUB 3 导航文件
        for (item in packageDoc.manifest) {
            if (item.hasProperty("nav")) {
                let navPath = resolvePath(opfPath, item.href)
                try {
                    let navHtml = extractor.extractToString(navPath)
                    navTitles = NavParser.parse(navHtml)
                } catch (_: Exception) {}
                break
            }
        }

        // 如果没有找到 EPUB 3 导航，尝试 EPUB 2 的 toc.ncx
        if (navTitles.isEmpty()) {
            for (item in packageDoc.manifest) {
                if (item.mediaType == "application/x-dtbncx+xml") {
                    let ncxPath = resolvePath(opfPath, item.href)
                    try {
                        let ncxXml = extractor.extractToString(ncxPath)
                        navTitles = NcxParser.parse(ncxXml)
                    } catch (_: Exception) {}
                    break
                }
            }
        }

        // 4. 查找封面 (EPUB 3 格式)
        if (packageDoc.metadata.cover.isNone()) {
            for (item in packageDoc.manifest) {
                if (item.hasProperty("cover-image")) {
                    packageDoc.metadata.cover = Some(item.id)
                    break
                }
            }
        }

        // 5. 解析所有 XHTML 文件
        var allFiles = parseAllFiles(extractor, packageDoc, navTitles)

        // 6. 创建目录
        var toc = createTableOfContents(allFiles)

        // 7. 将文件分组为章节
        let chapters = groupFilesIntoChapters(allFiles, packageDoc.spine)

        return Epub(
            metadata: packageDoc.metadata,
            chapters: chapters,
            tableOfContents: toc,
            allFiles: allFiles,
            extractor: extractor,
            packageDoc: packageDoc
        )
    }

    /**
     * 解析所有 XHTML 文件
     */
    private static func parseAllFiles(
        extractor: ZipExtractor,
        packageDoc: PackageDocument,
        navTitles: HashMap<String, String>
    ): ArrayList<EpubFile> {
        var files = ArrayList<EpubFile>()

        for (item in packageDoc.manifest) {
            if (item.mediaType == "application/xhtml+xml") {
                if (item.hasProperty("nav")) {
                    continue
                }

                let filePath = resolvePath(packageDoc.opfPath, item.href)
                try {
                    let content = extractor.extractToString(filePath)
                    let title = navTitles.get(item.href)
                    let epubFile = EpubFile(
                        id: item.id,
                        href: item.href,
                        title: title,
                        content: content,
                        mediaType: item.mediaType
                    )
                    files.add(epubFile)
                } catch (_: Exception) {}
            }
        }

        return files
    }

    /**
     * 创建目录
     */
    private static func createTableOfContents(allFiles: ArrayList<EpubFile>): TableOfContents {
        var toc = TableOfContents()
        for (file in allFiles) {
            let title = match (file.title) {
                case Some(t) => t
                case None => file.id
            }
            toc.addEntry(title, file.href, 0)
        }
        return toc
    }

    /**
     * 将文件分组为章节
     */
    private static func groupFilesIntoChapters(
        allFiles: ArrayList<EpubFile>,
        spine: ArrayList<SpineItem>
    ): ArrayList<Chapter> {
        var chapters = ArrayList<Chapter>()
        var currentFiles = ArrayList<EpubFile>()
        var currentTitle = ""

        var fileMap = HashMap<String, EpubFile>()
        for (file in allFiles) {
            fileMap[file.id] = file
        }

        for (spineItem in spine) {
            let fileOpt = fileMap.get(spineItem.idref)
            match (fileOpt) {
                case Some(file) =>
                    let hasTitle = file.title.isSome()
                    let shouldStartNew = currentFiles.isEmpty() || hasTitle

                    if (shouldStartNew && !currentFiles.isEmpty()) {
                        chapters.add(Chapter(title: currentTitle, files: currentFiles))
                        currentFiles = ArrayList<EpubFile>()
                    }

                    if (currentFiles.isEmpty()) {
                        currentTitle = match (file.title) {
                            case Some(t) => t
                            case None => file.id
                        }
                    }

                    currentFiles.add(file)
                case None => ()
            }
        }

        if (!currentFiles.isEmpty()) {
            chapters.add(Chapter(title: currentTitle, files: currentFiles))
        }

        return chapters
    }

    /**
     * 获取封面图片数据
     */
    public func getCoverBytes(): ?Array<UInt8> {
        match (metadata.cover) {
            case Some(coverId) =>
                for (item in packageDoc.manifest) {
                    if (item.id == coverId) {
                        let coverPath = resolvePath(packageDoc.opfPath, item.href)
                        let (exitCode, data, _) = extractor.extractToBytes(coverPath)
                        if (exitCode == 0) {
                            return Some(data)
                        }
                    }
                }
                return None
            case None => return None
        }
    }

    /**
     * 提取任意资源文件
     */
    public func extractResource(href: String): ?Array<UInt8> {
        let resourcePath = resolvePath(packageDoc.opfPath, href)
        let (exitCode, data, _) = extractor.extractToBytes(resourcePath)
        if (exitCode == 0) {
            return Some(data)
        }
        return None
    }

    /**
     * 根据 manifest ID 提取资源
     */
    public func extractResourceById(id: String): ?Array<UInt8> {
        for (item in packageDoc.manifest) {
            if (item.id == id) {
                return extractResource(item.href)
            }
        }
        return None
    }

    /**
     * 获取所有资源列表
     */
    public func getResourceList(): ArrayList<ManifestItem> {
        return packageDoc.manifest
    }

    /**
     * 清理临时文件
     */
    public func close(): Unit {
        extractor.cleanup()
    }
}

/**
 * 解析相对路径
 */
func resolvePath(basePath: String, relativePath: String): String {
    let slashPos = basePath.lastIndexOf("/")
    let combined = match (slashPos) {
        case Some(pos) => "${basePath[0..pos]}/${relativePath}"
        case None => relativePath
    }
    return normalizePath(combined)
}

/**
 * 规范化路径，处理 .. 和 . 引用
 */
func normalizePath(path: String): String {
    let parts = path.split("/")
    var result = ArrayList<String>()

    for (part in parts) {
        if (part == "..") {
            if (!result.isEmpty()) {
                let lastIdx = result.size - 1
                result.remove(lastIdx..lastIdx + 1)
            }
        } else if (part != "." && part.size > 0) {
            result.add(part)
        }
    }

    return String.join(result.toArray(), delimiter: "/")
}