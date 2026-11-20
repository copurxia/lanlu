package cui.text

import lbase.{Rect}
import cui.base.{Key, Renderer, UiEvent}
import cui.core.{State, Theme, UiContext}

private func maskTestContext(): UiContext {
    UiContext(Renderer.headless(), Theme.light())
}

// 掩码显示串：每个字素替换为一个 "•"，ASCII 与中文（多字节字素）均按字素一一对应。
@Test
func maskedDisplayTextReplacesEveryGrapheme(): Unit {
    @Expect(maskedDisplayText(""), "")
    @Expect(maskedDisplayText("abc"), "•••")
    // "密码ab" 共 4 个字素（中文各 3 字节），显示串为 4 个掩码符。
    @Expect(maskedDisplayText("密码ab"), "••••")
    @Expect(maskedDisplayText("密码ab").size, 4 * TEXT_MASK_RUNE.size)
}

// 真实值字节偏移与掩码显示串字节偏移可以双向换算，且都落在字素边界上。
@Test
func maskedOffsetMappingRoundTrips(): Unit {
    let text = "密码ab" // 字节边界：0, 3, 6, 7, 8
    @Expect(maskedDisplayOffset(text, 0), 0)
    @Expect(maskedDisplayOffset(text, 6), 2 * TEXT_MASK_RUNE.size)
    @Expect(maskedDisplayOffset(text, 8), 4 * TEXT_MASK_RUNE.size)

    @Expect(maskedSourceOffset(text, 0), 0)
    @Expect(maskedSourceOffset(text, 2 * TEXT_MASK_RUNE.size), 6)
    @Expect(maskedSourceOffset(text, 4 * TEXT_MASK_RUNE.size), 8)
}

// 掩码模式下编辑仍作用于真实值：键入、退格修改绑定的真实文本，光标停在真实字节偏移。
@Test
func maskedTextFieldEditsRealValue(): Unit {
    let ctx = maskTestContext()
    let body = State<String>("")
    let field = TextField(body, key: "m", masked: true)
    field.layout(ctx, Rect(0.0, 0.0, 200.0, 32.0))
    ctx.focus("m")

    let _ = field.handle(ctx, UiEvent.TextInput("密"))
    let _ = field.handle(ctx, UiEvent.TextInput("a"))
    @Expect(body.value, "密a") // 真实值保持明文，掩码只发生在显示层

    let _ = field.handle(ctx, UiEvent.KeyDown(Key.Backspace, false))
    @Expect(body.value, "密")
    // 三次编辑帧时间相同、合并为一个撤销组，一次撤销全部回退——撤销同样作用于真实值。
    field.undo()
    @Expect(body.value, "")
}
