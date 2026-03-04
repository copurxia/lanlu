/**
 * EPUB 解析库异常定义
 */
package epub.error

/**
 * EPUB 相关异常基类
 */
public open class EpubError <: Exception {
    public init() {
        super()
    }

    public init(message: String) {
        super(message)
    }

    protected open override func getClassName(): String {
        return "EpubError"
    }
}

/**
 * EPUB 解析错误
 */
public class EpubParseError <: EpubError {
    public init(message: String) {
        super("Parse error: ${message}")
    }

    protected override func getClassName(): String {
        return "EpubParseError"
    }
}

/**
 * EPUB 文件未找到错误
 */
public class EpubFileNotFoundError <: EpubError {
    public init(path: String) {
        super("File not found: ${path}")
    }

    protected override func getClassName(): String {
        return "EpubFileNotFoundError"
    }
}

/**
 * EPUB 格式无效错误
 */
public class EpubInvalidFormatError <: EpubError {
    public init(message: String) {
        super("Invalid EPUB format: ${message}")
    }

    protected override func getClassName(): String {
        return "EpubInvalidFormatError"
    }
}
