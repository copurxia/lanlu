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

// 提取单帧的 event 名（无 event 行返回空串，即 SSE 默认 message 事件）。
public func sseFrameEvent(frame: String): String {
    for (line in frame.split("\n")) {
        if (line.startsWith("event:")) {
            return line[6..].trimAscii()
        }
    }
    return ""
}

// 持续读取 SSE 流：每个含 data 的完整帧回调 (event, data)；onData 返回 false 或流结束
// （read <= 0）时返回。多字节字符可能跨 read 切断，直接分片 fromUtf8 会抛异常，故只在
// 拿到以 \n\n 结尾的完整帧后整段解码（帧边界为 ASCII，完整帧必为合法 UTF-8）；
// 已消费前缀超 64KB 才压缩搬运，常规帧率下零拷贝累积。单帧超过 maxFrameBytes 视为
// 对端/代理异常，抛异常让调用方走重连。
public func readSseStream(stream: InputStream, onData: (String, String) -> Bool,
    maxFrameBytes!: Int64 = 262144): Unit {
    let buf = ArrayList<UInt8>()
    let chunk = Array<UInt8>(8192, { _ => 0 })
    var start: Int64 = 0
    while (true) {
        let n = stream.read(chunk)
        if (n <= 0) { return }
        for (i in 0..n) { buf.add(chunk[i]) }
        while (true) {
            let idx = indexOfDoubleLf(buf, start)
            if (idx < 0) { break }
            if (idx + 2 - start > maxFrameBytes) {
                throw Exception("SSE frame exceeds ${maxFrameBytes} bytes")
            }
            let frameText = String.fromUtf8(buf.toArray()[start..(idx + 2)])
            start = idx + 2
            match (sseFirstData(frameText)) {
                case Some(data) => if (!onData(sseFrameEvent(frameText), data)) { return }
                case None => ()
            }
        }
        if (buf.size - start > maxFrameBytes) {
            throw Exception("SSE frame exceeds ${maxFrameBytes} bytes")
        }
        if (start == buf.size) {
            buf.clear()
            start = 0
        } else if (start > 65536) {
            let rest = buf.toArray()[start..]
            buf.clear()
            for (b in rest) { buf.add(b) }
            start = 0
        }
    }
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
