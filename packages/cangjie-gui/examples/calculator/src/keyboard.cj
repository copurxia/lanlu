/*
 * 键盘输入映射：把文本输入与功能键翻译成 CalcKey，与鼠标点击共用同一套逻辑。
 * Enter 求值、Backspace 逐位删除，数字/运算符直接键入。
 */
package cui_calculator

import cui.{Key, UiEvent}

func handleCalculatorEvent(model: CalcModel, event: UiEvent): Bool {
    match (event) {
        case UiEvent.TextInput(text) => pressForText(model, text)
        case UiEvent.KeyDown(Key.Enter, _) =>
            press(model, CalcKey.Equals)
            true
        case UiEvent.KeyDown(Key.Backspace, _) =>
            deleteLast(model)
            true
        case _ => false
    }
}

func pressForText(model: CalcModel, text: String): Bool {
    match (keyForText(text)) {
        case Some(key) =>
            press(model, key)
            true
        case None => false
    }
}

func keyForText(text: String): ?CalcKey {
    match (text) {
        case "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" => Some(CalcKey.Digit(text))
        case "." => Some(CalcKey.Dot)
        case "+" => Some(CalcKey.Op(CalcOp.Add))
        case "-" => Some(CalcKey.Op(CalcOp.Subtract))
        case "*" | "x" | "X" => Some(CalcKey.Op(CalcOp.Multiply))
        case "/" => Some(CalcKey.Op(CalcOp.Divide))
        case "=" => Some(CalcKey.Equals)
        case "%" => Some(CalcKey.Percent)
        case "c" | "C" => Some(CalcKey.AllClear)
        case _ => None<CalcKey>
    }
}
