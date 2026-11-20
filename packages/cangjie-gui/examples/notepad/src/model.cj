/*
 * 记事本的共享状态：正文缓冲、光标/滚动位置、文件路径与状态栏提示。
 *
 * 行数/字节统计是 DerivedState —— 正文一变，统计随之刷新，视图直接读取，
 * 无需在每帧里手工重算，也不可能与文档内容脱节。
 */
package cui_notepad

import cui.{DerivedState, FileDialogRequest, State}

class NotepadModel {
    let body = State<String>("欢迎使用 CUI 记事本。\n中文与 English 均使用系统 UI 字体清晰显示。")
    /** 光标与选区锚点成对持有：任何外部改写光标的动作（载入、粘贴）必须同步移动锚点，否则残留锚点会形成幻影选区。 */
    let bodyCursor = State<Int64>(body.value.size)
    let bodyAnchor = State<Int64>(body.value.size)
    let bodyScroll = State<Float32>(0.0)
    let currentPath = State<String>("")
    let status = State<String>("就绪")
    let readOnly = State<Bool>(false)
    /**
     * “新建”确认条是否可见。用状态驱动的应用内确认条代替系统 MessageBox，
     * 因为同步弹窗会阻塞事件循环，让打开/保存对话框的帧内轮询停摆。
     */
    let confirmingNew = State<Bool>(false)
    let openDialog = State<?FileDialogRequest>(None<FileDialogRequest>)
    let saveDialog = State<?FileDialogRequest>(None<FileDialogRequest>)
    /** 状态栏统计行，由正文派生：行数、字节数与编码说明。 */
    let stats: DerivedState<String>

    init() {
        this.stats = this.body.map<String>({text => "| ${text.split("\n").size} 行 | ${text.size} 字节 | UTF-8"})
    }
}
