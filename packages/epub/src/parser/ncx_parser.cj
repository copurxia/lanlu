/**
 * NCX 文件解析器 (EPUB 2 格式)
 */
package epub.parser

import std.collection.*

/**
 * 解析 toc.ncx 文件，提取 href -> title 映射
 */
public class NcxParser {
    /**
     * 解析 NCX 文件，返回 href -> title 的映射
     */
    public static func parse(xml: String): HashMap<String, String> {
        var titles = HashMap<String, String>()
        var pos: Int64 = 0

        while (pos < xml.size) {
            // 查找 <navPoint
            let navPointStartOpt = xml.indexOf("<navPoint", pos)
            let navPointStart: Int64 = match (navPointStartOpt) {
                case Some(idx) => idx
                case None => break
            }

            // 查找对应的结束标签或下一个 navPoint
            let navPointEndOpt = findNavPointEnd(xml, navPointStart)
            let navPointEnd: Int64 = match (navPointEndOpt) {
                case Some(idx) => idx
                case None => break
            }

            let navPointContent = xml[navPointStart..navPointEnd]

            // 提取 navLabel 中的 text
            let titleOpt = extractNavLabel(navPointContent)
            // 提取 content 中的 src
            let hrefOpt = extractContentSrc(navPointContent)

            if (let Some(title) <- titleOpt) {
                if (let Some(href) <- hrefOpt) {
                    // 去掉锚点部分，只保留文件名
                    let cleanHref = removeAnchor(href)
                    if (!cleanHref.isEmpty() && !title.isEmpty()) {
                        // 只保留第一个匹配（避免子章节覆盖父章节）
                        if (!titles.contains(cleanHref)) {
                            titles[cleanHref] = title
                        }
                    }
                }
            }

            pos = navPointStart + 10  // 跳过 <navPoint 继续搜索
        }

        return titles
    }

    /**
     * 查找 navPoint 的内容结束位置（到下一个同级 navPoint 或 </navPoint>）
     */
    private static func findNavPointEnd(xml: String, start: Int64): ?Int64 {
        // 找到 navPoint 开始标签的结束
        let tagEndOpt = xml.indexOf(">", start)
        match (tagEndOpt) {
            case Some(tagEnd) =>
                // 查找 </navPoint> 或 <navPoint（下一个同级）
                let closeTagOpt = xml.indexOf("</navPoint>", tagEnd)
                let nextNavPointOpt = xml.indexOf("<navPoint", tagEnd + 1)

                match (closeTagOpt) {
                    case Some(closeTag) =>
                        match (nextNavPointOpt) {
                            case Some(nextNavPoint) =>
                                // 返回较小的位置
                                if (nextNavPoint < closeTag) {
                                    return Some(nextNavPoint)
                                } else {
                                    return Some(closeTag)
                                }
                            case None => return Some(closeTag)
                        }
                    case None =>
                        match (nextNavPointOpt) {
                            case Some(nextNavPoint) => return Some(nextNavPoint)
                            case None => return Some(xml.size)
                        }
                }
            case None => return None
        }
    }

    /**
     * 从 navPoint 内容中提取 navLabel/text
     */
    private static func extractNavLabel(content: String): ?String {
        // 查找 <navLabel>
        let labelStartOpt = content.indexOf("<navLabel>")
        match (labelStartOpt) {
            case Some(labelStart) =>
                let labelEndOpt = content.indexOf("</navLabel>", labelStart)
                match (labelEndOpt) {
                    case Some(labelEnd) =>
                        let labelContent = content[labelStart + 10..labelEnd]
                        // 查找 <text>
                        let textStartOpt = labelContent.indexOf("<text>")
                        match (textStartOpt) {
                            case Some(textStart) =>
                                let textEndOpt = labelContent.indexOf("</text>", textStart)
                                match (textEndOpt) {
                                    case Some(textEnd) =>
                                        let text = labelContent[textStart + 6..textEnd].trimAscii()
                                        if (!text.isEmpty()) {
                                            return Some(text)
                                        }
                                    case None => ()
                                }
                            case None => ()
                        }
                    case None => ()
                }
            case None => ()
        }
        return None
    }

    /**
     * 从 navPoint 内容中提取 content/@src
     */
    private static func extractContentSrc(content: String): ?String {
        // 查找 <content
        let contentStartOpt = content.indexOf("<content ")
        match (contentStartOpt) {
            case Some(contentStart) =>
                let contentEndOpt = content.indexOf("/>", contentStart)
                let contentEnd: Int64 = match (contentEndOpt) {
                    case Some(idx) => idx
                    case None =>
                        let altEndOpt = content.indexOf(">", contentStart)
                        match (altEndOpt) {
                            case Some(idx) => idx
                            case None => return None
                        }
                }

                let contentTag = content[contentStart..contentEnd]
                return extractAttribute(contentTag, "src")
            case None => return None
        }
    }

    /**
     * 提取属性值
     */
    private static func extractAttribute(tag: String, attrName: String): ?String {
        let pattern1 = "${attrName}=\""
        let pattern2 = "${attrName}='"

        // 尝试双引号
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

    /**
     * 移除 URL 中的锚点部分
     */
    private static func removeAnchor(href: String): String {
        let hashOpt = href.indexOf("#")
        match (hashOpt) {
            case Some(hashPos) => href[0..hashPos]
            case None => href
        }
    }
}
