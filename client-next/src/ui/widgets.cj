package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*

// 点击传感器：透明、自身不占尺寸，layout 时记录父容器（ZStack）下发的整个矩形，
// 左键 MouseUp 命中该矩形时触发 onClick 并消费事件。
// 应用层自定义 Widget：实现 measure/layout/draw/handle 并在构造时 emit(this)
// （协议见 api-reference §2，写法参照 examples/explorer 的 EntryRow）。
class ClickSensor <: Widget {
    private let onClick: () -> Unit
    private var bounds = Rect.zero()

    public init(onClick: () -> Unit) {
        this.onClick = onClick
        emit(this)
    }

    // 不参与内容测量：传感器不撑大布局，区域大小完全由叠在上层的内容决定。
    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        bounds = rect
    }

    public func draw(_: UiContext): Unit {} // 全透明，只负责事件

    public func handle(_: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (bounds.contains(x, y)) {
                    onClick()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 可点击区域：框架没有通用 onClick 修饰器；cui.core 的 buildChild 是模块内部助手
// （未对应用导出，cui 伞包只重导出 emit），应用层自定义 Widget 无法包裹 builder 子树，
// 因此以 ZStack 叠层代替包裹——底层传感器随 ZStack 拉伸充满整个区域，内容绘制在上层；
// 事件自顶向下分发，内容未消费的左键抬起最终落到传感器触发 onClick。
public class ClickArea {
    public init(onClick!: () -> Unit, body!: () -> Unit) {
        ZStack {
            ClickSensor(onClick)
            body()
        }.alignment(Alignment.TopLeading)
    }
}

// 远程图片：三态（占位/错误可点击重试/成品）。key 形如 asset:42、page:arc:path。
// 首次构建（状态 ""）时经 model.requestImage 发起加载（并发上限由 model 保证）。
public func remoteImage(model: AppModel, key: String, url: String, w: Length, h: Length): Unit {
    let st = model.imageState(key)
    if (st.value == "") {
        model.requestImage(key, url)
        Panel { Label("…").muted() }.width(w).height(h)
    } else if (st.value == "loading") {
        Panel { Label("加载中…").muted() }.width(w).height(h)
    } else if (st.value == "error") {
        ClickArea(onClick: {=> model.retryImage(key, url)}) {
            Panel { Label("加载失败，点击重试").muted() }.width(w).height(h)
        }
    } else {
        // 状态为 "ready"：像素已 stage 进 cui 像素纹理缓存，PixelImageView 首帧惰性建纹理。
        // 封面用 Cover 裁满卡片（对齐 C2 之前 ImageView 的行为）；width/height 为首选尺寸。
        PixelImageView(key, w, h, fit: ImageFit.Cover)
    }
}
