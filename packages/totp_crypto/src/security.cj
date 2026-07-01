package totp_crypto

import std.collection.*
import std.random.Random

/**
 * ignite.security 兼容实现（StdxFallback 纯仓颉 AEAD，无 jinguissl 依赖）。
 * 仅提供 totp_utils 等业务用到的 SecurityConfig / SecurityProviderKind / encryptEnvelopeV1Text / decryptEnvelopeV1ToText / hexToBytes。
 * EnvelopeV1 格式与 ignite 保持一致，保证已加密数据可解密。
 */

public enum SecurityProviderKind <: Equatable<SecurityProviderKind> & ToString {
    | jinguiSSL
    | StdxFallback
    public operator func ==(right: SecurityProviderKind): Bool {
        match ((this, right)) {
            case (jinguiSSL, jinguiSSL) => true
            case (StdxFallback, StdxFallback) => true
            case _ => false
        }
    }
    public operator func !=(right: SecurityProviderKind): Bool {
        !(this == right)
    }
    public func toString(): String {
        match (this) {
            case jinguiSSL => "jinguiSSL"
            case StdxFallback => "stdx-fallback"
        }
    }
}

public class SecurityConfig {
    public var providerKind: SecurityProviderKind
    public var activeKid: String
    public var keyRing: HashMap<String, Array<UInt8>>
    public var aeadAlgorithm: String

    public init(
        providerKind!: SecurityProviderKind = StdxFallback,
        activeKid!: String = "k1",
        keyRing!: HashMap<String, Array<UInt8>> = HashMap<String, Array<UInt8>>(),
        aeadAlgorithm!: String = "AES-256-GCM"
    ) {
        this.providerKind = providerKind
        this.activeKid = activeKid
        this.keyRing = HashMap<String, Array<UInt8>>()
        this.aeadAlgorithm = aeadAlgorithm.trimAscii().toAsciiUpper()
        for ((kid, key) in keyRing) {
            this.keyRing.add(kid, key)
        }
    }

    public func activeKey(): Array<UInt8> {
        match (keyRing.get(activeKid)) {
            case Some(key) => key
            case None => throw Exception("active key id not found: ${activeKid}")
        }
    }
}

// ── EnvelopeV1 ──

class EnvelopeV1 {
    let v: Int64
    let alg: String
    let kid: String
    let nonce: String
    let ct: String
    let tag: String

    init(v: Int64, alg: String, kid: String, nonce: String, ct: String, tag: String) {
        this.v = v
        this.alg = alg
        this.kid = kid
        this.nonce = nonce
        this.ct = ct
        this.tag = tag
    }

    func toJsonString(): String {
        "{\"v\":1,\"alg\":\"${alg}\",\"kid\":\"${kid}\",\"nonce\":\"${nonce}\",\"ct\":\"${ct}\",\"tag\":\"${tag}\"}"
    }

    static func parse(json: String): EnvelopeV1 {
        let compact = removeAsciiSpaces(json)
        let version = extractIntField(compact, "v")
        let alg = extractStringField(compact, "alg")
        let kid = extractStringField(compact, "kid")
        let nonce = extractStringField(compact, "nonce")
        let ct = extractStringField(compact, "ct")
        let tag = extractStringField(compact, "tag")
        EnvelopeV1(version, alg, kid, nonce, ct, tag)
    }
}

// ── Public API ──

public func encryptEnvelopeV1Text(
    config: SecurityConfig,
    text: String,
    aadText!: String = ""
): String {
    let key = config.activeKey()
    let nonce = randomBytes(12)
    let plaintext = text.toArray()
    let aad = aadText.toArray()
    let stream = deriveStream(key, nonce, Int64(plaintext.size))
    let ciphertext = xorWithStream(plaintext, stream)
    let tag = fallbackTag(key, nonce, ciphertext, aad)
    let envelope = EnvelopeV1(
        1,
        config.aeadAlgorithm,
        config.activeKid,
        base64UrlEncode(nonce),
        base64UrlEncode(ciphertext),
        base64UrlEncode(tag)
    )
    envelope.toJsonString()
}

public func decryptEnvelopeV1ToText(
    config: SecurityConfig,
    envelopeJson: String,
    aadText!: String = ""
): String {
    let envelope = EnvelopeV1.parse(envelopeJson)
    match (config.keyRing.get(envelope.kid)) {
        case Some(key) =>
            let nonce = base64UrlDecode(envelope.nonce)
            let ct = base64UrlDecode(envelope.ct)
            let tag = base64UrlDecode(envelope.tag)
            let aad = aadText.toArray()
            let expected = fallbackTag(key, nonce, ct, aad)
            if (!constantTimeEquals(expected, tag)) {
                throw Exception("tag mismatch")
            }
            let stream = deriveStream(key, nonce, Int64(ct.size))
            String.fromUtf8(xorWithStream(ct, stream))
        case None => throw Exception("key id not found: ${envelope.kid}")
    }
}

public func hexToBytes(hex: String): Array<UInt8> {
    let runes = hex.toRuneArray()
    let out = ArrayList<UInt8>()
    var i: Int64 = 0
    while (i + 1 < runes.size) {
        let hi = digitOfHex(runes[i])
        let lo = digitOfHex(runes[i + 1])
        out.add(UInt8((hi << 4) | lo))
        i += 2
    }
    out.toArray()
}

func digitOfHex(ch: Rune): Int64 {
    match (ch) {
        case r'0' => 0
        case r'1' => 1
        case r'2' => 2
        case r'3' => 3
        case r'4' => 4
        case r'5' => 5
        case r'6' => 6
        case r'7' => 7
        case r'8' => 8
        case r'9' => 9
        case r'a' | r'A' => 10
        case r'b' | r'B' => 11
        case r'c' | r'C' => 12
        case r'd' | r'D' => 13
        case r'e' | r'E' => 14
        case r'f' | r'F' => 15
        case _ => throw Exception("invalid hex char")
    }
}

// ── StdxFallback AEAD (纯仓颉) ──

func randomBytes(size: Int64): Array<UInt8> {
    let rng = Random()
    let out = Array<UInt8>(size, repeat: 0)
    var i: Int64 = 0
    while (i < size) {
        out[i] = UInt8(rng.nextUInt64() & 0xFF)
        i += 1
    }
    out
}

func deriveStream(key: Array<UInt8>, nonce: Array<UInt8>, size: Int64): Array<UInt8> {
    let stream = Array<UInt8>(size, repeat: 0)
    var state: UInt64 = 0x9E3779B97F4A7C15
    for (b in key) {
        state = (state << 5) ^ (state >> 2) ^ UInt64(b)
    }
    for (b in nonce) {
        state = (state << 7) ^ (state >> 3) ^ UInt64(b)
    }
    var i: Int64 = 0
    while (i < size) {
        state = state ^ (state << 13)
        state = state ^ (state >> 7)
        state = state ^ (state << 17)
        stream[i] = UInt8(state & 0xFF)
        i += 1
    }
    stream
}

func xorWithStream(input: Array<UInt8>, stream: Array<UInt8>): Array<UInt8> {
    let out = Array<UInt8>(input.size, repeat: 0)
    var i: Int64 = 0
    while (i < input.size) {
        out[i] = input[i] ^ stream[i]
        i += 1
    }
    out
}

func fallbackTag(
    key: Array<UInt8>,
    nonce: Array<UInt8>,
    ciphertext: Array<UInt8>,
    aad: Array<UInt8>
): Array<UInt8> {
    let acc = Array<UInt8>(16, repeat: 0)
    foldTag(acc, key)
    foldTag(acc, nonce)
    foldTag(acc, aad)
    foldTag(acc, ciphertext)
    acc
}

func foldTag(acc: Array<UInt8>, data: Array<UInt8>): Unit {
    var i: Int64 = 0
    while (i < data.size) {
        let idx = i % 16
        let rot = UInt8((idx * 13 + 7) & 0xFF)
        let mixed = (Int64(acc[idx]) ^ Int64(data[i]))
        acc[idx] = UInt8((mixed + Int64(rot)) & 0xFF)
        i += 1
    }
}

func constantTimeEquals(left: Array<UInt8>, right: Array<UInt8>): Bool {
    if (left.size != right.size) {
        return false
    }
    var diff: UInt8 = 0
    var i: Int64 = 0
    while (i < left.size) {
        diff = diff | (left[i] ^ right[i])
        i += 1
    }
    diff == 0
}

// ── base64url ──

func base64UrlEncode(data: Array<UInt8>): String {
    let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".toRuneArray()
    let out = ArrayList<UInt8>()
    var i: Int64 = 0
    while (i < data.size) {
        let b0 = data[i]
        let b1 = if (i + 1 < data.size) { data[i + 1] } else { 0u8 }
        let b2 = if (i + 2 < data.size) { data[i + 2] } else { 0u8 }
        let triple = (UInt32(b0) << 16) | (UInt32(b1) << 8) | UInt32(b2)
        out.add(UInt8(UInt32(chars[Int64((triple >> 18) & 0x3F)].toString().toRuneArray()[0])))
        out.add(UInt8(UInt32(chars[Int64((triple >> 12) & 0x3F)].toString().toRuneArray()[0])))
        if (i + 1 < data.size) {
            out.add(UInt8(UInt32(chars[Int64((triple >> 6) & 0x3F)].toString().toRuneArray()[0])))
        }
        if (i + 2 < data.size) {
            out.add(UInt8(UInt32(chars[Int64(triple & 0x3F)].toString().toRuneArray()[0])))
        }
        i += 3
    }
    String.fromUtf8(out.toArray())
}

func base64UrlDecode(s: String): Array<UInt8> {
    let runes = s.toRuneArray()
    let lookup = base64UrlLookupTable()
    let out = ArrayList<UInt8>()
    var i: Int64 = 0
    while (i < runes.size) {
        var v0: Int64 = -1
        var v1: Int64 = -1
        var v2: Int64 = -1
        var v3: Int64 = -1
        if (i < runes.size) { v0 = lookupVal(lookup, runes[i]) }
        if (i + 1 < runes.size) { v1 = lookupVal(lookup, runes[i + 1]) }
        if (i + 2 < runes.size) { v2 = lookupVal(lookup, runes[i + 2]) }
        if (i + 3 < runes.size) { v3 = lookupVal(lookup, runes[i + 3]) }
        if (v0 < 0 || v1 < 0) { throw Exception("invalid base64url") }
        let triple = (UInt32(v0) << 18) | (UInt32(v1) << 12)
        out.add(UInt8((triple >> 16) & 0xFF))
        if (v2 >= 0) {
            let t2 = triple | (UInt32(v2) << 6)
            out.add(UInt8((t2 >> 8) & 0xFF))
            if (v3 >= 0) {
                let t3 = t2 | UInt32(v3)
                out.add(UInt8(t3 & 0xFF))
            }
        }
        i += 4
    }
    out.toArray()
}

func base64UrlLookupTable(): HashMap<UInt8, Int64> {
    let table = HashMap<UInt8, Int64>()
    let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    let runes = chars.toRuneArray()
    for (i in 0..runes.size) {
        table.add(UInt8(UInt32(runes[i])), Int64(i))
    }
    table
}

func lookupVal(table: HashMap<UInt8, Int64>, ch: Rune): Int64 {
    match (table.get(UInt8(UInt32(ch)))) {
        case Some(v) => v
        case None => -1
    }
}

// ── JSON field extraction (envelope parse) ──

func removeAsciiSpaces(s: String): String {
    let chars = s.toRuneArray()
    var out = ""
    for (ch in chars) {
        if (ch == r' ' || ch == r'\n' || ch == r'\r' || ch == r'\t') {
            continue
        }
        out += ch.toString()
    }
    out
}

func extractStringField(json: String, key: String): String {
    let pattern = "\"${key}\":\""
    let start = indexOfString(json, pattern)
    if (start < 0) { throw Exception("missing envelope field: ${key}") }
    let valueStart = start + pattern.size
    let valueEnd = indexOfRuneFrom(json, r'\"', valueStart)
    if (valueEnd < 0) { throw Exception("invalid envelope string field: ${key}") }
    substringRange(json, valueStart, valueEnd)
}

func extractIntField(json: String, key: String): Int64 {
    let pattern = "\"${key}\":"
    let start = indexOfString(json, pattern)
    if (start < 0) { throw Exception("missing envelope field: ${key}") }
    var i = start + pattern.size
    let runes = json.toRuneArray()
    var out = ""
    while (i < runes.size) {
        let ch = runes[i]
        if (ch >= r'0' && ch <= r'9') {
            out += ch.toString()
            i += 1
        } else {
            break
        }
    }
    if (out.size == 0) { throw Exception("invalid envelope integer field: ${key}") }
    parseInt64Ascii(out)
}

func parseInt64Ascii(raw: String): Int64 {
    var out: Int64 = 0
    for (ch in raw.toRuneArray()) {
        out = out * 10 + digitOfRune(ch)
    }
    out
}

func indexOfString(s: String, needle: String): Int64 {
    let h = s.toRuneArray()
    let n = needle.toRuneArray()
    if (n.size == 0) { return 0 }
    if (h.size < n.size) { return -1 }
    var i: Int64 = 0
    while (i <= h.size - n.size) {
        var ok = true
        var j: Int64 = 0
        while (j < n.size) {
            if (h[i + j] != n[j]) {
                ok = false
                break
            }
            j += 1
        }
        if (ok) { return i }
        i += 1
    }
    -1
}

func indexOfRuneFrom(s: String, target: Rune, from: Int64): Int64 {
    let chars = s.toRuneArray()
    var i = from
    while (i < chars.size) {
        if (chars[i] == target) {
            return i
        }
        i += 1
    }
    -1
}

func substringRange(s: String, start: Int64, endExclusive: Int64): String {
    let runes = s.toRuneArray()
    var out = ""
    var i = start
    while (i < endExclusive) {
        out += runes[i].toString()
        i += 1
    }
    out
}

func digitOfRune(ch: Rune): Int64 {
    match (ch) {
        case r'0' => 0
        case r'1' => 1
        case r'2' => 2
        case r'3' => 3
        case r'4' => 4
        case r'5' => 5
        case r'6' => 6
        case r'7' => 7
        case r'8' => 8
        case r'9' => 9
        case _ => throw Exception("invalid numeric rune")
    }
}