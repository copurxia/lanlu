package qwest

import std.collection.ArrayList

// HTTP 头集合：保序、大小写不敏感、同名多值（Set-Cookie 等场景）。
// 规模是每响应十几个头，线性扫描即可，不值得引入 HashMap + 归一化键的复杂度。
public class Headers <: ToString {
    private let entries = ArrayList<(String, String)>()

    public init() {}

    // 追加一条（保留已有同名头）。
    public func add(name: String, value: String): Unit {
        entries.add((name, value))
    }

    // 覆盖设置：先删同名（不区分大小写）再追加。
    public func set(name: String, value: String): Unit {
        remove(name)
        entries.add((name, value))
    }

    // 第一个同名头的值。
    public func get(name: String): ?String {
        for ((k, v) in entries) {
            if (equalsIgnoreAsciiCase(k, name)) {
                return Some(v)
            }
        }
        None
    }

    public func getAll(name: String): ArrayList<String> {
        let out = ArrayList<String>()
        for ((k, v) in entries) {
            if (equalsIgnoreAsciiCase(k, name)) {
                out.add(v)
            }
        }
        out
    }

    public func contains(name: String): Bool {
        get(name).isSome()
    }

    public func remove(name: String): Unit {
        var i = entries.size - 1
        while (i >= 0) {
            let (k, _) = entries[i]
            if (equalsIgnoreAsciiCase(k, name)) {
                entries.remove(at: i)
            }
            i--
        }
    }

    public prop size: Int64 {
        get() {
            entries.size
        }
    }

    // 遍历入口（写请求头/调试打印用）。
    public func toArray(): Array<(String, String)> {
        entries.toArray()
    }

    public func toString(): String {
        let sb = StringBuilder()
        for ((k, v) in entries) {
            sb.append("${k}: ${v}\r\n")
        }
        sb.toString()
    }

    // 头名比较的零分配路径：逐字节 ASCII 折叠比较，不为每次查找生成小写副本
    //（get/remove 在每响应路径上对每个头名调用，原 lowerAscii 每次分配新串）。
    static func equalsIgnoreAsciiCase(a: String, b: String): Bool {
        if (a.size != b.size) {
            return false
        }
        let ab = a.toArray()
        let bb = b.toArray()
        for (i in 0..ab.size) {
            var x = ab[i]
            var y = bb[i]
            if (x >= 0x41u8 && x <= 0x5Au8) {
                x += 0x20u8
            }
            if (y >= 0x41u8 && y <= 0x5Au8) {
                y += 0x20u8
            }
            if (x != y) {
                return false
            }
        }
        true
    }

    // 仅折叠 ASCII 大写，头名是 token（ASCII），无需完整 Unicode 折叠。
    static func lowerAscii(s: String): String {
        let bytes = s.toArray()
        var needs = false
        for (b in bytes) {
            if (b >= 0x41u8 && b <= 0x5Au8) {
                needs = true
                break
            }
        }
        if (!needs) {
            return s
        }
        let out = Array<UInt8>(bytes.size, repeat: 0u8)
        for (i in 0..bytes.size) {
            let b = bytes[i]
            out[i] = if (b >= 0x41u8 && b <= 0x5Au8) {
                b + 0x20u8
            } else {
                b
            }
        }
        unsafe { String.fromUtf8Unchecked(out) }
    }
}
