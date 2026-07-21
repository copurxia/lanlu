package lanlu_client_next.net

import std.unittest.*
import std.unittest.testmacro.*

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
