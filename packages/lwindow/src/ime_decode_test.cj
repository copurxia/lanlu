package lwindow

// 输入法协议解码（lw_input.key since=2 的文本/修饰键 + lw_text_input 的 preedit/commit/delete）。
// 假壳发送 -> liblwp -> decodeLwpEvent -> LWindowEvent，验证引擎侧看到的事件字段。

import lwp.*

@Test
func keyEventCarriesTextAndModifiers(): Unit {
    let shell = HeadlessShell(name: "lwin-ime1")
    shell.handshake()
    shell.keyText(30, true, "a")
    shell.keyText(30, false, "")
    // Shift+A：utf8 是大写，modifiers 带 LSHIFT
    shell.keyText(30, true, "A", modifiers: UInt16(1))
    let evs = pollLwpEvents(shell.channel())
    @Expect(evs.size, 3)
    @Expect(evs[0].kind, LWindowEventType.Key)
    @Expect(evs[0].key, 30)
    @Expect(evs[0].pressed, true)
    @Expect(evs[0].text, "a")
    @Expect(evs[0].modifiers, UInt16(0))
    @Expect(evs[1].text, "")
    @Expect(evs[2].text, "A")
    @Expect(evs[2].modifiers, UInt16(1))
    shell.channel().close()
}

@Test
func imeEventsDecode(): Unit {
    let shell = HeadlessShell(name: "lwin-ime2")
    shell.handshake()
    shell.preedit("nihao", 5)
    shell.commitString("你好")
    shell.deleteSurrounding(2, 1)
    let evs = pollLwpEvents(shell.channel())
    @Expect(evs.size, 3)
    @Expect(evs[0].kind, LWindowEventType.Preedit)
    @Expect(evs[0].text, "nihao")
    // 组合串内的光标字节偏移放在 key 字段
    @Expect(evs[0].key, 5)
    @Expect(evs[1].kind, LWindowEventType.TextInput)
    @Expect(evs[1].text, "你好")
    @Expect(evs[2].kind, LWindowEventType.DeleteSurrounding)
    @Expect(evs[2].key, 2)   // before（字符）
    @Expect(evs[2].x, 1.0f32) // after（字符）
    shell.channel().close()
}
