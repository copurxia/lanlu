package lwindow.backend

// backend.lwp（计划 §4.5）：生产路径唯一允许 import lgpu 的位置
// （portcheck 自检探针按 tools/deps-rules.toml 白名单直连 lgpu，不属于业务/平台层）。
//
// 职责：把「壳下发的 surface 句柄」翻译成渲染画布（lgpu.LgpuCanvas），对业务胶水
// 只暴露 lbase.Canvas 与少量命令式操作（resize/缩放/探针）。业务层因此不再出现
// 任何 lgpu 类型 —— 依赖白名单 client-next:forbidden=[lgui,lgpu,lwp] 由此达成。

import lbase.Canvas
import lgpu.{Font, LgpuCanvas, Surface, statsLine as lgpuStatsLine}
import lwindow.systemSansFontPath

// 最近一次创建的画布与字体（resize / 缩放更新 / 探针通道）。单窗口假设（与壳一致）。
var g_canvas: ?LgpuCanvas = None
var g_font: ?Font = None

/// 由壳的 surface 句柄创建渲染画布：fromSurfaceId → configure → 字体加载 → LgpuCanvas。
///
/// 失败（字体路径缺失）返回 None，调用方回落到各自的旧路径。成功返回的 Canvas 已按
/// `scale` 设置好逻辑→物理变换（几何图元走变换，文字按物理像素光栅化，见 lgpu 文字路径）。
public func createSurfaceCanvas(surfaceId: Int64, w: Int64, h: Int64, scale: Float32): ?Canvas {
    let surface = Surface.fromSurfaceId(surfaceId)
    surface.configure(w, h)
    match (systemSansFontPath()) {
        case Some(fontPath) =>
            let font = Font.load(fontPath)
            g_font = font
            let canvas = LgpuCanvas(surface, font)
            // 系统 UI 缩放：逻辑坐标 × scale = 物理像素。
            // 硬编码 1.0 时，PC 模式 190%/200% 缩放下内容只铺满左上角（第 117 轮真机修复）。
            canvas.scale = scale
            g_canvas = canvas
            canvas
        case None => None
    }
}

/// 壳尺寸变化：仅重配 swapchain（**不要**走 configure —— 重建 device/pipeline，
/// 真机 20 次 resize 压测第 13 轮后引擎线程卡死，第 53 轮）。
/// 返回 false = 画布尚未创建（调用方忽略本次）。
public func resizeShellCanvas(w: Int64, h: Int64): Bool {
    match (g_canvas) {
        case Some(c) =>
            c.surfaceRef().resize(w, h)
            true
        case None => false
    }
}

/// 壳上报缩放变化（window.created.scale）：更新画布 scale，下一帧起生效。
public func setShellCanvasScale(scale: Float32): Unit {
    match (g_canvas) {
        case Some(c) => c.scale = scale
        case None => ()
    }
}

/// 探针（LANLU_MAIN_PROBE_FILL=1）：首帧强制红屏，自检"壳 → 引擎 → 呈现"链路。
public func setShellCanvasForceClearRed(v: Bool): Unit {
    match (g_canvas) {
        case Some(c) => c.forceClearRed = v
        case None => ()
    }
}

/// 探针（LANLU_PROBE_LGPU=1）：真实字体度量 (ascent, descent, lineGap, upem)。
/// 文本垂直居中口径对账用；无字体返回 None。
public func shellFontMetrics(size: Float32): ?(Float32, Float32, Float32, Float32) {
    match (g_font) {
        case Some(f) => Some(f.metrics(size))
        case None => None
    }
}

/// 探针：lgpu 计数快照字符串（draws/uploads/frames 等累计值）。
public func shellStatsLine(): String {
    lgpuStatsLine()
}

/// 探针：文字测量缓存命中统计 (hits, misses, entries)；无画布返回 None。
public func shellCanvasMeasureStats(): ?(Int64, Int64, Int64) {
    match (g_canvas) {
        case Some(c) => Some(c.measureStats())
        case None => None
    }
}
