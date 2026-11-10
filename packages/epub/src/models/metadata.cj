/**
 * EPUB 元数据结构
 */
package epub.models

import std.collection.*

/**
 * EPUB 元数据
 */
public class Metadata {
    public var title: ?String
    public var creators: ArrayList<String>
    public var language: ?String
    public var identifier: String
    public var date: ?String
    public var publisher: ?String
    public var description: ?String
    public var rights: ?String
    public var cover: ?String
    public var tags: ArrayList<String>

    public init() {
        this.title = None
        this.creators = ArrayList<String>()
        this.language = None
        this.identifier = ""
        this.date = None
        this.publisher = None
        this.description = None
        this.rights = None
        this.cover = None
        this.tags = ArrayList<String>()
    }
}
