/*
 * 计算器的状态转换逻辑：只操作 CalcModel，不涉及任何渲染。
 *
 * 每条输入路径都先复位错误态（ERROR 后按任意键都能继续输入），除法有除零保护，
 * 整数显示有量级保护，数字解析交给标准库。
 */
package cui_calculator

import std.convert.Parsable
import std.math.abs
import std.math.round
import std.math.sqrt

func press(model: CalcModel, key: CalcKey): Unit {
    match (key) {
        case CalcKey.AllClear => clear(model)
        case CalcKey.Digit(text) => appendDigit(model, text)
        case CalcKey.Dot => appendDot(model)
        case CalcKey.Op(op) => choose(model, op)
        case CalcKey.Equals => finish(model)
        case CalcKey.Negate => negate(model)
        case CalcKey.Percent => applyUnary(model, {value => formatValue(value / Limit.PERCENT)})
        case CalcKey.SquareRoot => squareRoot(model)
        case CalcKey.Square => applyUnary(model, {value => formatValue(value * value)})
        case CalcKey.Reciprocal => reciprocal(model)
        case CalcKey.Pi =>
            recoverFromError(model)
            model.display = formatValue(PI_VALUE)
            model.resetDisplay = true
    }
}

func clear(model: CalcModel): Unit {
    model.display = DisplayText.ZERO
    model.stored = 0.0
    model.pending = None
    model.resetDisplay = true
    model.error = false
}

/* ERROR 只冻结屏幕一帧交互；下一次任何输入都从干净状态重新开始。 */
func recoverFromError(model: CalcModel): Unit {
    if (model.error) {
        clear(model)
    }
}

func appendDigit(model: CalcModel, digit: String): Unit {
    recoverFromError(model)
    if (model.resetDisplay || model.display == DisplayText.ZERO) {
        model.display = digit
        model.resetDisplay = false
    } else if (model.display.size < Limit.DIGITS) {
        model.display = model.display + digit
    }
}

func appendDot(model: CalcModel): Unit {
    recoverFromError(model)
    if (model.resetDisplay) {
        model.display = "${DisplayText.ZERO}."
        model.resetDisplay = false
    } else if (!model.display.contains(".") && model.display.size < Limit.DIGITS) {
        model.display = model.display + "."
    }
}

/* 键盘 Backspace：逐位删除当前输入；显示内容只含 ASCII，按字节截断是安全的。 */
func deleteLast(model: CalcModel): Unit {
    if (model.error) {
        clear(model)
        return
    }
    if (model.resetDisplay) {
        return
    }
    if (model.display.size <= 1) {
        model.display = DisplayText.ZERO
        return
    }
    let shortened = model.display[0..model.display.size - 1]
    model.display = if (shortened == "-") {
        DisplayText.ZERO
    } else {
        shortened
    }
}

/* 一元函数共用骨架：复位错误 → 取当前值 → 写回格式化结果。 */
func applyUnary(model: CalcModel, transform: (Float64) -> String): Unit {
    recoverFromError(model)
    model.display = transform(currentValue(model))
    model.resetDisplay = true
}

/* 取负在位翻转符号，且不结束数字输入：键入 12 → ± → 3 得到 -123；对 0 取负保持原样。 */
func negate(model: CalcModel): Unit {
    recoverFromError(model)
    if (model.display == DisplayText.ZERO) {
        return
    }
    model.display = if (model.display.startsWith("-")) {
        model.display[1..model.display.size]
    } else {
        "-${model.display}"
    }
}

func squareRoot(model: CalcModel): Unit {
    recoverFromError(model)
    let value = currentValue(model)
    if (value < 0.0) {
        fail(model)
        return
    }
    model.display = formatValue(sqrt(value))
    model.resetDisplay = true
}

func reciprocal(model: CalcModel): Unit {
    recoverFromError(model)
    let value = currentValue(model)
    // 精确判零：极小但非零的除数是合法输入（IEEE 除法定义良好），用阈值会把它们误报成除零。
    if (value == 0.0) {
        fail(model)
        return
    }
    model.display = formatValue(1.0 / value)
    model.resetDisplay = true
}

func choose(model: CalcModel, op: CalcOp): Unit {
    recoverFromError(model)
    if (model.pending.isSome() && !model.resetDisplay) {
        finish(model)
        if (model.error) {
            return
        }
    } else {
        model.stored = currentValue(model)
    }
    model.pending = Some(op)
    model.resetDisplay = true
}

func finish(model: CalcModel): Unit {
    recoverFromError(model)
    let op = match (model.pending) {
        case Some(value) => value
        case None => return
    }
    let rhs = currentValue(model)
    var result = 0.0
    match (op) {
        case CalcOp.Add => result = model.stored + rhs
        case CalcOp.Subtract => result = model.stored - rhs
        case CalcOp.Multiply => result = model.stored * rhs
        case CalcOp.Divide =>
            if (rhs == 0.0) {
                fail(model)
                return
            }
            result = model.stored / rhs
    }
    model.stored = result
    model.display = formatValue(result)
    model.pending = None
    model.resetDisplay = true
}

func fail(model: CalcModel): Unit {
    model.display = DisplayText.ERROR
    model.error = true
    model.pending = None
    model.resetDisplay = true
}

func currentValue(model: CalcModel): Float64 {
    match (Float64.tryParse(model.display)) {
        case Some(value) => value
        case None => 0.0
    }
}

/* 接近整数的结果按整数显示；超出 Int64 精确范围的值保持浮点形式，避免转换溢出。 */
func formatValue(value: Float64): String {
    if (abs(value) < Limit.INTEGER_RANGE) {
        // 四舍五入而非截断：0.999…（如 1÷49×49）与 2.000…4（如 √2 的平方）要对称吸附。
        let rounded = Int64(round(value))
        if (abs(value - Float64(rounded)) < Limit.INTEGER_EPSILON) {
            return "${rounded}"
        }
    }
    "${value}"
}
