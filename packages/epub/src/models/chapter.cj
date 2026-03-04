/**
 * EPUB 章节数据结构
 */
package epub.models

import std.collection.*

/**
 * 表示 EPUB 中的一个章节
 */
public class Chapter {
    public let title: String
    public let files: ArrayList<EpubFile>

    public init(title!: String, files!: ArrayList<EpubFile>) {
        this.title = title
        this.files = files
    }

    /**
     * 获取章节中的文件数量
     */
    public func getFileCount(): Int64 {
        return files.size
    }
}
