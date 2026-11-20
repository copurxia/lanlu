/*
 * 顶层事件处理：Ctrl 快捷键与拖放文件。
 * 只做“事件 -> 动作”的转发，具体行为全部委托给 file_actions / clipboard_actions。
 */
package cui_notepad

import cui.{DesktopApp, Key, Keyboard, UiEvent}

// SDL 把字母键统一上报为大写字母的 ASCII 码；用命名常量代替裸数字，
// 阅读时能直接对上“Ctrl+字母”的快捷键表。文件级快捷键在此处理；Ctrl+A/C/X/V
// 交由聚焦的编辑区自行处理（按选区复制/剪切/粘贴、全选），故不在此拦截。
let KEY_N: UInt8 = 78 // 字母 'N'：新建
let KEY_O: UInt8 = 79 // 字母 'O'：打开
let KEY_S: UInt8 = 83 // 字母 'S'：保存；加 Shift 为另存为

func handleNotepadEvent(
    event: UiEvent,
    model: NotepadModel,
    app: DesktopApp,
    documentPath: String
): Bool {
    match (event) {
        case UiEvent.KeyDown(Key.Letter(value), _) => handleShortcut(value, model, app, documentPath)
        case UiEvent.DropFile(path, _, _) =>
            loadDroppedFile(model, path)
            true
        case _ => false
    }
}

func handleShortcut(
    key: UInt8,
    model: NotepadModel,
    app: DesktopApp,
    documentPath: String
): Bool {
    let modifiers = Keyboard.modifiers()
    // 未按住 Ctrl/Command 时直接放行，让字母键继续输入正文。
    if (!modifiers.command) {
        return false
    }
    if (key == KEY_N) {
        newFile(model)
        return true
    }
    if (key == KEY_O) {
        openFile(model, app)
        return true
    }
    if (key == KEY_S) {
        if (modifiers.shift) {
            saveFileAs(model, app, documentPath)
        } else {
            saveCurrentFile(model, documentPath)
        }
        return true
    }
    // Ctrl+A/C/X/V 不作拦截，交由聚焦的 TextArea 以自身的选区与剪贴板逻辑处理。
    false
}
