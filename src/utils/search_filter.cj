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
     * 使用基于引号位置的分词策略，正确处理 Unicode 字符（包括 CJK 字符）
     */
    private static func tokenize(input: String): ArrayList<String> {
        let tokens = ArrayList<String>()

        // 检查是否包含引号
        if (!input.contains("\"")) {
            // 没有引号，直接按空格分词
            let parts = input.split(" ", removeEmpty: true)
            for (part in parts) {
                let trimmed = part.trimAscii()
                if (trimmed.size > 0) {
                    tokens.add(trimmed)
                }
            }
            return tokens
        }

        // 包含引号，需要特殊处理
        // 策略：找到所有引号对，提取引号内的内容，然后处理剩余部分
        var remaining = input
        var quoteStartOpt = remaining.indexOf("\"")

        while (true) {
            let quoteStart: Int64 = match (quoteStartOpt) {
                case Some(idx) => idx
                case None => break
            }

            // 处理引号前的内容
            if (quoteStart > 0) {
                let before = remaining[0..quoteStart]
                let beforeParts = before.split(" ", removeEmpty: true)
                for (part in beforeParts) {
                    let trimmed = part.trimAscii()
                    if (trimmed.size > 0) {
                        tokens.add(trimmed)
                    }
                }
            }

            // 找到配对的结束引号
            let afterQuote = remaining[quoteStart + 1..]
            let quoteEndOpt = afterQuote.indexOf("\"")

            match (quoteEndOpt) {
                case Some(quoteEnd) =>
                    // 找到配对引号，提取引号内容（包含引号）
                    let quoted = "\"" + afterQuote[0..quoteEnd] + "\""
                    tokens.add(quoted)
                    remaining = afterQuote[quoteEnd + 1..]
                case None =>
                    // 没有配对引号，将剩余内容作为普通词处理
                    let restParts = afterQuote.split(" ", removeEmpty: true)
                    for (part in restParts) {
                        let trimmed = part.trimAscii()
                        if (trimmed.size > 0) {
                            tokens.add(trimmed)
                        }
                    }
                    return tokens
            }

            quoteStartOpt = remaining.indexOf("\"")
        }

        // 处理最后剩余的内容
        if (remaining.size > 0) {
            let restParts = remaining.split(" ", removeEmpty: true)
            for (part in restParts) {
                let trimmed = part.trimAscii()
                if (trimmed.size > 0) {
                    tokens.add(trimmed)
                }
            }
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
