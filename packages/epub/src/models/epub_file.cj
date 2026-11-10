/**
 * EPUB 文件数据结构
 */
package epub.models

/**
 * 表示 EPUB 中的单个文件
 */
public class EpubFile {
    public let id: String
    public let href: String
    public var title: ?String
    public let content: String
    public let mediaType: String

    public init(
        id!: String,
        href!: String,
        title!: ?String,
        content!: String,
        mediaType!: String
    ) {
        this.id = id
        this.href = href
        this.title = title
        this.content = content
        this.mediaType = mediaType
    }

    /**
     * 检查是否为 HTML 文件
     */
    public func isHtml(): Bool {
        return mediaType == "application/xhtml+xml"
    }

    /**
     * 获取内容的字节数组
     */
    public func getContentBytes(): Array<UInt8> {
        return content.toArray()
    }
}
