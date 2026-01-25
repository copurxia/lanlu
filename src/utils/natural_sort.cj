package lanlu.utils

import std.collection.*
import std.sort.*

/**
 * 自然排序工具类
 * 支持文件名中数字的自然排序，如: page1, page2, page10 而不是 page1, page10, page2
 */
public class NaturalSort {

    /**
     * 对字符串数组进行自然排序（原地排序）
     */
    public static func sortStrings(data: ArrayList<String>): Unit {
        sort<String>(data, by: naturalCompare)
    }

    /**
     * 对元组数组按第一个元素进行自然排序（原地排序）
     */
    public static func sortTuples(data: ArrayList<(String, String)>): Unit {
        sort<(String, String)>(data, by: { a, b => naturalCompare(a[0], b[0]) })
    }

    /**
     * 自然排序比较函数
     * 将字符串分割为文本和数字片段，逐段比较
     */
    public static func naturalCompare(a: String, b: String): Ordering {
        let aSegments = splitIntoSegments(a)
        let bSegments = splitIntoSegments(b)

        let minLen = if (aSegments.size < bSegments.size) { aSegments.size } else { bSegments.size }

        for (i in 0..minLen) {
            let aSeg = aSegments[i]
            let bSeg = bSegments[i]

            let result = compareSegments(aSeg, bSeg)
            if (result != Ordering.EQ) {
                return result
            }
        }

        // 所有共同片段相等，比较长度
        if (aSegments.size < bSegments.size) {
            return Ordering.LT
        } else if (aSegments.size > bSegments.size) {
            return Ordering.GT
        }
        return Ordering.EQ
    }

    /**
     * 将字符串分割为文本和数字片段
     */
    private static func splitIntoSegments(s: String): ArrayList<Segment> {
        let segments = ArrayList<Segment>()
        if (s.isEmpty()) {
            return segments
        }

        let runes = s.toRuneArray()
        var i = 0

        while (i < runes.size) {
            if (isDigit(runes[i])) {
                // 收集数字片段
                var numStr = ""
                while (i < runes.size && isDigit(runes[i])) {
                    numStr += runes[i].toString()
                    i++
                }
                segments.add(Segment(numStr, true))
            } else {
                // 收集文本片段
                var textStr = ""
                while (i < runes.size && !isDigit(runes[i])) {
                    textStr += runes[i].toString()
                    i++
                }
                segments.add(Segment(textStr, false))
            }
        }

        return segments
    }

    /**
     * 比较两个片段
     */
    private static func compareSegments(a: Segment, b: Segment): Ordering {
        // 如果都是数字，按数值比较
        if (a.isNumber && b.isNumber) {
            let aNum = parseNumber(a.value)
            let bNum = parseNumber(b.value)
            if (aNum < bNum) {
                return Ordering.LT
            } else if (aNum > bNum) {
                return Ordering.GT
            }
            // 数值相等时，比较前导零（更多前导零的排在前面）
            if (a.value.size > b.value.size) {
                return Ordering.LT
            } else if (a.value.size < b.value.size) {
                return Ordering.GT
            }
            return Ordering.EQ
        }

        // 如果类型不同，数字排在文本前面
        if (a.isNumber && !b.isNumber) {
            return Ordering.LT
        }
        if (!a.isNumber && b.isNumber) {
            return Ordering.GT
        }

        // 都是文本，按字典序比较（大小写不敏感）
        return compareStringsIgnoreCase(a.value, b.value)
    }

    /**
     * 大小写不敏感的字符串比较
     */
    private static func compareStringsIgnoreCase(a: String, b: String): Ordering {
        let aLower = a.toAsciiLower()
        let bLower = b.toAsciiLower()
        return aLower.compare(bLower)
    }

    /**
     * 解析数字字符串为 Int64
     */
    private static func parseNumber(s: String): Int64 {
        var result: Int64 = 0
        for (r in s.toRuneArray()) {
            let digit = UInt32(r) - UInt32(r'0')
            result = result * 10 + Int64(digit)
        }
        return result
    }

    /**
     * 判断字符是否为数字
     */
    private static func isDigit(r: Rune): Bool {
        let code = UInt32(r)
        return code >= UInt32(r'0') && code <= UInt32(r'9')
    }
}

/**
 * 片段类型，表示文本或数字片段
 */
class Segment {
    public let value: String
    public let isNumber: Bool

    public init(value: String, isNumber: Bool) {
        this.value = value
        this.isNumber = isNumber
    }
}
