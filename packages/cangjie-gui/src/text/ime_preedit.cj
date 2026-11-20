package cui.text

/*
 * 输入法组合串（preedit）的显示层换算。
 *
 * 组合中的文本**不属于**输入框的值：真实的 text.value 只在 commit 时才变化。显示时把组合串
 * 插到光标处并按"下划线 + 下落光标"绘制；这样撤销栈、校验、提交都只看真实值，
 * 与 Chromium/Wayland text-input 的语义一致（组合态是输入法的私有状态）。
 */

/// 把组合串插到 caret 处的显示视图。
public struct PreeditView {
    /// 插入组合串后的显示串
    public let display: String
    /// 组合串内的光标在显示串里的字节偏移
    public let cursor: Int64
    /// 组合串字节长度（>0 表示正在组合）
    public let length: Int64

    public init(display: String, cursor: Int64, length: Int64) {
        this.display = display
        this.cursor = cursor
        this.length = length
    }
}

/// base 为已经过掩码换算的显示串，caret 是其中的字节偏移。
public func preeditView(base: String, caret: Int64, preedit: String, preeditCursor: Int64): PreeditView {
    if (preedit.isEmpty()) {
        return PreeditView(base, caret, 0)
    }
    let at = max(0, min(caret, base.size))
    let clip = max(0, min(preeditCursor, preedit.size))
    PreeditView(base[0..at] + preedit + base[at..base.size], at + clip, preedit.size)
}

/// 真实偏移 -> 显示串偏移（组合串插在 caret 处，其后的偏移整体右移）。
public func shiftForPreedit(offset: Int64, caret: Int64, preeditLen: Int64): Int64 {
    if (preeditLen <= 0 || offset <= caret) {
        offset
    } else {
        offset + preeditLen
    }
}
