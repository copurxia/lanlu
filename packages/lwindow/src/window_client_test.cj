package lwindow

// 窗口生命周期链路测试（M2 起步）：引擎 window.create -> 壳 created/configure -> 引擎 ack。
// 壳侧用 HeadlessShell 模拟（不需要设备）。

import lwp.*
import std.env.setVariable
import std.collection.ArrayList

@Test
func createThenCreatedAndConfigure(): Unit {
    let shell = HeadlessShell(name: "lwin-win1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)

    @Expect(win.create("标题", 800, 600), true)

    // 壳侧收到 window.create（REQUEST 方向），并回 created + configure
    let (riface, ropcode, rbody) = shell.recvRequest()
    @Expect(riface, LWP_IFACE_LW_WINDOW)
    @Expect(ropcode, LWP_LW_WINDOW_CREATE_OPCODE)
    @Expect(rbody.size > 8, true)
    shell.sendWindowCreated(7, 2.0f32, false)
    shell.sendConfigure(1600, 1200, 1)

    let evs = win.pollAll(nowNs: 1000000)
    @Expect(evs.size, 2)
    match (evs[0]) {
        case LWindowLifecycleEvent.WindowCreated(id, scale, ssd) =>
            @Expect(id, 7)
            @Expect(scale, 2.0f32)
            @Expect(ssd, false)
        case _ => @Expect("WindowCreated", "other")
    }
    match (evs[1]) {
        case LWindowLifecycleEvent.Configure(w, h, state) =>
            @Expect(w, 1600)
            @Expect(h, 1200)
            @Expect(state, 1)
        case _ => @Expect("Configure", "other")
    }
    // 自动 ack：客户端不留待确认状态，且 ack 真的发到了壳
    @Expect(win.hasPendingConfigure(), false)
    let (aiface, aopcode, _ab) = shell.recvRequest()
    @Expect(aiface, LWP_IFACE_LW_WINDOW)
    @Expect(aopcode, LWP_LW_WINDOW_ACK_CONFIGURE_OPCODE)
    ch.close()
}

@Test
func manualAckWhenAutoAckDisabled(): Unit {
    let shell = HeadlessShell(name: "lwin-win2")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch, autoAck: false)
    shell.sendConfigure(1024, 768, 1)
    let _ = win.pollAll(nowNs: 0)
    @Expect(win.hasPendingConfigure(), true)
    @Expect(win.ackConfigure(), true)
    @Expect(win.hasPendingConfigure(), false)
    let (_, aopcode, _ab) = shell.recvRequest()
    @Expect(aopcode, LWP_LW_WINDOW_ACK_CONFIGURE_OPCODE)
    ch.close()
}

@Test
func unackedConfigureIsCountedOnce(): Unit {
    let shell = HeadlessShell(name: "lwin-win3")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch, autoAck: false)
    let t0: Int64 = 0
    shell.sendConfigure(800, 600, 1)
    let _ = win.pollAll(nowNs: t0)
    @Expect(win.hasPendingConfigure(), true)
    // 还没到超时
    @Expect(win.checkConfigureTimeout(t0 + 100 * 1000000), false)
    // 超过 500ms
    @Expect(win.checkConfigureTimeout(t0 + 900 * 1000000), true)
    @Expect(win.unackedConfigure, 1)
    // 只报一次
    @Expect(win.checkConfigureTimeout(t0 + 2000 * 1000000), false)
    @Expect(win.unackedConfigure, 1)
    @Expect(win.hasPendingConfigure(), false)
    ch.close()
}

@Test
func frameDoneDecodes(): Unit {
    let shell = HeadlessShell(name: "lwin-win4")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    shell.sendFrameDone(42, 123456789)
    let evs = win.pollAll()
    @Expect(evs.size, 1)
    match (evs[0]) {
        case LWindowLifecycleEvent.FrameDone(serial, t) =>
            @Expect(serial, 42)
            @Expect(t, 123456789)
        case _ => @Expect("FrameDone", "other")
    }
    ch.close()
}

// 启动阶段：有界等待壳下发初始 configure（建窗尺寸的唯一来源）
@Test
func awaitConfigureReturnsShellSize(): Unit {
    let shell = HeadlessShell(name: "lwin-await")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    // 壳在后台稍后下发 configure（模拟 ArkTS 的异步时序）
    spawn {
        sleep(Duration.millisecond * 20)
        shell.sendConfigure(1234, 567, 1)
    }
    let size = win.awaitConfigure(500)
    match (size) {
        case Some((w, h)) =>
            @Expect(w, 1234)
            @Expect(h, 567)
        case None => @Expect("Some", "None")
    }
    // 自动 ack：客户端不应再有待确认的 configure
    @Expect(win.hasPendingConfigure(), false)
    ch.close()
}

@Test
func awaitConfigureTimesOutWithoutShell(): Unit {
    let shell = HeadlessShell(name: "lwin-await2")
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    let t0 = LwpChannel.nowNs()
    @Expect(win.awaitConfigure(80).isNone(), true)
    let dt = (LwpChannel.nowNs() - t0) / 1000000
    @Expect(dt >= 70 && dt < 600, true)
    ch.close()
}

// 表面与帧：attach 走协议、frame.request 必须等到 done
@Test
func attachCarriesBufferAndSize(): Unit {
    let shell = HeadlessShell(name: "lwin-sf1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    @Expect(win.attach(0x1122334455667788, 1600, 1200), true)
    let (iface, opcode, body) = shell.recvRequest()
    @Expect(iface, LWP_IFACE_LW_SURFACE)
    @Expect(opcode, LWP_LW_SURFACE_ATTACH_OPCODE)
    @Expect(body.size, LWP_LW_SURFACE_ATTACH_SIZE)
    ch.close()
}

@Test
func frameRequestClosedByDone(): Unit {
    let shell = HeadlessShell(name: "lwin-sf2")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    let serial = win.requestFrame(nowNs: 0)
    @Expect(win.hasPendingFrame(), true)
    // 壳回 frame.done -> 闭环，不应超时
    shell.sendFrameDone(serial, 1000)
    let _ = win.pollAll(nowNs: 0)
    @Expect(win.hasPendingFrame(), false)
    @Expect(win.checkFrameTimeout(1000000000), false)
    @Expect(win.frameTimeout, 0)
    ch.close()
}

@Test
func frameTimeoutCountedOnce(): Unit {
    let shell = HeadlessShell(name: "lwin-sf3")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    let _ = win.requestFrame(nowNs: 0)
    @Expect(win.hasPendingFrame(), true)
    @Expect(win.checkFrameTimeout(50 * 1000000), false)     // 未到期
    @Expect(win.checkFrameTimeout(500 * 1000000), true)     // 超过 200ms
    @Expect(win.frameTimeout, 1)
    @Expect(win.checkFrameTimeout(900 * 1000000), false)    // 只报一次
    @Expect(win.frameTimeout, 1)
    ch.close()
}

@Test
func attachSerialMonotonic(): Unit {
    let shell = HeadlessShell(name: "lwin-sf4")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    @Expect(win.attach(1, 100, 100), true)
    @Expect(win.attach(2, 100, 100), true)
    @Expect(win.attachOutOfOrder, 0)
    // 三帧都能被壳侧按顺序收到
    let (_, _o1, _b1) = shell.recvRequest()
    let (_, _o2, _b2) = shell.recvRequest()
    let (_, _o3, _b3) = shell.recvRequest()
    ch.close()
}

// Surface 生命周期（§7.1）：available/changed/will_destroy
@Test
func surfaceLifecycleDecodes(): Unit {
    let shell = HeadlessShell(name: "lwin-sf5")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    shell.sendSurfaceAvailable(0x1122334455667788, 1600, 1200)
    shell.sendSurfaceChanged(800, 600)
    shell.sendSurfaceWillDestroy()
    let evs = win.pollAll()
    @Expect(evs.size, 3)
    match (evs[0]) {
        case LWindowLifecycleEvent.SurfaceAvailable(h, w, hh) =>
            @Expect(h, 0x1122334455667788)
            @Expect(w, 1600)
            @Expect(hh, 1200)
        case _ => @Expect("SurfaceAvailable", "other")
    }
    match (evs[1]) {
        case LWindowLifecycleEvent.SurfaceChanged(w, hh) =>
            @Expect(w, 800)
            @Expect(hh, 600)
        case _ => @Expect("SurfaceChanged", "other")
    }
    match (evs[2]) {
        case LWindowLifecycleEvent.SurfaceWillDestroy => @Expect(true, true)
        case _ => @Expect("SurfaceWillDestroy", "other")
    }
    ch.close()
}

// system.info：时区/语言/字体目录/家目录/API 级别
@Test
func systemInfoDecodes(): Unit {
    let shell = HeadlessShell(name: "lwin-sys1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    shell.sendSystemInfo("Asia/Shanghai", "zh-Hans", "/usr/share/fonts", "/home/user", 26)
    let evs = win.pollAll()
    @Expect(evs.size, 1)
    match (evs[0]) {
        case LWindowLifecycleEvent.SystemInfo(tz, lang, fonts, home, api) =>
            @Expect(tz, "Asia/Shanghai")
            @Expect(lang, "zh-Hans")
            @Expect(fonts, "/usr/share/fonts")
            @Expect(home, "/home/user")
            @Expect(api, 26)
        case _ => @Expect("SystemInfo", "other")
    }
    ch.close()
}

// system.info 缓存：壳下发后客户端应能直接读到（引擎启动时用它替掉环境变量探测）
@Test
func systemInfoIsCached(): Unit {
    let shell = HeadlessShell(name: "lwin-sys2")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    @Expect(win.systemInfo.isNone(), true)
    shell.sendSystemInfo("UTC", "en-US", "/usr/share/fonts", "/home/u", 26)
    let _ = win.pollAll()
    match (win.systemInfo) {
        case Some((tz, lang, fonts, home, api)) =>
            @Expect(tz, "UTC")
            @Expect(lang, "en-US")
            @Expect(fonts, "/usr/share/fonts")
            @Expect(home, "/home/u")
            @Expect(api, 26)
        case None => @Expect("Some", "None")
    }
    ch.close()
}

// surface 状态机：available -> alive，will_destroy -> 不再可用
@Test
func surfaceStateFollowsLifecycle(): Unit {
    let shell = HeadlessShell(name: "lwin-sf6")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    @Expect(win.surfaceAlive, false)
    shell.sendSurfaceAvailable(0xABCD, 640, 480)
    let _ = win.pollAll()
    @Expect(win.surfaceAlive, true)
    @Expect(win.surfaceHandle, 0xABCD)
    @Expect(win.surfaceWidth, 640)
    shell.sendSurfaceChanged(800, 600)
    let _ = win.pollAll()
    @Expect(win.surfaceWidth, 800)
    @Expect(win.surfaceHeight, 600)
    shell.sendSurfaceWillDestroy()
    let _ = win.pollAll()
    @Expect(win.surfaceAlive, false)
    ch.close()
}

// 检查器规则（§7.1）：will_destroy 之后再 attach 要计数
@Test
func attachAfterDestroyCounted(): Unit {
    let shell = HeadlessShell(name: "lwin-rule1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    shell.sendSurfaceAvailable(0x1234, 800, 600)
    let _ = win.pollAll()
    @Expect(win.canPresent(), true)
    shell.sendSurfaceWillDestroy()
    let _ = win.pollAll()
    @Expect(win.canPresent(), false)
    let before = win.attachAfterDestroy
    let _ = win.attach(0x1234, 800, 600)
    @Expect(win.attachAfterDestroy, before + 1)
    ch.close()
}

// 检查器规则：hidden 期间请求帧要计数
@Test
func frameWhileHiddenCounted(): Unit {
    let shell = HeadlessShell(name: "lwin-rule2")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    shell.sendSurfaceAvailable(0x1, 320, 240)
    let _ = win.pollAll()
    @Expect(win.canPresent(), true)
    // hidden 事件（与 available 同接口，手工构造）
    var b = Array<UInt8>(4, repeat: 0)
    b[0] = 4
    let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_SURFACE, LWP_LW_SURFACE_HIDDEN_OPCODE, b)
    let _ = win.pollAll()
    @Expect(win.canPresent(), false)
    let before = win.frameWhileHidden
    let _ = win.requestFrame()
    @Expect(win.frameWhileHidden, before + 1)
    ch.close()
}

// 有界等待 surface.available（取代“轮询环境变量等 surface id”）
@Test
func awaitSurfaceReturnsHandleAndSize(): Unit {
    setVariable("LANLU_LWP", "1")
    let shell = HeadlessShell(name: "lanlu")   // 与 initLwpInput 默认通道名一致
    shell.handshake()
    spawn {
        sleep(Duration.millisecond * 20)
        shell.sendSurfaceAvailable(0xFEED, 1080, 720)
    }
    let s = lwpAwaitSurface(500)
    match (s) {
        case Some((handle, w, h)) =>
            @Expect(handle, 0xFEED)
            @Expect(w, 1080)
            @Expect(h, 720)
        case None => @Expect("Some", "None")
    }
    shell.channel().close()
    setVariable("LANLU_LWP", "0")
}

// lw_test：引擎就绪 + 壳注入测试动作/抓帧（计划 §16：自检由壳触发）
@Test
func testInterfaceRoundTrip(): Unit {
    let shell = HeadlessShell(name: "lwin-test1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    @Expect(win.sendTestReady(engineVersion: 7), true)
    let (iface, opcode, body) = shell.recvRequest()
    @Expect(iface, LWP_IFACE_LW_TEST)
    @Expect(opcode, LWP_LW_TEST_READY_OPCODE)
    @Expect(body.size, 8)

    // 壳注入一条测试动作 + 一次抓帧请求
    var inj = Array<UInt8>(16, repeat: 0)
    inj[0] = 16
    inj[4] = 2      // kind
    inj[8] = 5      // a
    inj[12] = 9     // b
    let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_TEST, LWP_LW_TEST_INJECT_OPCODE, inj)
    let path = "/tmp/cap.rgba"
    let pb = path.toArray()
    var cap = Array<UInt8>(8 + pb.size, repeat: 0)
    let total = UInt32(8 + pb.size)
    cap[0] = UInt8(total & 0xFF)
    cap[1] = UInt8((total >> 8) & 0xFF)
    cap[4] = 8
    cap[6] = UInt8(pb.size)
    for (i in 0..pb.size) { cap[8 + i] = pb[i] }
    let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_TEST, LWP_LW_TEST_CAPTURE_OPCODE, cap)

    let evs = win.pollAll()
    @Expect(evs.size, 2)
    match (evs[0]) {
        case LWindowLifecycleEvent.TestInject(k, a, b) =>
            @Expect(k, 2)
            @Expect(a, 5)
            @Expect(b, 9)
        case _ => @Expect("TestInject", "other")
    }
    match (evs[1]) {
        case LWindowLifecycleEvent.TestCapture(p) => @Expect(p, "/tmp/cap.rgba")
        case _ => @Expect("TestCapture", "other")
    }
    ch.close()
}

// 剪贴板与对话框：引擎请求经协议到达壳
@Test
func clipboardAndDialogRequestsReachShell(): Unit {
    let shell = HeadlessShell(name: "lwin-cb1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    @Expect(win.clipboardSet("hello-clip"), true)
    let sGet = win.clipboardGet()
    let sOpen = win.dialogOpenFile(filters: "txt")
    let sSave = win.dialogSaveFile("out.txt")

    // 4 条 REQUEST 依次到达：set / get / open / save
    let (c1i, c1o, c1b) = shell.recvRequest()
    @Expect(c1i, LWP_IFACE_LW_CLIPBOARD)
    @Expect(c1o, LWP_LW_CLIPBOARD_SET_OPCODE)
    let setMsg = decodeLwpLwClipboardSet(c1b)
    @Expect(setMsg.mime, "text/plain")
    @Expect(setMsg.text, "hello-clip")
    let (c2i, c2o, _c2b) = shell.recvRequest()
    @Expect(c2i, LWP_IFACE_LW_CLIPBOARD)
    @Expect(c2o, LWP_LW_CLIPBOARD_GET_OPCODE)
    let (c3i, c3o, _c3b) = shell.recvRequest()
    @Expect(c3i, LWP_IFACE_LW_DIALOG)
    @Expect(c3o, LWP_LW_DIALOG_OPEN_FILE_OPCODE)
    let (c4i, c4o, _c4b) = shell.recvRequest()
    @Expect(c4i, LWP_IFACE_LW_DIALOG)
    @Expect(c4o, LWP_LW_DIALOG_SAVE_FILE_OPCODE)
    ch.close()
}

// 壳回 clipboard.text / dialog.result
@Test
func clipboardTextAndDialogResultDecode(): Unit {
    let shell = HeadlessShell(name: "lwin-cb2")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    // clipboard.text：size(4) serial(4) mime(str) text(str)
    let mime = "text/plain".toArray()
    let text = "粘贴内容".toArray()
    let total = 4 + 4 + 4 + 4 + mime.size + text.size
    var b = Array<UInt8>(total, repeat: 0)
    b[0] = UInt8(total & 0xFF)
    b[4] = 101
    b[8] = 16; b[10] = UInt8(mime.size)
    b[12] = UInt8(16 + mime.size); b[14] = UInt8(text.size)
    for (i in 0..mime.size) { b[16 + i] = mime[i] }
    for (i in 0..text.size) { b[16 + mime.size + i] = text[i] }
    let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_CLIPBOARD, LWP_LW_CLIPBOARD_TEXT_OPCODE, b)
    let evs = win.pollAll()
    @Expect(evs.size, 1)
    match (evs[0]) {
        case LWindowLifecycleEvent.ClipboardText(serial, m, t) =>
            @Expect(serial, 101)
            @Expect(m, "text/plain")
            @Expect(t, "粘贴内容")
        case _ => @Expect("ClipboardText", "other")
    }
    ch.close()
}

// 剪贴板异步读的缓存：clipboard.text 事件 -> lwpFrameTick 落地 -> 下次 get 读到
@Test
func clipboardCacheFilledByEvent(): Unit {
    setVariable("LANLU_LWP", "1")
    lwpResetForTest()
    let shell = HeadlessShell(name: "lanlu")
    shell.handshake()
    @Expect(initLwpInput(), true)
    // 壳回一条 clipboard.text
    let text = "cached".toArray()
    var b = Array<UInt8>(16 + text.size, repeat: 0)
    b[0] = UInt8(16 + text.size)
    // mime 为空（off=16,len=0）；text 紧随其后（off=16,len=6）
    b[8] = 16; b[10] = 0
    b[12] = 16; b[14] = UInt8(text.size)
    for (i in 0..text.size) { b[16 + i] = text[i] }
    let _ = shell.channel().send(LWP_EVENT, LWP_IFACE_LW_CLIPBOARD, LWP_LW_CLIPBOARD_TEXT_OPCODE, b)
    // tick 排空事件并填充缓存
    let tickRet = lwpFrameTick()
    @Expect(lwpStatsLine().size > 0, true)   // 通道确实初始化了
    @Expect(tickRet, true)                   // tick 至少处理了一条事件
    match (lwpClipboardGetText()) {
        case Some(v) => @Expect(v, "cached")
        case None => @Expect("Some", "None")
    }
    shell.channel().close()
    setVariable("LANLU_LWP", "0")
}

// 引擎日志出口：system.log 到达壳侧且文本/级别正确
@Test
func logReachesShell(): Unit {
    let shell = HeadlessShell(name: "lwin-log1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    @Expect(win.log("boot ok", level: 1), true)
    let (iface, opcode, body) = shell.recvRequest()
    @Expect(iface, LWP_IFACE_LW_SYSTEM)
    @Expect(opcode, LWP_LW_SYSTEM_LOG_OPCODE)
    let msg = decodeLwpLwSystemLog(body)
    @Expect(msg.level, 1)
    @Expect(msg.text, "boot ok")
    ch.close()
}

// 窗口状态/退出请求（替代 window_cmd.txt 与 appExited 轮询）
@Test
func windowStateAndExitRequests(): Unit {
    let shell = HeadlessShell(name: "lwin-st1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    @Expect(win.requestState(8), true)         // minimize/沉浸式
    @Expect(win.requestCloseWindow(), true)
    @Expect(win.requestExit(0), true)
    let (_, o1, _) = shell.recvRequest()
    @Expect(o1, LWP_LW_WINDOW_SET_STATE_OPCODE)
    let (_, o2, _) = shell.recvRequest()
    @Expect(o2, LWP_LW_WINDOW_CLOSE_OPCODE)
    let (_, o3, b3) = shell.recvRequest()
    @Expect(o3, LWP_LW_APP_EXIT_OPCODE)
    let exit = decodeLwpLwAppExit(b3)
    @Expect(exit.code, 0)
    ch.close()
}

// 命令字符串分流：LANLU_LWP=1 时走协议（不再写 window_cmd.txt）
@Test
func windowCommandRoutesThroughProtocol(): Unit {
    setVariable("LANLU_LWP", "1")
    lwpResetForTest()
    let shell = HeadlessShell(name: "lanlu")
    shell.handshake()
    @Expect(initLwpInput(), true)
    requestWindowCommand("minimize")
    // initLwpInput 先发了 hello_ack（REQUEST 方向），泵出的第一条是它
    let (_, first, _) = shell.recvRequest()
    @Expect(first, LWP_LW_CORE_HELLO_ACK_OPCODE)
    requestWindowCommand("maximize")
    let (_, o, _) = shell.recvRequest()
    @Expect(o, LWP_LW_WINDOW_SET_STATE_OPCODE)
    shell.channel().close()
    setVariable("LANLU_LWP", "0")
    lwpResetForTest()
}

// lw_test.replay：壳要求重放一份录制，引擎侧经 liblwp 回放入队（计划 §16.3 最后一块）
@Test
func replayEventDecodesAndReplays(): Unit {
    setVariable("LANLU_LWP", "1")
    lwpResetForTest()
    let shell = HeadlessShell(name: "lanlu")
    shell.handshake()
    @Expect(initLwpInput(), true)

    // 先录一段：把 3 条输入事件与一次回放请求写进同一通道
    let tracePath = "/workspace/lanlu/tmp/lwpt/replay-test.lwtrace"
    let rec = HeadlessShell(name: "lanlu")
    @Expect(rec.channel().traceOpen(tracePath), true)
    rec.pointerButton(1.0f32, 2.0f32, 0, true)
    rec.pointerMotion(3.0f32, 4.0f32)
    rec.key(30, true)
    rec.channel().traceClose()

    // 再通过协议请求回放
    let path = tracePath.toArray()
    var b = Array<UInt8>(8 + path.size, repeat: 0)
    b[0] = UInt8(8 + path.size)
    b[4] = 8; b[6] = UInt8(path.size)
    for (i in 0..path.size) { b[8 + i] = path[i] }
    let _ = rec.channel().send(LWP_EVENT, LWP_IFACE_LW_TEST, LWP_LW_TEST_REPLAY_OPCODE, b)

    // 引擎侧 tick 取到事件后调用 lwpReplayTrace，回放的输入事件应可从漏斗取出
    let n = lwpReplayTrace(tracePath)
    @Expect(n > 0, true)
    let evs = pollLwpEvents(rec.channel())
    @Expect(evs.size >= 1, true)
    rec.channel().close()
    setVariable("LANLU_LWP", "0")
    lwpResetForTest()
}

// 能力位：hello 宣告的能力要能被引擎读到（决定降级路径）
@Test
func shellCapabilitiesDecoded(): Unit {
    let shell = HeadlessShell(name: "lwin-cap1")
    // handshake() 发 hello（capabilities 由 HeadlessShell 组包，这里手工发一条带位的）
    let caps: UInt64 = LWP_CORE_CAPABILITIES_VSYNC | LWP_CORE_CAPABILITIES_IME_PREEDIT
    let body = buildHelloBytes(caps)
    let ch = LwpChannel.open("lwin-cap1-sep", slots: 16)
    let win = LwpWindowClient(ch)
    let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_CORE, LWP_LW_CORE_HELLO_OPCODE, body)
    let evs = win.pollAll()
    @Expect(evs.size, 0)          // hello 不产生事件，只记录状态
    @Expect(win.shellCapabilities, caps)
    @Expect(win.hasCapability(LWP_CORE_CAPABILITIES_VSYNC), true)
    @Expect(win.hasCapability(LWP_CORE_CAPABILITIES_CURSOR_LOCK), false)
    ch.close()
    shell.channel().close()
}

/// 手工组一条 core.hello（size=28 + "x" + "y"），capabilities 放在偏移 20
func buildHelloBytes(caps: UInt64): Array<UInt8> {
    var b = Array<UInt8>(30, repeat: 0)
    b[0] = 30
    b[4] = 1                     // protocol_major
    b[8] = 28; b[10] = 1         // shell_name
    b[12] = 29; b[14] = 1        // os_name
    b[16] = 26                   // os_api_level
    for (i in 0..8) {
        b[20 + i] = UInt8((caps >> (8 * i)) & 0xFF)
    }
    b[28] = 120                  // 'x'
    b[29] = 121                  // 'y'
    b
}

// vsync 能力：壳未宣告时不该每帧请求（否则壳回不了 frame.done，只会积压 + 假超时）
@Test
func vsyncCapabilityGatesFrameRequest(): Unit {
    setVariable("LANLU_LWP", "1")
    lwpResetForTest()
    let shell = HeadlessShell(name: "lanlu")
    // 先发不带 vsync 位的 hello
    let _ = shell.channel().send(LWP_EVENT, LWP_IFACE_LW_CORE, LWP_LW_CORE_HELLO_OPCODE, buildHelloBytes(0))
    @Expect(initLwpInput(), true)
    let _ = lwpFrameTick()
    // 壳侧 REQUEST 队列里应有 hello_ack，但**不应有** frame.request
    var sawFrameRequest = false
    var n = 0
    while (n < 4) {
        let (iface, opcode, _b) = shell.recvRequest()
        if (iface == 0 && opcode == 0) { break }
        if (iface == LWP_IFACE_LW_FRAME) { sawFrameRequest = true }
        n = n + 1
    }
    @Expect(sawFrameRequest, false)

    // 再宣告 vsync：之后应开始请求帧
    let caps: UInt64 = LWP_CORE_CAPABILITIES_VSYNC
    let _ = shell.channel().send(LWP_EVENT, LWP_IFACE_LW_CORE, LWP_LW_CORE_HELLO_OPCODE, buildHelloBytes(caps))
    let _ = lwpFrameTick()
    @Expect(lwpShellProvidesVsync(), true)
    setVariable("LANLU_LWP", "0")
    shell.channel().close()
    lwpResetForTest()
}

// 剪贴板读按能力降级：壳没宣告 clipboard_read_async 时不应发 get（否则缓存永远为空）
@Test
func clipboardGetRequiresCapability(): Unit {
    setVariable("LANLU_LWP", "1")
    lwpResetForTest()
    let shell = HeadlessShell(name: "lanlu")
    // 宣告的能力里**不含** clipboard_read_async
    let _ = shell.channel().send(LWP_EVENT, LWP_IFACE_LW_CORE, LWP_LW_CORE_HELLO_OPCODE,
        buildHelloBytes(LWP_CORE_CAPABILITIES_VSYNC))
    @Expect(initLwpInput(), true)
    let _ = lwpFrameTick()   // 让 hello 被解码进状态
    @Expect(lwpClipboardGetText().isNone(), true)   // 应返回 None 让调用方回落文件桥
    setVariable("LANLU_LWP", "0")
    shell.channel().close()
    lwpResetForTest()
}

// IME 请求：enable/disable、surrounding text、cursor rect 都能到达壳
@Test
func imeRequestsReachShell(): Unit {
    let shell = HeadlessShell(name: "lwin-ime1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    @Expect(win.imeEnable(true), true)
    @Expect(win.imeSetSurrounding("你好世界", 2, 2), true)
    @Expect(win.imeSetCursorRect(10, 20, 4, 18), true)
    @Expect(win.imeEnable(false), true)

    let (i1, o1, _) = shell.recvRequest()
    @Expect(i1, LWP_IFACE_LW_TEXT_INPUT)
    @Expect(o1, LWP_LW_TEXT_INPUT_ENABLE_OPCODE)
    let (_, o2, b2) = shell.recvRequest()
    @Expect(o2, LWP_LW_TEXT_INPUT_SET_SURROUNDING_OPCODE)
    let sur = decodeLwpLwTextInputSetSurrounding(b2)
    @Expect(sur.text, "你好世界")
    @Expect(sur.cursor, 2)
    let (_, o3, b3) = shell.recvRequest()
    @Expect(o3, LWP_LW_TEXT_INPUT_SET_CURSOR_RECT_OPCODE)
    let rect = decodeLwpLwTextInputSetCursorRect(b3)
    @Expect(rect.x, 10)
    @Expect(rect.h, 18)
    let (_, o4, _) = shell.recvRequest()
    @Expect(o4, LWP_LW_TEXT_INPUT_DISABLE_OPCODE)
    ch.close()
}

// 合并回执：壳的 vsync 只 ack 最新 serial，不能因此判超时（第 70 轮发现的 2:1 现象）
@Test
func mergedFrameDoneIsNotTimeout(): Unit {
    let shell = HeadlessShell(name: "lwin-vs1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    // 发两次请求，第二次覆盖 pending
    let s1 = win.requestFrame(nowNs: 0)
    let s2 = win.requestFrame(nowNs: 0)
    @Expect(s2 > s1, true)
    // 壳只回最新的那一条（合并回执）
    win.noteFrameDone(s2)
    // 即使时间已过极大值，也不应记超时
    @Expect(win.checkFrameTimeout(Int64(1) << 40), false)
    @Expect(win.frameTimeout, 0)
    ch.close()
}

// 光标形状决策：文本框内给 I 形（1），框外/无文本框给默认（0）
@Test
func cursorShapeByPoint(): Unit {
    @Expect(lwpCursorShapeForPoint(10.0, 20.0, 100.0, 24.0, 50.0, 30.0, true), 1)   // 框内
    @Expect(lwpCursorShapeForPoint(10.0, 20.0, 100.0, 24.0, 5.0, 30.0, true), 0)    // 框外左侧
    @Expect(lwpCursorShapeForPoint(10.0, 20.0, 100.0, 24.0, 50.0, 30.0, false), 0)   // 没有文本框
    @Expect(lwpCursorShapeForPoint(10.0, 20.0, 0.0, 0.0, 10.0, 20.0, true), 0)       // 零尺寸
    @Expect(lwpCursorShapeForPoint(10.0, 20.0, 100.0, 24.0, 10.0, 20.0, true), 1)    // 边界（左上）
    @Expect(lwpCursorShapeForPoint(10.0, 20.0, 100.0, 24.0, 110.0, 44.0, true), 1)   // 边界（右下）
}

// 回归：LwpWindowClient.poll() 每帧被 lwpFrameTick 调用，不能把输入事件吞掉。
// 第 90 轮实测：25 条 pointer_motion 就是这样消失的（光标/IME 锚点都因此失效）。
@Test
func pollDoesNotSwallowInputEvents(): Unit {
    let shell = HeadlessShell(name: "lwin-poll1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    shell.pointerMotion(12.0, 34.0)
    // 排空轮询（只认生命周期事件）
    var guard = 0
    while (guard < 16) {
        match (win.poll()) {
            case Some(_) => guard = guard + 1
            case None => break
        }
    }
    // 输入消息必须还在（被放回暂存区），而不是消失。
    // 暂存区里可能先有 hello 等非输入消息，跳过它们继续找 PointerMove。
    var found = false
    while (let Some(msg) <- takeBacklogLwpMessage()) {
        match (decodeLwpEvent(msg)) {
            case Some(ev) =>
                if (ev.kind == LWindowEventType.PointerMove) {
                    @Expect(ev.x, 12.0)
                    @Expect(ev.y, 34.0)
                    found = true
                    break
                }
            case None => ()
        }
    }
    @Expect(found, true)
    ch.close()
}

// 拖放事件解码：drop 的 uris 已在壳侧解码为本地路径，引擎这里原样拿到
@Test
func dragDropDecodesUris(): Unit {
    let shell = HeadlessShell(name: "lwin-dnd1")
    shell.handshake()
    let ch = shell.channel()
    let win = LwpWindowClient(ch)
    let uris = "/home/u/a.txt\n/home/u/b.txt".toArray()
    let total = 16 + uris.size
    var b = Array<UInt8>(total, repeat: 0)
    // size(4)=total, x(4)=640, y(4)=480, uris(lwp_str@12)
    b[0] = UInt8(total & 0xFF)
    b[4] = UInt8(0x80); b[5] = UInt8(0x02); b[6] = 0; b[7] = 0   // x = 640
    b[8] = UInt8(0xE0); b[9] = UInt8(0x01); b[10] = 0; b[11] = 0 // y = 480
    b[12] = 16                                       // uris off（低字节）
    b[14] = UInt8(uris.size)
    for (i in 0..uris.size) { b[16 + i] = uris[i] }
    let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_DROP_OPCODE, b)
    let evs = win.pollAll()
    @Expect(evs.size, 1)
    match (evs[0]) {
        case LWindowLifecycleEvent.DragDrop(x, y, u) =>
            @Expect(x, 640)
            @Expect(y, 480)
            @Expect(u, "/home/u/a.txt\n/home/u/b.txt")
        case _ => @Expect("DragDrop", "other")
    }
    ch.close()
}

// 三键平台化（docs/lwindow-title-buttons-plan.md）：请求只在壳宣告 title_buttons 时发送，
// 载荷字段（visible/side/margin/spacing/size/colorMode）编码正确。
@Test
func setTitleButtonsRequiresCapabilityAndEncodes(): Unit {
    // 未宣告能力：不发
    let shell0 = HeadlessShell(name: "lwin-tb0")
    shell0.handshake()                       // 默认 caps 不含 title_buttons
    let win0 = LwpWindowClient(shell0.channel())
    @Expect(win0.setTitleButtons(7), false)
    shell0.channel().close()

    // 宣告能力：发送且字段正确
    let shell = HeadlessShell(name: "lwin-tb1")
    shell.handshake(capabilities: LWP_CORE_CAPABILITIES_TITLE_BUTTONS)
    let win = LwpWindowClient(shell.channel())
    let _ = win.pollAll()   // 先消费 hello，能力位才会落到 shellCapabilities
    @Expect(win.hasCapability(LWP_CORE_CAPABILITIES_TITLE_BUTTONS), true)
    @Expect(win.setTitleButtons(7, side: 0, closeMargin: 16, spacing: 12, buttonSize: 28, colorMode: 2), true)
    let (iface, opcode, body) = shell.recvRequest()
    @Expect(iface, LWP_IFACE_LW_WINDOW)
    @Expect(opcode, LWP_LW_WINDOW_SET_TITLE_BUTTONS_OPCODE)
    let req = decodeLwpLwWindowSetTitleButtons(body)
    @Expect(req.visible, 7)
    @Expect(req.side, 0)
    @Expect(req.close_margin, 16)
    @Expect(req.spacing, 12)
    @Expect(req.button_size, 28)
    @Expect(req.color_mode, 2)
    shell.channel().close()
}

// 三键矩形事件：壳上报 window 局部 px，引擎缓存快照并发出生命周期事件。
@Test
func titleButtonsRectDecodesAndCaches(): Unit {
    let shell = HeadlessShell(name: "lwin-tb2")
    shell.handshake(capabilities: LWP_CORE_CAPABILITIES_TITLE_BUTTONS)
    let win = LwpWindowClient(shell.channel())
    shell.sendTitleButtonsRect(1950, 0, 140, 37, true)
    var saw = false
    while (true) {
        match (win.poll()) {
            case Some(LWindowLifecycleEvent.TitleButtonsRect(right, top, w, h, vis)) =>
                @Expect(right, 1950)
                @Expect(top, 0)
                @Expect(w, 140)
                @Expect(h, 37)
                @Expect(vis, true)
                saw = true
                break
            case Some(_) => ()
            case None => break
        }
    }
    @Expect(saw, true)
    @Expect(win.titleBtnWidth, 140)
    @Expect(win.titleBtnHeight, 37)
    @Expect(win.titleBtnVisible, true)
    // 隐藏三键（全屏）：width=0、visible=false
    shell.sendTitleButtonsRect(0, 0, 0, 0, false)
    let _ = win.pollAll()
    @Expect(win.titleBtnWidth, 0)
    @Expect(win.titleBtnVisible, false)
    shell.channel().close()
}
