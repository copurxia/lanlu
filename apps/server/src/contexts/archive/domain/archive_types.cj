package lanlu.contexts.archive.domain

/**
 * Strongly typed archive kind.
 *
 * Database and API boundaries still use the string values below. Domain and
 * infrastructure code should prefer ArchiveType when it needs behavior.
 */
public enum ArchiveType {
    | Archive
    | Folder
    | Pdf
    | Epub
    | Unknown(String)

    public static func fromDb(value: String): ArchiveType {
        match (value.trimAscii()) {
            case "archive" => return Archive
            case "folder" => return Folder
            case "pdf" => return Pdf
            case "epub" => return Epub
            case _ => return Unknown(value.trimAscii())
        }
    }

    public static func isValidDbValue(value: String): Bool {
        return ArchiveType.fromDb(value).isKnown()
    }

    public func toDb(): String {
        match (this) {
            case Archive => return "archive"
            case Folder => return "folder"
            case Pdf => return "pdf"
            case Epub => return "epub"
            case Unknown(value) => return value
        }
    }

    public func isKnown(): Bool {
        match (this) {
            case Unknown(_) => return false
            case _ => return true
        }
    }

    public func displayName(): String {
        match (this) {
            case Archive => return "压缩包"
            case Folder => return "文件夹"
            case Pdf => return "PDF文件"
            case Epub => return "EPUB电子书"
            case Unknown(_) => return "未知"
        }
    }

    public func defaultFileType(): String {
        match (this) {
            case Epub => return "html"
            case _ => return "image"
        }
    }
}

/**
 * Archive类型字符串兼容层。
 *
 * 新代码优先使用 ArchiveType；保留该类是为了兼容数据库/API 字符串边界和既有调用点。
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
        return ArchiveType.isValidDbValue(`type`)
    }

    /**
     * 获取类型显示名称
     */
    public static func getDisplayName(`type`: String): String {
        return ArchiveType.fromDb(`type`).displayName()
    }
}
