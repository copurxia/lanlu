/**
 * rawdir_ffi —— 按裸字节枚举目录 + 非 UTF-8 文件名回退解码 + 裸字节安全重命名。
 *
 * 背景：Cangjie std.fs 的 Directory.readFrom / Dirent 要求条目名为合法 UTF-8，
 * 目录里只要有一个 GBK/GB18030 名（Windows 中文环境打包传来的压缩包常见），
 * 整个 readFrom 直接抛异常，上层 catch 后返回空数组——单条坏名“毒化”整个目录，
 * 扫描器表现为“这个目录怎么都扫不出来”。
 *
 * 本包用 POSIX opendir/readdir 拿原始字节，逐条解码：UTF-8 严格解码失败时
 * 落到 iconv GB18030（GBK 超集），再失败则只跳过该条（其余条目不受影响）。
 * 扫描入口处另可调用方用 renameRawEntry 把非 UTF-8 名规范化为解码后的
 * UTF-8 名落盘，后续 std.fs 一切路径操作即可正常工作。
 *
 * 平台：Linux（glibc iconv + dirent.d_type）。Windows 构建不适用。
 */

package rawdir_ffi

import std.collection.*

/*
 * C bridge（native/lanlu_rawdir_bridge.c）。缓冲区由 Cangjie 侧分配持有，
 * C 侧只写入，避免跨语言的指针数组管理。
 */
foreign func lrawdir_list(dirpath: CString, nameBuf: CPointer<UInt8>, nameCap: Int64,
    typeBuf: CPointer<UInt8>, offBuf: CPointer<Int64>, maxEntries: Int64): Int64

foreign func lrawdir_rename_utf8(dirpath: CString, rawName: CPointer<UInt8>, rawLen: Int64,
    newName: CString): Int64

foreign func lrawdir_convert(fromCode: CString, inBuf: CPointer<UInt8>, inLen: Int64,
    outBuf: CPointer<UInt8>, outCap: Int64): Int64

/* dirent d_type（C 侧已过滤成这四种） */
public const RAWDIR_DT_UNKNOWN: UInt8 = 0
public const RAWDIR_DT_FIFO: UInt8 = 1
public const RAWDIR_DT_DIR: UInt8 = 4
public const RAWDIR_DT_REG: UInt8 = 8
public const RAWDIR_DT_LNK: UInt8 = 10

/* C 侧约定的特殊返回码 */
public const RAWDIR_BUFFER_FULL: Int64 = -10001
public const RAWDIR_CHARSET_UNAVAILABLE: Int64 = -10002

/** 单个目录条目：原始字节名（不含 NUL）+ d_type。 */
public struct RawDirEntry {
    public let nameBytes: Array<UInt8>
    public let dType: UInt8

    public init(nameBytes: Array<UInt8>, dType: UInt8) {
        this.nameBytes = nameBytes
        this.dType = dType
    }
}

/** 单次尝试的条目数/名字缓冲区上限；不足时按 8 倍增长重试。 */
private let LIST_MAX_ENTRIES: Int64 = 8192
private let LIST_NAME_CAP_INITIAL: Int64 = 65536
private let LIST_NAME_CAP_MAX: Int64 = 8388608

/**
 * 按裸字节列出目录（跳过 "." / ".."，只保留文件/目录/软链接/UNKNOWN）。
 * 返回 None 表示目录打不开或超出缓冲区上限；错误码可通过 lastListError 获取。
 */
public var lastListError: Int64 = 0

public func listRawEntries(dirPath: String): Option<Array<RawDirEntry>> {
    lastListError = 0
    var nameCap = LIST_NAME_CAP_INITIAL
    /* 64KB 起步按 8 倍扩容重试；LIST_NAME_CAP_MAX 封顶，循环只作兜底。 */
    for (_ in 0..4) {
        let nameBuf = Array<UInt8>(nameCap, { _ => 0 })
        let typeBuf = Array<UInt8>(LIST_MAX_ENTRIES, { _ => 0 })
        let offBuf = Array<Int64>(LIST_MAX_ENTRIES, { _ => 0 })

        let cPath = unsafe { LibC.mallocCString(dirPath) }
        var rc: Int64 = -1
        unsafe {
            let hn = acquireArrayRawData(nameBuf)
            let ht = acquireArrayRawData(typeBuf)
            let ho = acquireArrayRawData(offBuf)
            rc = lrawdir_list(cPath, hn.pointer, nameCap, ht.pointer, ho.pointer, LIST_MAX_ENTRIES)
            releaseArrayRawData(ho)
            releaseArrayRawData(ht)
            releaseArrayRawData(hn)
            LibC.free(cPath)
        }

        if (rc == RAWDIR_BUFFER_FULL) {
            if (nameCap >= LIST_NAME_CAP_MAX) {
                lastListError = RAWDIR_BUFFER_FULL
                return None
            }
            nameCap *= 8
            continue
        }
        if (rc < 0) {
            lastListError = rc
            return None
        }

        let count = rc
        let entries = ArrayList<RawDirEntry>()
        for (i in 0..count) {
            let start = offBuf[i]
            var end = start
            while (end < nameCap && nameBuf[end] != 0) {
                end += 1
            }
            let bytes = nameBuf[start..end]
            if (bytes.size == 0) {
                continue
            }
            entries.add(RawDirEntry(bytes, typeBuf[i]))
        }
        return Some(entries.toArray())
    }
    /* 理论上不可达：缓冲区封顶检查在循环内提前 return。 */
    lastListError = RAWDIR_BUFFER_FULL
    return None
}

/** 字节串是否为合法 UTF-8。 */
public func isUtf8Bytes(bytes: Array<UInt8>): Bool {
    try {
        let _ = String.fromUtf8(bytes)
        return true
    } catch (_: Exception) {
        return false
    }
}

/**
 * 解码条目名：先严格 UTF-8；失败则 iconv GB18030（GBK 的超集，兼容 GB2312）。
 * 两者都失败返回 None（调用方应只跳过这一条，不影响同目录其他条目）。
 *
 * 注意：不做语种启发式。Shift-JIS 等其它多字节编码的字节串可能恰好也是
 * 合法 GB18030 序列，会解码成“错误但合法”的中文——需要日语源支持时
 * 再考虑加编码探测，当前场景（中文 Windows 来源）GBK 优先即正确。
 */
public func tryDecodeBytes(bytes: Array<UInt8>): Option<String> {
    if (bytes.size == 0) {
        return Some("")
    }
    try {
        return Some(String.fromUtf8(bytes))
    } catch (_: Exception) {
        ()
    }
    return tryConvert("GB18030", bytes)
}

private func tryConvert(fromCode: String, bytes: Array<UInt8>): Option<String> {
    let outCap: Int64 = 4096
    let out = Array<UInt8>(outCap, { _ => 0 })
    let cCode = unsafe { LibC.mallocCString(fromCode) }
    var rc: Int64 = -1
    unsafe {
        let hi = acquireArrayRawData(bytes)
        let ho = acquireArrayRawData(out)
        rc = lrawdir_convert(cCode, hi.pointer, Int64(bytes.size), ho.pointer, outCap)
        releaseArrayRawData(ho)
        releaseArrayRawData(hi)
        LibC.free(cCode)
    }
    if (rc <= 0) {
        return None
    }
    let decoded = out[0..rc]
    try {
        return Some(String.fromUtf8(decoded))
    } catch (_: Exception) {
        return None
    }
}

/**
 * 用原始字节名定位条目并重命名为（合法 UTF-8 的）newName。
 * newName 不能与目录中现有条目冲突——碰撞处理由调用方负责。
 * 返回 0 成功，负值为 -errno。
 */
public func renameRawEntry(dirBase: String, rawName: Array<UInt8>, newName: String): Int64 {
    if (rawName.size == 0 || newName.size == 0) {
        return -1
    }
    let cBase = unsafe { LibC.mallocCString(dirBase) }
    let cNew = unsafe { LibC.mallocCString(newName) }
    var rc: Int64 = -1
    unsafe {
        let h = acquireArrayRawData(rawName)
        rc = lrawdir_rename_utf8(cBase, h.pointer, Int64(rawName.size), cNew)
        releaseArrayRawData(h)
        LibC.free(cBase)
        LibC.free(cNew)
    }
    return rc
}
