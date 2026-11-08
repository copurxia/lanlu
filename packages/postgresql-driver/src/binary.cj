package postgresql_driver

import std.collection.*
import std.convert.*

// ===== 二进制结果协议支持 =====
//
// 白名单（与 native/lanlu_pg_bridge.c llpg_binary_result_format 一致）：
//   bool(16) bytea(17) int8(20) int2(21) int4(23) text(25) varchar(1043) uuid(2950)
//
// ===== 决策记录：float4(700)/float8(701) 不进白名单 =====
// C 侧 %.17g 与 PG 文本协议的最短往返表示在仓颉 parseFloat64 下存在 ULP 级差异
// （实测 e=2.718281828459045：bin …0464671 vs text …0450908，delta 4.4e-16）。
// 两者各自“可往返”到相邻的不同 double，没有既短又跨语言一致的格式化算法。
// float 列恒走文本协议；【改白名单时不要把 float 加回来】，除非仓颉侧先有
// 位模式精确的 float 解析（bits ctor）配套。
//
// 全部列命中白名单才启用 resultFormat=1；否则整条退回文本协议（仅限只读 SELECT，
// 见 connection.cj runBinaryAware 的写语句禁令）。
// timestamptz/numeric/array/json 的二进制表示复杂，不在首轮范围——自动落回文本。
//
// 解码分两层：
// - 整型/布尔/文本/字节/uuid：仓颉侧大端解码（本文件 decodeBinaryCell）
// - float4/float8：经 bridge 的 llpg_f64_text/llpg_f32_text（C printf %.17g/%.9g 与
//   PG 文本协议最短往返表示一致，避免手写 IEEE754）

/** 该 OID 是否在二进制解码白名单内。 */
func binaryDecodableOid(oid: Int32): Bool {
    // float4/float8 移出白名单（%.17g 与 PG 最短往返表示 ULP 差异，float 列走文本）
    oid == OID_BOOL || oid == OID_BYTEA || oid == OID_INT8 || oid == OID_INT2 ||
        oid == OID_INT4 || oid == OID_TEXT || oid == OID_VARCHAR || oid == OID_UUID
}

// bridge 浮点文本化（纯内存，@FastNative 安全）
@FastNative
foreign func llpg_f64_text(bits: UInt64): CString

@FastNative
foreign func llpg_f32_text(bits: UInt32): CString

/**
 * 大端二进制 cell -> 文本协议等价字符串（PgRowData.values 复用现有读取器）。
 * 解码失败返回 None（调用方应让该查询退回文本协议）。
 *
 * 与文本协议对齐约定：bool "t"/"f"；int 十进制；float 用 %.17g/%.9g（最短往返）；
 * bytea "\x"+hex；text/varchar/uuid 原样 UTF-8。
 */
func decodeBinaryCell(oid: Int32, bytes: Array<UInt8>): ?String {
    // 注意：const let 顶层名在 match pattern 中会被当作变量绑定，故用 if 链。
    if (oid == OID_BOOL) {
        if (bytes.size != 1) { return None }
        return Some(if (bytes[0] != 0u8) { "t" } else { "f" })
    }
    if (oid == OID_INT2) {
        if (bytes.size != 2) { return None }
        return Some(beInt64(bytes, 2).toString())
    }
    if (oid == OID_INT4) {
        if (bytes.size != 4) { return None }
        return Some(beInt64(bytes, 4).toString())
    }
    if (oid == OID_INT8) {
        if (bytes.size != 8) { return None }
        return Some(beInt64(bytes, 8).toString())
    }
    if (oid == OID_FLOAT4) {
        if (bytes.size != 4) { return None }
        return Some(unsafe { llpg_f32_text(UInt32(beUint64(bytes, 4))) }.toString())
    }
    if (oid == OID_FLOAT8) {
        if (bytes.size != 8) { return None }
        return Some(unsafe { llpg_f64_text(beUint64(bytes, 8)) }.toString())
    }
    if (oid == OID_BYTEA) {
        return Some("\\x" + bytesToHex(bytes))
    }
    if (oid == OID_UUID) {
        // UUID 二进制是 16 字节原始值（big-endian time-low/mid/hi 结构），非文本；
        // 需格式化为标准 8-4-4-4-12 文本（与 PG 文本协议输出一致）。
        if (bytes.size != 16) { return None }
        // PG 文本输出：uuid 各字段按 big-endian 展示（与二进制存储顺序一致）
        let hex = bytesToHex(bytes)
        // 8-4-4-4-12
        return Some(hex[0..8] + "-" + hex[8..12] + "-" + hex[12..16] + "-" + hex[16..20] + "-" + hex[20..32])
    }
    if (oid == OID_TEXT || oid == OID_VARCHAR) {
        return Some(String.fromUtf8(bytes))
    }
    return None
}

/** 大端有符号整型（n ∈ {2,4,8}，符号扩展）。仓颉 Int64(UInt64) 数值转换有溢出检查，
 * 负数走符号-幅值法：补码取反 + 1 得幅值（<= 2^63），特判 Int64.MinValue。 */
func beInt64(bytes: Array<UInt8>, n: Int64): Int64 {
    var v: UInt64 = 0
    for (i in 0..n) {
        v = (v << 8) | UInt64(bytes[i])
    }
    if (n < 8) {
        let signBit: UInt64 = 1u64 << (n * 8 - 1)
        if ((v & signBit) != 0u64) {
            let mask: UInt64 = (1u64 << (n * 8)) - 1u64
            v = v | (UInt64.Max ^ mask)
        }
    }
    if ((v & 0x8000000000000000u64) != 0u64) {
        let mag = (v ^ 0xFFFFFFFFFFFFFFFFu64) + 1u64
        if (mag == 0x8000000000000000u64) {
            return -9223372036854775807i64 - 1
        }
        return -Int64(mag)
    }
    return Int64(v)
}

/** 大端无符号（n 字节）。 */
func beUint64(bytes: Array<UInt8>, n: Int64): UInt64 {
    var v: UInt64 = 0
    for (i in 0..n) {
        v = (v << 8) | UInt64(bytes[i])
    }
    v
}
