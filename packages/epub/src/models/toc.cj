/**
 * EPUB 目录数据结构
 */
package epub.models

import std.collection.*

/**
 * 目录条目
 */
public class TocEntry {
    public let title: String
    public let href: String
    public let level: Int64

    public init(title!: String, href!: String, level!: Int64) {
        this.title = title
        this.href = href
        this.level = level
    }
}

/**
 * 目录
 */
public class TableOfContents {
    public let entries: ArrayList<TocEntry>

    public init() {
        this.entries = ArrayList<TocEntry>()
    }

    public func addEntry(title: String, href: String, level: Int64): Unit {
        entries.add(TocEntry(title: title, href: href, level: level))
    }

    public func getEntryCount(): Int64 {
        return entries.size
    }
}
