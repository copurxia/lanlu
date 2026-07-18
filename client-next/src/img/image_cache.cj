package lanlu_client_next.img

import std.collection.ArrayList
import std.fs.{exists, removeIfExists, rename, Directory, File, Path}
import std.sort.sort

// 缓存 key → 安全文件名：仅保留 ASCII 字母/数字和 . - _，其余一律替换为 _。
public func sanitizeKey(s: String): String {
    let out = ArrayList<UInt8>(s.size)
    for (b in s.toArray()) {
        let ok = (b >= 0x61u8 && b <= 0x7Au8) || (b >= 0x41u8 && b <= 0x5Au8) ||
            (b >= 0x30u8 && b <= 0x39u8) || b == 0x2Eu8 || b == 0x2Du8 || b == 0x5Fu8
        out.add(if (ok) { b } else { 0x5Fu8 })
    }
    String.fromUtf8(out.toArray())
}

// 磁盘图片缓存：key → <root>/<sanitize(key)>.png。
// 未命中时 fetch() 拉原始字节写 .bin，转码到 .tmp.png 后原子 rename 定稿（半成品不暴露给 UI）。
public class ImageCache {
    private let root: String

    public init(root: String) {
        this.root = root
        // cjc 1.1.3 的 Directory.create 对已存在目录抛异常，先判断。
        if (!exists(Path(root))) {
            Directory.create(Path(root), recursive: true)
        }
    }

    private func pngPath(relKey: String): String { "${root}/${sanitizeKey(relKey)}.png" }
    private func binPath(relKey: String): String { "${root}/${sanitizeKey(relKey)}.bin" }

    // 命中直接返回；未命中：fetch() 拿字节 → 写 .bin → 转码 .tmp.png → rename 定稿。失败抛异常。
    public func ensurePng(relKey: String, fetch: () -> Array<UInt8>): String {
        let dst = pngPath(relKey)
        if (exists(Path(dst))) { return dst }
        let bytes = fetch()
        if (bytes.size == 0) { throw Exception("图片内容为空") }
        let bin = binPath(relKey)
        File.writeTo(Path(bin), bytes)
        let tmp = "${dst}.tmp.png"
        try {
            transcodeFileToPng(bin, tmp)
            rename(Path(tmp), to: Path(dst), overwrite: true)
        } finally {
            removeIfExists(Path(bin), recursive: false)
            removeIfExists(Path(tmp), recursive: false)
        }
        return dst
    }

    public func totalBytes(): Int64 {
        var total: Int64 = 0
        if (!exists(Path(root))) { return 0 }
        // 缓存目录是扁平的，readFrom 一层即可（walk 的回调不能捕获可变变量）。
        for (info in Directory.readFrom(Path(root))) {
            total += info.size
        }
        return total
    }

    public func clear(): Unit {
        removeIfExists(Path(root), recursive: true)
        Directory.create(Path(root), recursive: true)
    }

    // 简单 LRU：按修改时间升序删到阈值内。
    public func sweep(maxBytes: Int64): Unit {
        if (!exists(Path(root))) { return }
        let entries = ArrayList<(Int64, String, Int64)>()  // (mtimeMs, path, size)
        for (info in Directory.readFrom(Path(root))) {
            // 排除 .tmp.png：在途半成品随时可能被并发 rename 定稿，不能进清理候选。
            if (info.name.endsWith(".png") && !info.name.endsWith(".tmp.png")) {
                entries.add((info.lastModificationTime.toUnixTimeStamp().toMilliseconds(), info.path.toString(), info.size))
            }
        }
        var total: Int64 = 0
        for (e in entries) { total += e[2] }
        if (total <= maxBytes) { return }
        sort(entries, lessThan: { a, b => a[0] < b[0] })
        for (e in entries) {
            if (total <= maxBytes) { break }
            removeIfExists(Path(e[1]), recursive: false)
            total -= e[2]
        }
    }
}
