/**
 * 导航文件解析器
 */
package epub.parser

import std.collection.*

/**
 * 解析导航文件 (nav.xhtml)，提取 href -> title 映射
 */
public class NavParser {
    /**
     * 解析导航文件，返回 href -> title 的映射
     */
    public static func parse(html: String): HashMap<String, String> {
        var titles = HashMap<String, String>()
        var pos: Int64 = 0

        while (pos < html.size) {
            let aStartOpt = html.indexOf("<a ", pos)
            let aStart: Int64 = match (aStartOpt) {
                case Some(idx) => idx
                case None => break
            }

            let aEndOpt = html.indexOf("</a>", aStart)
            let aEnd: Int64 = match (aEndOpt) {
                case Some(idx) => idx
                case None => break
            }

            let aTag = html[aStart..aEnd + 4]
            let hrefOpt = extractHref(aTag)

            if (let Some(href) <- hrefOpt) {
                let text = extractLinkText(aTag)
                if (!text.isEmpty()) {
                    titles[href] = text
                }
            }

            pos = aEnd + 4
        }

        return titles
    }

    private static func extractHref(aTag: String): ?String {
        // 尝试双引号
        let pattern1 = "href=\""
        let start1Opt = aTag.indexOf(pattern1)
        if (let Some(start) <- start1Opt) {
            let valueStart = start + pattern1.size
            let valueEndOpt = aTag.indexOf("\"", valueStart)
            if (let Some(valueEnd) <- valueEndOpt) {
                if (valueEnd > valueStart) {
                    return Some(aTag[valueStart..valueEnd])
                }
            }
        }

        // 尝试单引号
        let pattern2 = "href='"
        let start2Opt = aTag.indexOf(pattern2)
        if (let Some(start) <- start2Opt) {
            let valueStart = start + pattern2.size
            let valueEndOpt = aTag.indexOf("'", valueStart)
            if (let Some(valueEnd) <- valueEndOpt) {
                if (valueEnd > valueStart) {
                    return Some(aTag[valueStart..valueEnd])
                }
            }
        }

        return None
    }

    private static func extractLinkText(aTag: String): String {
        let tagCloseOpt = aTag.indexOf(">")
        let tagClose: Int64 = match (tagCloseOpt) {
            case Some(idx) => idx
            case None => return ""
        }

        let textEndOpt = aTag.indexOf("</a>")
        let textEnd: Int64 = match (textEndOpt) {
            case Some(idx) => idx
            case None => return ""
        }

        let rawText = aTag[tagClose + 1..textEnd]
        return stripHtmlTags(rawText).trimAscii()
    }

    private static func stripHtmlTags(text: String): String {
        var result = StringBuilder()
        var inTag = false

        for (c in text) {
            if (c == b'<') {
                inTag = true
            } else if (c == b'>') {
                inTag = false
            } else if (!inTag) {
                result.append(c)
            }
        }

        return result.toString()
    }
}
