# paint：画板

一个自由绘画应用，演示自定义 `Widget` 的完整写法、`CanvasWidget` 画布手势，以及
指针事件“消费还是放行”的边界决策，这是自绘控件最容易出错的地方。

## 演示要点

- 实现 `Widget` 接口四个方法（measure/layout/draw/handle）写出可复用的 `ColorSwatch` 色块
- `CanvasWidget` 的绘制回调与事件回调分工
- 画布手势的事件边界：`MouseUp` 为何必须区分“结束绘制”与“消费事件”
- `map` 派生的工具栏文本（“画笔 N px”“N 条笔迹”）
- `Slider` 双向驱动画笔粗细、系统十字光标的托管

## 文件结构

| 文件 | 职责 |
|---|---|
| [main.cj](src/main.cj) | 入口：窗口、最小尺寸、十字光标托管 |
| [state.cj](src/state.cj) | `Stroke` 线段、`PaintModel`（起笔/采样/收笔）与派生文本 |
| [canvas.cj](src/canvas.cj) | 画布渲染与手势事件策略 |
| [color_swatch.cj](src/color_swatch.cj) | 自定义 `Widget`：可选中色块 |
| [views.cj](src/views.cj) | 根布局与工具栏 |
| [theme.cj](src/theme.cj) | 调色板与主题 |

## 关键实现

### 事件边界：收笔与消费分离

事件按绘制层级自顶向下分发（后声明者先收到）。画布在工具栏之后声明，总是先拿到
`MouseUp`；若无条件消费，工具栏“清空”按钮（按下与松开两段手势）的松开半程会被吞掉，
按钮永远无法触发。正确策略是收笔不看坐标、消费必须判界：

```cangjie
case UiEvent.MouseUp(MouseButton.Left, x, y) =>
    // 收笔：笔迹拖出画布外再松开也要结束本次绘制
    let wasDrawing = model.endStroke()
    // 消费：只有属于本次绘制、或落在画布内的松开才归画布，其余放行
    if (wasDrawing || frame.contains(x, y)) {
        return true
    }
```

### 自定义 Widget

`ColorSwatch` 是应用自己实现 `Widget` 的最小完整样例：`measure` 返回固定方块尺寸、
`layout` 记录 frame、`draw` 画圆角色块与选中环、`handle` 在 `MouseDown` 命中时写回
共享的颜色状态。选中判定比较了 RGBA 四个通道。

### 派生的工具栏文本

画笔粗细与笔迹计数都是 `DerivedState`，滑块拖动、画布落笔后文本自动刷新：

```cangjie
let brushText: DerivedState<String>       // "画笔 5 px"
let strokeCountText: DerivedState<String> // "12 条笔迹"
```

## 运行

```powershell
cd examples/paint
cjpm run
```

支持视觉回归快照：

```powershell
cjpm run --run-args "--snapshot paint.bmp"
```
