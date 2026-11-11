package lwp

// LWP 协议解码测试（仓颉侧）：用「手写字节 → 解码 → 断言字段」验证生成代码与 C 侧布局一致。
// C 侧的静态断言见 packages/lwp/native/test_protocol.c；两边用同一份 IDL 偏移，互为交叉验证。

// 组装一条 lw_core.hello：size=28，字段偏移 4/6/8/12/16/20，字符串在尾部
func buildHello(): Array<UInt8> {
    var b = Array<UInt8>(36, repeat: 0)
    b[0] = 28  // size = 28（小端，其余字节 0）
    b[4] = 1   // protocol_major = 1
    b[6] = 0   // protocol_minor = 0
    b[8] = 28  // shell_name.off
    b[10] = 4  // shell_name.len
    b[12] = 32 // os_name.off
    b[14] = 4  // os_name.len
    b[16] = 26 // os_api_level
    // capabilities = VSYNC(8192) | IME_PREEDIT(64) = 8256 → 小端 u64
    b[20] = UInt8(8256 & 0xFF)
    b[21] = UInt8((8256 >> 8) & 0xFF)
    let shell = "ohos".toArray()
    let os = "ohos".toArray()
    for (i in 0..4) {
        b[28 + i] = shell[i]
        b[32 + i] = os[i]
    }
    b
}

@Test
func decodeHelloFields(): Unit {
    let msg = decodeLwpLwCoreHello(buildHello())
    @Expect(msg.protocol_major, 1)
    @Expect(msg.protocol_minor, 0)
    @Expect(msg.shell_name, "ohos")
    @Expect(msg.os_name, "ohos")
    @Expect(msg.os_api_level, 26)
    @Expect(msg.capabilities, 8256)
}

@Test
func decodeHelloCapabilitiesBits(): Unit {
    let msg = decodeLwpLwCoreHello(buildHello())
    @Expect((msg.capabilities & LWP_CORE_CAPABILITIES_VSYNC) != 0, true)
    @Expect((msg.capabilities & LWP_CORE_CAPABILITIES_IME_PREEDIT) != 0, true)
    @Expect((msg.capabilities & LWP_CORE_CAPABILITIES_CURSOR_LOCK) != 0, false)
}

@Test
func stringOutOfRangeIsEmpty(): Unit {
    // 越界字符串不能让解码器崩溃（协议检查器要求：坏消息不致命）
    var b = Array<UInt8>(28, repeat: 0)
    b[0] = 28
    b[8] = 200 // shell_name.off 越界
    b[10] = 8
    let msg = decodeLwpLwCoreHello(b)
    @Expect(msg.shell_name, "")
}

@Test
func sizesMatchIdl(): Unit {
    @Expect(LWP_LW_CORE_HELLO_SIZE, 28)
    @Expect(LWP_LW_CORE_HELLO_ACK_SIZE, 16)
    @Expect(LWP_LW_CORE_ERROR_SIZE, 12)
    @Expect(LWP_LW_CORE_LOG_SIZE, 13)
    @Expect(LWP_LW_CORE_PING_SIZE, 8)
    @Expect(LWP_LW_CORE_PONG_SIZE, 8)
}

@Test
func protocolVersionIsOne(): Unit {
    @Expect(LWP_PROTOCOL_MAJOR, 1)
    @Expect(LWP_IFACE_LW_CORE_VERSION, 1)
}

// 协议面完整性：13 个接口 / 47 条消息（IDL 扩容后必须同步这些断言，
// 否则“悄悄改了 ABI”不会被发现）
@Test
func interfaceIdsAreStable(): Unit {
    @Expect(LWP_IFACE_LW_CORE, 1)
    @Expect(LWP_IFACE_LW_INPUT, 2)
    @Expect(LWP_IFACE_LW_APP, 3)
    @Expect(LWP_IFACE_LW_WINDOW, 4)
    @Expect(LWP_IFACE_LW_SURFACE, 5)
    @Expect(LWP_IFACE_LW_FRAME, 6)
    @Expect(LWP_IFACE_LW_DISPLAY, 7)
    @Expect(LWP_IFACE_LW_SEAT, 8)
    @Expect(LWP_IFACE_LW_TEXT_INPUT, 9)
    @Expect(LWP_IFACE_LW_CLIPBOARD, 10)
    @Expect(LWP_IFACE_LW_DIALOG, 11)
    @Expect(LWP_IFACE_LW_SYSTEM, 12)
    @Expect(LWP_IFACE_LW_TEST, 13)
}

@Test
func windowMessageSizes(): Unit {
    @Expect(LWP_LW_WINDOW_CREATE_SIZE, 4 + 4 + 4 + 4 + 4)      // size + 3 标量 + string
    @Expect(LWP_LW_WINDOW_CONFIGURE_SIZE, 16)
    @Expect(LWP_LW_SURFACE_ATTACH_SIZE, 24)                    // size + u64 + 3×u32
    @Expect(LWP_LW_DISPLAY_INFO_SIZE, 28)                      // size + (w,h)u32 + scale f32 + refresh u32 + 2×inset u32
    @Expect(LWP_LW_APP_PAUSED_SIZE, 4)                         // 只有 size
}

@Test
func emptyMessageDecodes(): Unit {
    let body = Array<UInt8>(4, repeat: 0)
    let m = decodeLwpLwAppPaused(body)
    // 只有 size 字段，不应崩溃（无字段消息在协议里合法）
    @Expect(LWP_LW_APP_PAUSED_SIZE, 4)
    let _ = m
}
