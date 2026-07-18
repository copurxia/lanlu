package lanlu_client_next.net

import std.collection.ArrayList

// RFC3986 unreserved：A-Z a-z 0-9 - . _ ~，其余一律按 UTF-8 字节 %XX。
public func percentEncode(s: String): String {
    let sb = StringBuilder()
    for (b in s.toArray()) {
        let c = b
        let unreserved = (c >= 0x41u8 && c <= 0x5Au8) || (c >= 0x61u8 && c <= 0x7Au8) ||
            (c >= 0x30u8 && c <= 0x39u8) || c == 0x2Du8 || c == 0x2Eu8 || c == 0x5Fu8 || c == 0x7Eu8
        if (unreserved) {
            sb.append(Rune(UInt32(c)))   // 单字节 ASCII 直接追加
        } else {
            sb.append('%')
            sb.append(hexUpper(c >> 4))
            sb.append(hexUpper(c & 0x0Fu8))
        }
    }
    sb.toString()
}

private func hexUpper(n: UInt8): Rune {
    if (n < 10u8) { return Rune(UInt32(0x30u8 + n)) }  // '0'
    Rune(UInt32(0x41u8 + (n - 10u8)))                  // 'A'
}

public class SearchQuery {
    public var filter: String = ""
    public var categoryId: String = ""
    public var sortby: String = "title"
    public var order: String = "asc"
    public var page: Int64 = 1
    public var pageSize: Int64 = 40
    public var newonly: Bool = false
    public var untaggedonly: Bool = false
    public var favoriteonly: Bool = false
}

public func buildSearchQuery(q: SearchQuery): String {
    let parts = ArrayList<String>()
    if (q.filter.size > 0) { parts.add("filter=${percentEncode(q.filter)}") }
    if (q.categoryId.size > 0) { parts.add("category_id=${percentEncode(q.categoryId)}") }
    parts.add("page=${q.page}")
    parts.add("pageSize=${q.pageSize}")
    if (q.sortby.size > 0) { parts.add("sortby=${percentEncode(q.sortby)}") }
    if (q.order.size > 0) { parts.add("order=${percentEncode(q.order)}") }
    if (q.newonly) { parts.add("newonly=1") }
    if (q.untaggedonly) { parts.add("untaggedonly=1") }
    if (q.favoriteonly) { parts.add("favoriteonly=1") }
    "?" + String.join(parts.toArray(), delimiter: "&")
}
