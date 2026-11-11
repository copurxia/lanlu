package lwindow

// backend.lwp / backend.headless 的全链路测试：
// 假壳（HeadlessShell）发送 -> liblwp 通道 -> pollLwpEvents 解码 -> LWindowEvent。
// 这是第一条「引擎侧真正走协议」的路径（计划 §10 M1）。

import lwp.*
import std.env.setVariable
import std.collection.ArrayList

@Test
func pointerButtonRoundTrip(): Unit {
    let shell = HeadlessShell(name: "lwin-t1")
    shell.handshake()
    shell.pointerButton(120.5f32, 80.25f32, 0, true)
    shell.pointerButton(120.5f32, 80.25f32, 0, false)
    let evs = pollLwpEvents(shell.channel())
    // hello 会被漏斗过滤（非 input 接口），只剩两条按键
    @Expect(evs.size, 2)
    @Expect(evs[0].kind, LWindowEventType.PointerDown)
    @Expect(evs[0].x, 120.5f32)
    @Expect(evs[0].y, 80.25f32)
    @Expect(evs[0].key, 0)
    @Expect(evs[0].pressed, true)
    @Expect(evs[1].kind, LWindowEventType.PointerUp)
    @Expect(evs[1].pressed, false)
    shell.channel().close()
}

@Test
func motionAxisKeyTextDecode(): Unit {
    let shell = HeadlessShell(name: "lwin-t2")
    shell.handshake()
    shell.pointerMotion(1.0f32, 2.0f32)
    shell.pointerAxis(0.0f32, -3.0f32)
    shell.key(30, true)
    shell.textInput("你好")
    let evs = pollLwpEvents(shell.channel())
    @Expect(evs.size, 4)
    @Expect(evs[0].kind, LWindowEventType.PointerMove)
    @Expect(evs[1].kind, LWindowEventType.PointerAxis)
    @Expect(evs[1].y, -3.0f32)
    @Expect(evs[2].kind, LWindowEventType.Key)
    @Expect(evs[2].key, 30)
    @Expect(evs[2].pressed, true)
    @Expect(evs[3].kind, LWindowEventType.TextInput)
    @Expect(evs[3].text, "你好")
    shell.channel().close()
}

@Test
func unknownMessageIsDroppedNotFatal(): Unit {
    let shell = HeadlessShell(name: "lwin-t3")
    shell.handshake()
    // 伪造一条未定义消息：input 接口 + 超出范围的 opcode
    let _ = shell.channel().send(LWP_EVENT, LWP_IFACE_LW_INPUT, 200, Array<UInt8>(8, repeat: 0))
    shell.pointerButton(1.0f32, 2.0f32, 1, true)
    let evs = pollLwpEvents(shell.channel())
    @Expect(evs.size, 1)
    @Expect(evs[0].kind, LWindowEventType.PointerDown)
    shell.channel().close()
}

@Test
func trailingHelloOnlyYieldsNoEvents(): Unit {
    let shell = HeadlessShell(name: "lwin-t4")
    shell.handshake()
    let evs = pollLwpEvents(shell.channel())
    @Expect(evs.size, 0)   // core.hello 不是输入事件
    shell.channel().close()
}

// 录制 -> 回放：证明「.lwtrace 里的壳侧消息」能重建出同样的事件序列
// （计划 §16.3 回放、M0-6 输入回放基线的载体）。
@Test
func recordThenReplayYieldsSameEvents(): Unit {
    let tracePath = "/workspace/lanlu/tmp/lwpt/lwindow-replay.lwtrace"
    let rec = HeadlessShell(name: "lwin-rec")
    @Expect(rec.channel().traceOpen(tracePath), true)
    rec.handshake()
    rec.pointerButton(10.0f32, 20.0f32, 0, true)
    rec.pointerMotion(11.0f32, 21.0f32)
    rec.key(65, true)
    rec.textInput("abc")
    let live = pollLwpEvents(rec.channel())
    rec.channel().traceClose()
    @Expect(live.size, 4)

    // 回放进一个全新通道，引擎侧走同一条漏斗
    let replay = HeadlessShell(name: "lwin-replay")
    let n = replay.channel().replay(tracePath)
    @Expect(n, 5)   // hello + 4 条事件（回放的是“发送”记录）
    let replayed = pollLwpEvents(replay.channel())
    @Expect(replayed.size, live.size)
    for (i in 0..live.size) {
        @Expect(replayed[i].kind, live[i].kind)
        @Expect(replayed[i].x, live[i].x)
        @Expect(replayed[i].y, live[i].y)
        @Expect(replayed[i].key, live[i].key)
        @Expect(replayed[i].text, live[i].text)
    }
    rec.channel().close()
    replay.channel().close()
}

// 输入源开关（过渡期）：LANLU_LWP=1 时引擎走协议通道而不是文件桥
@Test
func lwpInputSwitchFollowsEnv(): Unit {
    setVariable("LANLU_LWP", "0")
    @Expect(lwpInputEnabled(), false)
    setVariable("LANLU_LWP", "1")
    @Expect(lwpInputEnabled(), true)
    setVariable("LANLU_LWP", "0")
}

// 引擎侧取事件的完整路径：壳发事件 -> 通道 -> nextLwpEvent
@Test
func nextLwpEventDrainsInOrder(): Unit {
    let shell = HeadlessShell(name: "lanlu")   // 与 initLwpInput 默认通道名一致
    shell.handshake()
    shell.pointerButton(5.0f32, 6.0f32, 0, true)
    shell.pointerMotion(7.5f32, 8.5f32)
    shell.textInput("hi")
    @Expect(initLwpInput(), true)

    let e1 = evOrUnknown(nextLwpEvent())
    @Expect(e1.kind, LWindowEventType.PointerDown)
    @Expect(e1.x, 5.0f32)
    let e2 = evOrUnknown(nextLwpEvent())
    @Expect(e2.kind, LWindowEventType.PointerMove)
    @Expect(e2.y, 8.5f32)
    let e3 = evOrUnknown(nextLwpEvent())
    @Expect(e3.kind, LWindowEventType.TextInput)
    @Expect(e3.text, "hi")
    // 队列空 -> None（不阻塞、不抛）
    @Expect(nextLwpEvent().isNone(), true)
}

func evOrUnknown(ev: ?LWindowEvent): LWindowEvent {
    match (ev) {
        case Some(e) => e
        case None => LWindowEvent(LWindowEventType.Unknown, 0.0f32, 0.0f32)
    }
}
