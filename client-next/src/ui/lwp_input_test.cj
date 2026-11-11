package lanlu_client_next.ui

// LWP 输入映射测试：协议事件 -> UiEvent 的唯一映射点（lwpEventToUi）。
// 壳侧发的字节在 packages/lplatform-ohos/selftest 已验证，这里验证引擎侧的翻译。

import lwindow.*
import lwindow
import lgui.{Key, UiEvent, MouseButton}

func uiEventName(ev: UiEvent): String {
    match (ev) {
        case UiEvent.MouseDown(_, _, _) => "down"
        case UiEvent.MouseMove(_, _) => "move"
        case UiEvent.MouseUp(_, _, _) => "up"
        case UiEvent.MouseWheel(_, _, _, _) => "wheel"
        case UiEvent.TextInput(_) => "text"
        case UiEvent.KeyDown(_, _) => "keydown"
        case UiEvent.KeyUp(_) => "keyup"
        case _ => "other"
    }
}

@Test
func pointerDownMapsToMouseDown(): Unit {
    let ev = LWindowEvent(LWindowEventType.PointerDown, 12.0f32, 34.0f32, 0)
    let ui = lwpEventToUi(ev)
    @Expect(uiEventName(ui), "down")
}

@Test
func pointerMoveAndUpMap(): Unit {
    @Expect(uiEventName(lwpEventToUi(LWindowEvent(LWindowEventType.PointerMove, 1.0f32, 2.0f32, 0))), "move")
    @Expect(uiEventName(lwpEventToUi(LWindowEvent(LWindowEventType.PointerUp, 1.0f32, 2.0f32, 0))), "up")
}

@Test
func axisMapsToWheel(): Unit {
    let ev = LWindowEvent(LWindowEventType.PointerAxis, 0.0f32, -3.0f32, 0)
    @Expect(uiEventName(lwpEventToUi(ev)), "wheel")
}

@Test
func textInputCarriesText(): Unit {
    let ev = LWindowEvent(LWindowEventType.TextInput, 0.0f32, 0.0f32, 0, text: "你好")
    match (lwpEventToUi(ev)) {
        case UiEvent.TextInput(t) => @Expect(t, "你好")
        case _ => @Expect("TextInput", "other")
    }
}

@Test
func keyMapsByName(): Unit {
    // evdev 28 = Enter；按下 -> KeyDown
    let down = LWindowEvent(LWindowEventType.Key, 0.0f32, 0.0f32, 28, pressed: true)
    match (lwpEventToUi(down)) {
        case UiEvent.KeyDown(k, _) => @Expect(k, Key.Enter)
        case _ => @Expect("KeyDown", "other")
    }
    let up = LWindowEvent(LWindowEventType.Key, 0.0f32, 0.0f32, 28, pressed: false)
    @Expect(uiEventName(lwpEventToUi(up)), "keyup")
}

@Test
func letterKeyMapsFromEvdev(): Unit {
    // evdev 16..25 = Q..P
    let ev = LWindowEvent(LWindowEventType.Key, 0.0f32, 0.0f32, 17, pressed: true)  // 'w'
    match (lwpEventToUi(ev)) {
        case UiEvent.KeyDown(k, _) => @Expect(k, Key.Letter(UInt8(119)))  // 'w'
        case _ => @Expect("KeyDown", "other")
    }
}

@Test
func unknownKindMapsToUnknown(): Unit {
    let ev = LWindowEvent(LWindowEventType.Unknown, 0.0f32, 0.0f32, 0)
    @Expect(uiEventName(lwpEventToUi(ev)), "other")
}
