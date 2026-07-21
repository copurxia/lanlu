package lanlu_client_next.net

import std.collection.ArrayList
import std.io.InputStream

// SSE 文本前缀中首个完整 data 帧（帧以空行 \n\n 结尾）。
// 服务端事件流格式（taskpool_controller）：`event: xxx\nid: N\ndata: {json}\n\n`。
public func sseFirstData(text: String): ?String {
    var rest = text
    while (true) {
        let idx = match (rest.indexOf("\n\n")) {
            case Some(i) => i
            case None => return None
        }
        let frame = rest[0..idx]
        for (line in frame.split("\n")) {
            if (line.startsWith("data:")) {
                return line[5..].trimAscii()
            }
        }
        // 该帧无 data 行（心跳/注释）：跳过继续找下一帧。
        rest = rest[(idx + 2)..]
    }
    return None
}

// 按字节累积读取：多字节字符可能跨 read 切断，直接分片 fromUtf8 会抛异常；
// 只在拿到以 \n\n 结尾的完整帧后整段解码（帧边界为 ASCII，完整帧必为合法 UTF-8）。
public func readSseSnapshot(stream: InputStream, maxBytes!: Int64 = 262144): String {
    let buf = ArrayList<UInt8>()
    let chunk = Array<UInt8>(8192, { _ => 0 })
    while (buf.size < maxBytes) {
        let n = stream.read(chunk)
        if (n <= 0) { break }
        for (i in 0..n) { buf.add(chunk[i]) }
        var searchFrom = 0
        while (true) {
            let idx = indexOfDoubleLf(buf, searchFrom)
            if (idx < 0) { break }
            let frameText = String.fromUtf8(buf.toArray()[0..(idx + 2)])
            match (sseFirstData(frameText)) {
                case Some(_) => return frameText
                case None => searchFrom = idx + 2
            }
        }
    }
    return String.fromUtf8(buf.toArray())
}

// 在字节缓冲中从 from 起查找 "\n\n"（0A 0A）的位置；找不到返回 -1。
private func indexOfDoubleLf(buf: ArrayList<UInt8>, from: Int64): Int64 {
    var i = from
    while (i + 1 < buf.size) {
        if (buf[i] == 0x0A && buf[i + 1] == 0x0A) { return i }
        i += 1
    }
    return -1
}
