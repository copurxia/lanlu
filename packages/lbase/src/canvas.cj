package lbase

// 渲染后端接口（L 层迁移用）。
//
// 目的：把视图代码对**具体后端**（现在还是 SDL，将来是 lgpu）的依赖收窄成一个接口。
// 视图只依赖 Canvas；`Renderer`（SDL 实现）和 `lgpu.LgpuCanvas`（wgpu 实现）都实现它。
//
// 说明：本接口暂时放在 sdl 包里（Color/Pen/Rect 也在这里），等 P5 删掉 sdl 包时
// 会整体搬到中立包；现在这样能零改动地让两边共存、逐步切换。

public interface Canvas {
    /// 开始一帧（清屏色）。
    func beginFrame(clear: Color): Unit

    /// 结束一帧并呈现。
    func present(): Unit

    /// 离屏抓帧：把当前帧写成原始 RGBA 文件；返回 >0 = w*1e6+h，<0 失败。
    func captureTo(path: String): Int32

    /// GPU 快照：把本帧已录制的图元渲染进后端纹理并以 id 注册（不读回 CPU）。
    /// (logicalW, logicalH) 是纹理的逻辑尺寸：source 矩形按逻辑坐标解释，与屏幕坐标一致。
    /// 返回物理像素尺寸；后端不支持时返回 None（调用方退回 captureTo 路径）。
    func snapshotTexture(_: Int64, _: Float32, _: Float32): ?(Int32, Int32) {
        None
    }

    /// 层断点：此后录制的图元整体画在此前所有图元（含纹理）之上。
    func layerMark(): Unit {}

    /// 丢弃本帧已录制的全部图元（全屏不透明遮罩覆盖下层时省掉 GPU 填充）。
    func discardRecorded(): Unit {}

    /// 单实例辉光环；后端不支持时返回 false，调用方退回多层描边。
    func glowRing(_: Float32, _: Float32, _: Float32, _: Float32, _: Float32, _: Float32, _: Color,
            _: Float32): Bool {
        false
    }

    /// 填充矩形。
    func fill(rect: Rect, color: Color): Unit

    /// 圆角矩形填充。
    func fillRoundedRect(rect: Rect, radius: Float32, color: Color): Unit

    /// 线性渐变填充（vertical=false 横向，true 纵向）。
    func fillRectGradient(rect: Rect, from: Color, to: Color, vertical: Bool): Unit

    /// 绘制带圆角裁剪的纹理（radius 为像素半径，0 = 普通矩形）。
    func drawTextureRounded(id: Int64, destination: Rect, source: ?Rect, radius: Float32, alpha: Float32): Unit

    /// 柔和边缘的圆角矩形填充。
    func fillRoundedRectSoft(rect: Rect, radius: Float32, color: Color, feather!: Float32): Unit

    /// 矩形描边。
    func strokeRect(rect: Rect, pen: Pen): Unit

    /// 圆角矩形描边。
    func strokeRoundedRect(rect: Rect, radius: Float32, pen: Pen): Unit

    /// 线段。
    func strokeLine(x1: Float32, y1: Float32, x2: Float32, y2: Float32, pen: Pen): Unit

    /// 1px 线段（color 版本）。
    func line(x1: Float32, y1: Float32, x2: Float32, y2: Float32, color: Color): Unit

    /// 实心圆。
    func fillCircle(cx: Float32, cy: Float32, radius: Float32, color: Color): Unit

    /// 圆描边。
    func strokeCircle(cx: Float32, cy: Float32, radius: Float32, pen: Pen, segments!: Int64): Unit

    /// 用后端纹理 id 绘制（替代后端路径；id 由 texturePixelsSink 注册）。
    func drawTexture(id: Int64, destination: Rect, source: ?Rect, alpha: Float32): Unit

    /// 上传/更新一张 RGBA8 纹理（替代后端持有纹素）。
    func uploadTexture(id: Int64, width: Int32, height: Int32, pixels: Array<UInt8>): Unit

    // 说明：后端**不再**提供"PNG 字节 → 纹理"的上传口。图片解码统一由 lcodec 负责
    // （设备：系统 ImageSource；桌面：系统 libvips），后端口径只有 RGBA 像素上传
    // (uploadTexture)，纹理尺寸因此始终来自真实解码结果。

    /// 释放一张后端纹理（R4：Texture.close 时调用，回收显存；后端负责幂等）。
    func releaseTexture(id: Int64): Unit

    /// 推入裁剪矩形（与当前裁剪求交）。
    func pushClip(rect: Rect): Unit

    /// 弹出最近一次裁剪。
    func popClip(): Unit

    /// 绘制文本，(x, y) 为文本行左上角。接口里不能带默认值（Cangjie 限制），
    /// 默认值由各实现声明。
    func text(text: String, x: Float32, y: Float32, color: Color, pointSize!: Float32): Unit

    /// 文本宽度（像素）。
    func textWidth(text: String, pointSize!: Float32): Float32

    /// 行高（像素）。
    func textHeight(pointSize!: Float32): Float32

    /// 在矩形内居中绘制文本。
    func textCenter(text: String, rect: Rect, color: Color, pointSize!: Float32): Unit
}
