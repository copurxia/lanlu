package lanlu.models

/**
 * Archive类型枚举常量
 * 使用字符串而非枚举，确保数据库兼容性
 */
public class ArchiveTypes {
    // 压缩包类型（默认）
    public static let ARCHIVE: String = "archive"

    // 文件夹类型
    public static let FOLDER: String = "folder"

    // PDF文件类型
    public static let PDF: String = "pdf"

    // EPUB文件类型
    public static let EPUB: String = "epub"

    /**
     * 获取所有支持的类型列表
     */
    public static func getAllTypes(): Array<String> {
        return [ARCHIVE, FOLDER, PDF, EPUB]
    }

    /**
     * 检查类型是否有效
     */
    public static func isValidType(`type`: String): Bool {
        return `type` == ARCHIVE || `type` == FOLDER || `type` == PDF || `type` == EPUB
    }

    /**
     * 获取类型显示名称
     */
    public static func getDisplayName(`type`: String): String {
        match (`type`) {
            case "archive" => "压缩包"
            case "folder" => "文件夹"
            case "pdf" => "PDF文件"
            case "epub" => "EPUB电子书"
            case _ => "未知"
        }
    }
}
