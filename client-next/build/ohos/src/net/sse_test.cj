package lanlu_client_next.net

import std.collection.ArrayList
import std.io.InputStream
import std.unittest.*
import std.unittest.testmacro.*

// 限块输入流：每次 read 至多交付 maxChunk 字节，模拟帧/多字节字符被 TCP 分片切断。
private class ChunkedStream <: InputStream {
    private let data: Array<UInt8>
    private let maxChunk: Int64
    private var pos: Int64 = 0
    init(data: Array<UInt8>, maxChunk: Int64) {
        this.data = data
        this.maxChunk = maxChunk
    }
    public func read(buffer: Array<UInt8>): Int64 {
        if (pos >= data.size) { return 0 }
        var n = data.size - pos
        if (n > maxChunk) { n = maxChunk }
        if (n > buffer.size) { n = buffer.size }
        for (i in 0..n) { buffer[i] = data[pos + i] }
        pos += n
        return n
    }
}

@Test
func sseFirstDataFrames(): Unit {
    // 完整帧：event/id 行忽略，只取 data 负载
    let d = sseFirstData("event: snapshot\nid: 1\ndata: {\"tasks\":[],\"total\":0}\n\n")
    @Expect(d ?? "", "{\"tasks\":[],\"total\":0}")
    // 未完整（无空行结尾）返回 None
    match (sseFirstData("data: {\"tasks\":[]")) {
        case None => ()
        case Some(_) => @Expect(1, 0)  // 不应到达
    }
    // 前缀是注释行/心跳也跳过
    let d2 = sseFirstData(": ping\n\ndata: hello\n\n")
    @Expect(d2 ?? "", "hello")
}

@Test
func sseFrameEventName(): Unit {
    @Expect(sseFrameEvent("event: snapshot\nid: 1\ndata: {}\n\n"), "snapshot")
    @Expect(sseFrameEvent("data: {}\n\n"), "")
}

@Test
func readSseStreamDeliversEveryFrame(): Unit {
    // 多帧 + 心跳帧逐帧回调，event 名随帧带上。
    let text = "event: snapshot\nid: 1\ndata: {\"total\":1}\n\nevent: ping\nid: 2\ndata: {\"ok\":1}\n\n" +
        "event: tasks\nid: 3\ndata: {\"total\":2}\n\n"
    let events = ArrayList<String>()
    readSseStream(ChunkedStream(text.toArray(), 7), { event, data =>
        events.add("${event}|${data}")
        true
    })
    @Expect(events.size, 3)
    @Expect(events[0], "snapshot|{\"total\":1}")
    @Expect(events[1], "ping|{\"ok\":1}")
    @Expect(events[2], "tasks|{\"total\":2}")
}

@Test
func readSseStreamStopsWhenCallbackReturnsFalse(): Unit {
    let text = "data: first\n\ndata: second\n\n"
    let got = ArrayList<String>()
    readSseStream(ChunkedStream(text.toArray(), 8192), { _, data =>
        got.add(data)
        false
    })
    @Expect(got.size, 1)
    @Expect(got[0], "first")
}

@Test
func readSseStreamDecodesUtf8SplitAcrossReads(): Unit {
    // 多字节字符（"任" 3 字节）跨 read 切断：整帧集齐后解码不得抛异常。
    let text = "data: {\"name\":\"任务\"}\n\n"
    let got = ArrayList<String>()
    readSseStream(ChunkedStream(text.toArray(), 4), { _, data =>
        got.add(data)
        true
    })
    @Expect(got.size, 1)
    @Expect(got[0], "{\"name\":\"任务\"}")
}

@Test
func readSseStreamRejectsOversizedFrame(): Unit {
    let text = "data: " + String.join(Array<String>(300, { _ => "x" })) + "\n\n"
    var threw = false
    try {
        readSseStream(ChunkedStream(text.toArray(), 8192), { _, _ => true }, maxFrameBytes: 64)
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
}
