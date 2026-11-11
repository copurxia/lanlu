package lwp

// 仓颉侧通道测试：验证 liblwp.so 的 FFI 绑定与协议解码联通。
// 需要先构建 liblwp.so（bash packages/lwp/native/build.sh），并设置 LWP_LIB_DIR。

@Test
func sendRecvRoundTrip(): Unit {
    let ch = LwpChannel.open("cj-test", slots: 32)
    // 与 C 侧核心一致：先握手，再发业务消息（检查器规则）
    ch.enableChecker(strict: true)
    let hello = buildCoreHelloBytes()
    @Expect(ch.send(LWP_EVENT, LWP_IFACE_LW_CORE, LWP_LW_CORE_HELLO_OPCODE, hello), 0)

    let got = match (ch.recv(LWP_EVENT)) {
        case Some(m) => m
        case None => LwpMessage(0, 0, 0, 0, Array<UInt8>(0, repeat: 0))
    }
    @Expect(got.iface, LWP_IFACE_LW_CORE)
    @Expect(got.opcode, LWP_LW_CORE_HELLO_OPCODE)
    @Expect(got.body.size, hello.size)

    // 解码生成的 hello 结构
    let decoded = decodeLwpLwCoreHello(got.body)
    @Expect(decoded.protocol_major, 1)
    @Expect(decoded.shell_name, "engine")
    @Expect(decoded.os_api_level, 26)
    ch.close()
}

@Test
func checkerBlocksBeforeHandshake(): Unit {
    let ch = LwpChannel.open("cj-checker", slots: 16)
    ch.enableChecker(strict: true)
    // 未握手就发非 core 消息 -> 被拒（-71 EPROTO）
    let rc = ch.send(LWP_EVENT, 9, 0, Array<UInt8>(0, repeat: 0))
    @Expect(rc, LWP_ERR_EPROTO)
    ch.close()
}

@Test
func emptyRecvReturnsNone(): Unit {
    let ch = LwpChannel.open("cj-empty", slots: 8)
    @Expect(ch.recv(LWP_EVENT).isNone(), true)
    ch.close()
}

@Test
func waitTimesOut(): Unit {
    let ch = LwpChannel.open("cj-wait", slots: 8)
    let t0 = LwpChannel.nowNs()
    @Expect(ch.wait(LWP_EVENT, 30), false)
    let dt = (LwpChannel.nowNs() - t0) / 1000000
    @Expect(dt >= 25 && dt < 500, true)
    ch.close()
}

/// 组装一条 core.hello（偏移与 IDL 一致：size=28；字段 4/6/8/12/16/20；字符串在尾部）
func buildCoreHelloBytes(): Array<UInt8> {
    let total = 28 + 6 + 5 // hello 头 + "engine" + "ohos"
    var b = Array<UInt8>(total, repeat: 0)
    b[0] = UInt8(28)
    b[4] = 1  // protocol_major
    b[6] = 0  // protocol_minor
    b[8] = 28 // shell_name.off
    b[10] = 6 // shell_name.len
    b[12] = 34 // os_name.off
    b[14] = 4  // os_name.len
    b[16] = 26 // os_api_level
    b[20] = UInt8(LWP_CORE_CAPABILITIES_VSYNC & 0xFF)
    b[21] = UInt8((LWP_CORE_CAPABILITIES_VSYNC >> 8) & 0xFF)
    let shell = "engine".toArray()
    for (i in 0..shell.size) {
        b[28 + i] = shell[i]
    }
    let os = "ohos".toArray()
    for (i in 0..os.size) {
        b[34 + i] = os[i]
    }
    b
}
