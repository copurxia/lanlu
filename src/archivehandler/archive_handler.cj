package lrr4cj.archivehandler

/**
 * 条目读取器接口
 * 支持分块读取档案中的条目内容
 */
public interface EntryReader {
    /**
     * 获取条目的总大小（字节）
     * @return 条目大小，-1 表示未知
     */
    func getSize(): Int64

    /**
     * 读取一块数据
     * @param buffer 目标缓冲区
     * @return 实际读取的字节数，0 表示已读完
     */
    func read(buffer: Array<Byte>): Int64

    /**
     * 关闭读取器，释放资源
     */
    func close(): Unit
}

/**
 * 档案处理器接口
 * 定义所有档案类型必须实现的操作
 */
public interface ArchiveHandler {
    /**
     * 获取处理器支持的类型标识
     */
    func getType(): String

    /**
     * 列出档案中的所有条目/页面
     * @param archivePath 档案路径
     * @return 条目列表（文件名或页面标识）
     */
    func listEntries(archivePath: String): Array<String>

    /**
     * 提取单个条目/页面的内容到内存
     * @param archivePath 档案路径
     * @param entryName 条目名称
     * @return (exitCode, data, error)
     */
    func extractEntryToStream(archivePath: String, entryName: String): (Int64, Array<UInt8>, Array<UInt8>)

    /**
     * 获取条目的流式读取器（支持分块读取）
     * @param archivePath 档案路径
     * @param entryName 条目名称
     * @return (exitCode, reader, error) - reader 可能为 None
     */
    func getEntryReader(archivePath: String, entryName: String): (Int64, Option<EntryReader>, String)

    /**
     * 提取单个条目/页面到指定文件
     * @param archivePath 档案路径
     * @param entryName 条目名称
     * @param outputPath 输出路径
     * @return 是否成功
     */
    func extractEntryToFile(archivePath: String, entryName: String, outputPath: String): Bool

    /**
     * 获取媒体文件数量（图片+视频）
     * @param archivePath 档案路径
     * @return 媒体文件数量
     */
    func getMediaCount(archivePath: String): Int32

    /**
     * 获取第一张图片信息（用于缩略图生成）
     * @param archivePath 档案路径
     * @return (entryName, fullPath) - fullPath仅对folder类型有效
     */
    func getFirstImage(archivePath: String): (String, String)

    /**
     * 获取封面图片数据
     * @param archivePath 档案路径
     * @return (exitCode, imageData, errorData) - 0表示成功
     */
    func getCoverImage(archivePath: String): (Int64, Array<UInt8>, Array<UInt8>)

    /**
     * 检测给定路径是否属于此类型
     * @param filePath 文件路径
     * @return 是否匹配此类型
     */
    func canHandle(filePath: String): Bool

    /**
     * 列出档案中的所有条目/页面（带标题信息）
     * @param archivePath 档案路径
     * @return 条目列表，每个元素为 (href, title)，title 可能为空字符串
     */
    func listEntriesWithTitle(archivePath: String): Array<(String, String)>
}
