package postgresql_driver

import std.collection.*
import std.convert.*

/**
 * 连接池配置。
 * - maxSize: 池中并存连接上限(借满后再借则阻塞等待归还)。
 * - minSize: 池预热常驻最小空闲连接数。
 * - idleTimeoutMs: 空闲连接回收阈值(毫秒);<=0 不回收。
 */
public struct PoolConfig {
    public let maxSize: Int64
    public let minSize: Int64
    public let idleTimeoutMs: Int64

    public init(maxSize: Int64, minSize: Int64, idleTimeoutMs: Int64) {
        let mx = if (maxSize < 1) { 1 } else { maxSize }
        let mn = if (minSize < 0) { 0 } else if (minSize > mx) { mx } else { minSize }
        this.maxSize = mx
        this.minSize = mn
        this.idleTimeoutMs = if (idleTimeoutMs < 0) { 0 } else { idleTimeoutMs }
    }

    public static func default(): PoolConfig {
        PoolConfig(10, 0, 0)
    }
}

/**
 * 解析连接串，返回 (libpq conninfo, 池配置)。
 * 支持两种输入：
 *   1. URL 形式：postgres://user:pass@host:port/db?sslmode=disable&pool.max=20
 *      （postgresql:// 同义；非标准端口/缺省端口/缺省 dbname 均兼容）
 *   2. libpq keyword 形式：host=h port=p user=u password=p dbname=d sslmode=disable pool.max=20
 * pool.max / pool.min / pool.idleTimeout 三个键从连接串中剥离用于建池，其余原样交给 libpq。
 */
public func parseConnString(input: String): (String, PoolConfig) {
    let s = input.trimAscii()
    if (s.startsWith("postgres://") || s.startsWith("postgresql://")) {
        return parseUrlForm(s)
    }
    return parseKeywordForm(s)
}

// URL 形式解析：拆出 user/password/host/port/dbname/query，剥离 pool.*，重建 keyword conninfo。
func parseUrlForm(url: String): (String, PoolConfig) {
    var rest = url
    // 去掉 scheme
    if (rest.startsWith("postgresql://")) {
        rest = rest["postgresql://".size..rest.size]
    } else {
        rest = rest["postgres://".size..rest.size]
    }
    // 分离 query
    var query = ""
    let qIdx = indexOfByte(rest, 63u8) // '?'
    if (let Some(i) <- qIdx) {
        query = rest[i + 1..rest.size]
        rest = rest[0..i]
    }
    // 分离 fragment(忽略)
    let fIdx = indexOfByte(rest, 35u8) // '#'
    if (let Some(i) <- fIdx) {
        rest = rest[0..i]
    }
    // userinfo 与 host:port 以 '@' 分隔
    var user = ""
    var password = ""
    var hostpath = rest
    let atIdx = lastIndexOfByte(rest, 64u8) // '@'
    if (let Some(i) <- atIdx) {
        let userinfo = rest[0..i]
        hostpath = rest[i + 1..rest.size]
        let colonIdx = indexOfByte(userinfo, 58u8) // ':'
        if (let Some(j) <- colonIdx) {
            user = percentDecode(userinfo[0..j])
            password = percentDecode(userinfo[j + 1..userinfo.size])
        } else {
            user = percentDecode(userinfo)
        }
    }
    // host[:port]/dbname (host 可能是 IPv6 [::1]，此处按常见 IPv4/host 处理)
    var host = "127.0.0.1"
    var port = "5432"
    var dbname = "postgres"
    // 去掉可能的 [] 包裹(IPv6)
    var hp = hostpath
    // 找第一个 '/' 分隔 host:port 与 dbname
    let slashIdx = indexOfByte(hp, 47u8) // '/'
    var hostport = hp
    if (let Some(i) <- slashIdx) {
        hostport = hp[0..i]
        let db = hp[i + 1..hp.size]
        if (!db.isEmpty()) {
            dbname = percentDecode(db)
        }
    }
    // 拆 host:port
    let pcIdx = lastIndexOfByte(hostport, 58u8) // ':'
    if (let Some(j) <- pcIdx) {
        let h = hostport[0..j]
        let p = hostport[j + 1..hostport.size]
        if (!h.isEmpty()) { host = h }
        if (!p.isEmpty()) { port = p }
    } else {
        if (!hostport.isEmpty()) { host = hostport }
    }
    // 处理 query：剥离 pool.* ，其余作为 libpq 参数
    var maxSize: Int64 = 10
    var minSize: Int64 = 0
    var idleMs: Int64 = 0
    let kept = ArrayList<String>()
    if (!query.isEmpty()) {
        for (pair in query.split("&")) {
            if (pair.isEmpty()) {
                continue
            }
            match (indexOfByte(pair, 61u8)) { // '='
                case Some(eq) =>
                    let k = percentDecode(pair[0..eq])
                    let v = percentDecode(pair[eq + 1..pair.size])
                    if (k == "pool.max") {
                        maxSize = parseIntOr(v, maxSize)
                    } else if (k == "pool.min") {
                        minSize = parseIntOr(v, minSize)
                    } else if (k == "pool.idleTimeout") {
                        idleMs = parseIntOr(v, idleMs)
                    } else {
                        kept.add(escapeKv(k) + "=" + escapeKv(v))
                    }
                case None =>
                    kept.add(escapeKv(percentDecode(pair)))
            }
        }
    }
    // 重建 keyword conninfo
    let parts = ArrayList<String>()
    parts.add("host=" + escapeKv(host))
    parts.add("port=" + escapeKv(port))
    if (!user.isEmpty()) { parts.add("user=" + escapeKv(user)) }
    if (!password.isEmpty()) { parts.add("password=" + escapeKv(password)) }
    parts.add("dbname=" + escapeKv(dbname))
    for (k in kept) { parts.add(k) }
    return (joinSpace(parts), PoolConfig(maxSize, minSize, idleMs))
}

// keyword 形式解析：空格分隔的 k=v，剥离 pool.*。
func parseKeywordForm(s: String): (String, PoolConfig) {
    var maxSize: Int64 = 10
    var minSize: Int64 = 0
    var idleMs: Int64 = 0
    let kept = ArrayList<String>()
    for (part in s.split(" ")) {
        if (part.isEmpty()) {
            continue
        }
        match (indexOfByte(part, 61u8)) {
            case Some(eq) =>
                let k = part[0..eq]
                let v = part[eq + 1..part.size]
                if (k == "pool.max") {
                    maxSize = parseIntOr(v, maxSize)
                } else if (k == "pool.min") {
                    minSize = parseIntOr(v, minSize)
                } else if (k == "pool.idleTimeout") {
                    idleMs = parseIntOr(v, idleMs)
                } else {
                    kept.add(part)
                }
            case None => kept.add(part)
        }
    }
    return (joinSpace(kept), PoolConfig(maxSize, minSize, idleMs))
}

// ----- 工具 -----

func indexOfByte(s: String, b: UInt8): ?Int64 {
    let a = s.toArray()
    for (i in 0..a.size) {
        if (a[i] == b) {
            return Some(i)
        }
    }
    return None
}

func lastIndexOfByte(s: String, b: UInt8): ?Int64 {
    let a = s.toArray()
    var i = a.size - 1
    while (i >= 0) {
        if (a[i] == b) {
            return Some(i)
        }
        i -= 1
    }
    return None
}

func parseIntOr(s: String, fallback: Int64): Int64 {
    try {
        Int64.parse(s.trimAscii())
    } catch (_: Exception) {
        fallback
    }
}

func joinSpace(parts: ArrayList<String>): String {
    let sb = StringBuilder()
    var first = true
    for (p in parts) {
        if (!first) {
            sb.append(" ")
        }
        sb.append(p)
        first = false
    }
    return sb.toString()
}

// conninfo 值若含空白/等号/反斜杠/单引号，用单引号包裹并转义(libpq 规则)。
func escapeKv(s: String): String {
    let a = s.toArray()
    var needQuote = a.size == 0
    for (b in a) {
        if (b == 32u8 || b == 61u8 || b == 92u8 || b == 39u8) {
            needQuote = true
            break
        }
    }
    if (!needQuote) {
        return s
    }
    let out = ArrayList<UInt8>()
    out.add(39u8) // '\''
    for (b in a) {
        if (b == 92u8 || b == 39u8) {
            out.add(92u8) // '\'
        }
        out.add(b)
    }
    out.add(39u8) // '\''
    return String.fromUtf8(out.toArray())
}

// percent-decode (%XX -> 字节)。UTF-8 字节序列再拼回 String。
func percentDecode(s: String): String {
    let a = s.toArray()
    let out = ArrayList<UInt8>()
    var i = 0
    while (i < a.size) {
        if (a[i] == 37u8 && i + 2 < a.size) { // '%'
            let hi = hexVal(a[i + 1])
            let lo = hexVal(a[i + 2])
            out.add(hi * 16u8 + lo)
            i += 3
            continue
        }
        out.add(a[i])
        i += 1
    }
    return String.fromUtf8(out.toArray())
}
