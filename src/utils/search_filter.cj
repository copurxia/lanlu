package lanlu.utils

import std.collection.*

/**
 * 搜索过滤器解析结果
 */
public class SearchFilterResult {
    // 普通搜索词（支持通配符）
    public var terms: ArrayList<String> = ArrayList<String>()
    // 排除词
    public var excludeTerms: ArrayList<String> = ArrayList<String>()
    // 精确短语（引号内的内容）
    public var exactTerms: ArrayList<String> = ArrayList<String>()

    public init() {}
}

/**
 * 搜索过滤器解析器
 * 支持以下特殊字符：
 * - 引号 ("..."): 精确短语搜索
 * - 减号 (-): 排除词
 */
public class SearchFilter {

    /**
     * 解析搜索过滤器字符串
     */
    public static func parse(filter: String): SearchFilterResult {
        let result = SearchFilterResult()
        let input = filter.trimAscii()

        if (input.size == 0) {
            return result
        }

        // 分词，支持引号短语
        let tokens = tokenize(input)

        // 解析每个 token
        for (token in tokens) {
            let trimmedToken = token.trimAscii()
            if (trimmedToken.size == 0) {
                continue
            }

            parseToken(trimmedToken, result)
        }

        return result
    }

    /**
     * 分词，支持引号短语
     * - 引号内内容作为整体 token
     * - 当包含 `$` 且形如 `namespace:...$` 时，优先整体提取（允许 value 中含空格）
     */
    private static func tokenize(input: String): ArrayList<String> {
        let tokens = ArrayList<String>()
        let s = input
        let n = s.size
        var i: Int64 = 0

        func isSpace(ch: UInt8): Bool {
            return ch == 32u8
        }

        while (i < n) {
            // skip spaces
            while (i < n && isSpace(s[i])) { i += 1 }
            if (i >= n) { break }

            // quoted phrase
            if (s[i] == 34u8) {
                let rest = s[i + 1..]
                let quoteEndOpt = rest.indexOf("\"")
                match (quoteEndOpt) {
                    case Some(qend) =>
                        let quoted = "\"" + rest[0..qend] + "\""
                        tokens.add(quoted)
                        i = i + 1 + qend + 1
                        continue
                    case None =>
                        // no closing quote, fallback to split the rest by spaces
                        let restParts = rest.split(" ", removeEmpty: true)
                        for (part in restParts) {
                            let trimmed = part.trimAscii()
                            if (trimmed.size > 0) {
                                tokens.add(trimmed)
                            }
                        }
                        return tokens
                }
            }

            // try to capture namespace:...$ as a whole token
            var j = i
            var colonIdx: Int64 = -1
            while (j < n && !isSpace(s[j])) {
                if (s[j] == 58u8) { colonIdx = j }
                j += 1
            }
            if (colonIdx >= 0) {
                let afterColon = s[colonIdx + 1..]
                let dollarOpt = afterColon.indexOf("$")
                match (dollarOpt) {
                    case Some(didx) =>
                        let endIdx = colonIdx + 1 + didx + 1
                        let token = s[i..endIdx].trimAscii()
                        if (token.size > 0) {
                            tokens.add(token)
                        }
                        i = endIdx
                        continue
                    case None => ()
                }
            }

            // normal token up to next space
            let token = s[i..j].trimAscii()
            if (token.size > 0) {
                tokens.add(token)
            }
            i = j
        }

        return tokens
    }

    /**
     * 解析单个 token
     */
    private static func parseToken(token: String, result: SearchFilterResult) {
        var t = token

        // 检查是否是排除项（以 - 开头）
        let isExclude = t.startsWith("-") && t.size > 1
        if (isExclude) {
            t = t[1..]
        }

        // 检查是否是引号短语
        let isQuoted = t.startsWith("\"") && t.endsWith("\"") && t.size > 2
        if (isQuoted) {
            t = t[1..t.size-1]
        }

        // 根据类型添加到对应列表
        if (isQuoted) {
            if (isExclude) {
                result.excludeTerms.add(t)
            } else {
                result.exactTerms.add(t)
            }
        } else {
            if (isExclude) {
                result.excludeTerms.add(t)
            } else {
                result.terms.add(t)
            }
        }
    }

    /**
     * 将搜索词转换为 SQL LIKE 模式
     * 转义特殊字符，添加前后通配符
     */
    public static func toLikePattern(input: String): String {
        var s = input

        // 转义反斜杠
        s = s.replace("\\", "\\\\")
        // 转义 SQL LIKE 特殊字符
        s = s.replace("%", "\\%")
        s = s.replace("_", "\\_")

        return "%" + s + "%"
    }

    /**
     * 将搜索词转换为精确匹配的 SQL LIKE 模式（不添加前后通配符）
     */
    public static func toExactLikePattern(input: String): String {
        var s = input

        // 转义反斜杠
        s = s.replace("\\", "\\\\")
        // 转义 SQL LIKE 特殊字符
        s = s.replace("%", "\\%")
        s = s.replace("_", "\\_")

        return s
    }
}
