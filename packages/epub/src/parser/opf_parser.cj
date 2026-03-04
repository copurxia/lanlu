/**
 * OPF 文件解析器
 */
package epub.parser

import std.collection.*
import epub.models.*

/**
 * 解析 OPF (Open Packaging Format) 文件
 */
public class OpfParser {
    /**
     * 解析 OPF 文件字符串
     */
    public static func parse(xml: String): PackageDocument {
        var doc = PackageDocument()

        // 解析 metadata
        doc.metadata = parseMetadata(xml)

        // 解析 manifest
        doc.manifest = parseManifest(xml)

        // 解析 spine
        doc.spine = parseSpine(xml)

        return doc
    }

    private static func parseMetadata(xml: String): Metadata {
        var metadata = Metadata()

        let metaStartOpt = xml.indexOf("<metadata")
        let metaStart: Int64 = match (metaStartOpt) {
            case Some(idx) => idx
            case None => return metadata
        }

        let metaEndOpt = xml.indexOf("</metadata>")
        let metaEnd: Int64 = match (metaEndOpt) {
            case Some(idx) => idx
            case None => return metadata
        }

        let metaSection = xml[metaStart..metaEnd]

        // 解析 title
        metadata.title = extractElementText(metaSection, "dc:title")
        if (metadata.title.isNone()) {
            metadata.title = extractElementText(metaSection, "title")
        }

        // 解析 creators
        let creators = extractAllElementTexts(metaSection, "dc:creator")
        for (c in creators) {
            metadata.creators.add(c)
        }
        if (metadata.creators.isEmpty()) {
            let creators2 = extractAllElementTexts(metaSection, "creator")
            for (c in creators2) {
                metadata.creators.add(c)
            }
        }

        // 解析其他字段
        metadata.language = extractElementText(metaSection, "dc:language")
        if (metadata.language.isNone()) {
            metadata.language = extractElementText(metaSection, "language")
        }

        let idOpt = extractElementText(metaSection, "dc:identifier")
        if (let Some(id) <- idOpt) {
            metadata.identifier = id
        }

        metadata.date = extractElementText(metaSection, "dc:date")
        metadata.publisher = extractElementText(metaSection, "dc:publisher")
        metadata.description = extractElementText(metaSection, "dc:description")
        metadata.rights = extractElementText(metaSection, "dc:rights")

        // 解析 tags/subjects
        let subjects = extractAllElementTexts(metaSection, "dc:subject")
        for (s in subjects) {
            metadata.tags.add(s)
        }

        // 解析封面 (EPUB 2 格式)
        metadata.cover = findCoverId(metaSection)

        return metadata
    }

    private static func findCoverId(metaSection: String): ?String {
        var pos: Int64 = 0
        while (pos < metaSection.size) {
            let metaStartOpt = metaSection.indexOf("<meta", pos)
            let metaStart: Int64 = match (metaStartOpt) {
                case Some(idx) => idx
                case None => break
            }

            let metaEndOpt = metaSection.indexOf(">", metaStart)
            let metaEnd: Int64 = match (metaEndOpt) {
                case Some(idx) => idx
                case None => break
            }

            let metaTag = metaSection[metaStart..metaEnd]
            let nameAttr = extractAttribute(metaTag, "name")

            if (let Some(name) <- nameAttr) {
                if (name == "cover") {
                    return extractAttribute(metaTag, "content")
                }
            }

            pos = metaEnd + 1
        }
        return None
    }

    private static func parseManifest(xml: String): ArrayList<ManifestItem> {
        var items = ArrayList<ManifestItem>()

        let manifestStartOpt = xml.indexOf("<manifest")
        let manifestStart: Int64 = match (manifestStartOpt) {
            case Some(idx) => idx
            case None => return items
        }

        let manifestEndOpt = xml.indexOf("</manifest>")
        let manifestEnd: Int64 = match (manifestEndOpt) {
            case Some(idx) => idx
            case None => return items
        }

        let manifestSection = xml[manifestStart..manifestEnd]

        var pos: Int64 = 0
        while (pos < manifestSection.size) {
            let itemStartOpt = manifestSection.indexOf("<item", pos)
            let itemStart: Int64 = match (itemStartOpt) {
                case Some(idx) => idx
                case None => break
            }

            let itemEndOpt = manifestSection.indexOf(">", itemStart)
            let itemEnd: Int64 = match (itemEndOpt) {
                case Some(idx) => idx
                case None => break
            }

            let itemTag = manifestSection[itemStart..itemEnd]

            let idOpt = extractAttribute(itemTag, "id")
            let hrefOpt = extractAttribute(itemTag, "href")
            let mediaTypeOpt = extractAttribute(itemTag, "media-type")

            if (let Some(id) <- idOpt) {
                if (let Some(href) <- hrefOpt) {
                    if (let Some(mediaType) <- mediaTypeOpt) {
                        var item = ManifestItem(id: id, href: href, mediaType: mediaType)
                        item.properties = extractAttribute(itemTag, "properties")
                        items.add(item)
                    }
                }
            }

            pos = itemEnd + 1
        }

        return items
    }

    private static func parseSpine(xml: String): ArrayList<SpineItem> {
        var items = ArrayList<SpineItem>()

        let spineStartOpt = xml.indexOf("<spine")
        let spineStart: Int64 = match (spineStartOpt) {
            case Some(idx) => idx
            case None => return items
        }

        let spineEndOpt = xml.indexOf("</spine>")
        let spineEnd: Int64 = match (spineEndOpt) {
            case Some(idx) => idx
            case None => return items
        }

        let spineSection = xml[spineStart..spineEnd]

        var pos: Int64 = 0
        while (pos < spineSection.size) {
            let itemStartOpt = spineSection.indexOf("<itemref", pos)
            let itemStart: Int64 = match (itemStartOpt) {
                case Some(idx) => idx
                case None => break
            }

            let itemEndOpt = spineSection.indexOf(">", itemStart)
            let itemEnd: Int64 = match (itemEndOpt) {
                case Some(idx) => idx
                case None => break
            }

            let itemTag = spineSection[itemStart..itemEnd]
            let idrefOpt = extractAttribute(itemTag, "idref")

            if (let Some(idref) <- idrefOpt) {
                items.add(SpineItem(idref: idref))
            }

            pos = itemEnd + 1
        }

        return items
    }

    private static func extractElementText(xml: String, tagName: String): ?String {
        let startTag = "<${tagName}"
        let endTag = "</${tagName}>"

        let startOpt = xml.indexOf(startTag)
        let start: Int64 = match (startOpt) {
            case Some(idx) => idx
            case None => return None
        }

        let tagCloseOpt = xml.indexOf(">", start)
        let tagClose: Int64 = match (tagCloseOpt) {
            case Some(idx) => idx
            case None => return None
        }

        let endOpt = xml.indexOf(endTag, tagClose)
        let end: Int64 = match (endOpt) {
            case Some(idx) => idx
            case None => return None
        }

        let text = xml[tagClose + 1..end].trimAscii()
        if (text.isEmpty()) {
            return None
        }
        return Some(text)
    }

    private static func extractAllElementTexts(xml: String, tagName: String): ArrayList<String> {
        var results = ArrayList<String>()
        let startTag = "<${tagName}"
        let endTag = "</${tagName}>"

        var pos: Int64 = 0
        while (pos < xml.size) {
            let startOpt = xml.indexOf(startTag, pos)
            let start: Int64 = match (startOpt) {
                case Some(idx) => idx
                case None => break
            }

            let tagCloseOpt = xml.indexOf(">", start)
            let tagClose: Int64 = match (tagCloseOpt) {
                case Some(idx) => idx
                case None => break
            }

            let endOpt = xml.indexOf(endTag, tagClose)
            let end: Int64 = match (endOpt) {
                case Some(idx) => idx
                case None => break
            }

            let text = xml[tagClose + 1..end].trimAscii()
            if (!text.isEmpty()) {
                results.add(text)
            }

            pos = end + endTag.size
        }

        return results
    }

    private static func extractAttribute(tag: String, attrName: String): ?String {
        // 尝试双引号
        let pattern1 = "${attrName}=\""
        let attr1Opt = tag.indexOf(pattern1)
        if (let Some(attrStart) <- attr1Opt) {
            let valueStart = attrStart + pattern1.size
            let valueEndOpt = tag.indexOf("\"", valueStart)
            if (let Some(valueEnd) <- valueEndOpt) {
                if (valueEnd > valueStart) {
                    return Some(tag[valueStart..valueEnd])
                }
            }
        }

        // 尝试单引号
        let pattern2 = "${attrName}='"
        let attr2Opt = tag.indexOf(pattern2)
        if (let Some(attrStart) <- attr2Opt) {
            let valueStart = attrStart + pattern2.size
            let valueEndOpt = tag.indexOf("'", valueStart)
            if (let Some(valueEnd) <- valueEndOpt) {
                if (valueEnd > valueStart) {
                    return Some(tag[valueStart..valueEnd])
                }
            }
        }

        return None
    }
}
