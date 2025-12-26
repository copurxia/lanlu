/**
 * EPUB Manifest 数据结构
 */
package epub.models

import std.collection.*

/**
 * Manifest 项
 */
public class ManifestItem {
    public let id: String
    public let href: String
    public let mediaType: String
    public var properties: ?String

    public init(id!: String, href!: String, mediaType!: String) {
        this.id = id
        this.href = href
        this.mediaType = mediaType
        this.properties = None
    }

    /**
     * 检查是否包含指定属性
     */
    public func hasProperty(property: String): Bool {
        match (properties) {
            case Some(p) => p.contains(property)
            case None => false
        }
    }
}

/**
 * Spine 项
 */
public class SpineItem {
    public let idref: String

    public init(idref!: String) {
        this.idref = idref
    }
}

/**
 * OPF 包文档
 */
public class PackageDocument {
    public var metadata: Metadata
    public var manifest: ArrayList<ManifestItem>
    public var spine: ArrayList<SpineItem>
    public var opfPath: String

    public init() {
        this.metadata = Metadata()
        this.manifest = ArrayList<ManifestItem>()
        this.spine = ArrayList<SpineItem>()
        this.opfPath = ""
    }
}
