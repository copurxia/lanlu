/**
 * Container.xml 解析器
 */
package epub.parser

import epub.error.*

/**
 * 解析 META-INF/container.xml 获取 OPF 文件路径
 */
public class ContainerParser {
    /**
     * 解析 container.xml 字符串，返回 OPF 文件路径
     */
    public static func parse(xml: String): String {
        // 查找 <rootfile 后面跟空格的位置（避免匹配到 <rootfiles）
        let rootfileStartOpt = xml.indexOf("<rootfile ")
        let rootfileStart: Int64 = match (rootfileStartOpt) {
            case Some(idx) => idx
            case None => throw EpubParseError("rootfile element not found")
        }

        let rootfileEndOpt = xml.indexOf(">", rootfileStart)
        let rootfileEnd: Int64 = match (rootfileEndOpt) {
            case Some(idx) => idx
            case None => throw EpubParseError("Invalid rootfile element")
        }

        let rootfileTag = xml[rootfileStart..rootfileEnd]
        return extractAttribute(rootfileTag, "full-path")
    }

    private static func extractAttribute(tag: String, attrName: String): String {
        let pattern1 = "${attrName}=\""
        let pattern2 = "${attrName}='"

        // 尝试双引号
        let attr1Opt = tag.indexOf(pattern1)
        if (let Some(attrStart) <- attr1Opt) {
            let valueStart = attrStart + pattern1.size
            let valueEndOpt = tag.indexOf("\"", valueStart)
            if (let Some(valueEnd) <- valueEndOpt) {
                if (valueEnd > valueStart) {
                    return tag[valueStart..valueEnd]
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
                    return tag[valueStart..valueEnd]
                }
            }
        }

        throw EpubParseError("Attribute '${attrName}' not found")
    }
}
