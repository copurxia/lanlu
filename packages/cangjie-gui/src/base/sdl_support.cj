package cui.base

import lbase.CuiException

import std.env.getVariable

// LANLU_PERF=1 启动分段打点（client-next 启动路径评估用，默认关闭零开销）：
// 窗口/渲染器/ShowWindow/字体初始化各段耗时以 [boot] 前缀打印，与 client-next
// main.cj 的 [boot] 累计毫秒行配套阅读。
internal let bootPerfEnabled = getVariable("LANLU_PERF") == Some("1")

/**
 * Throws `CuiException` when an SDL boolean result reports failure.
 */
public func ensureSdl(ok: Bool, api: String): Unit {
    if (!ok) {
        throw CuiException("${api} failed: ${lastSdlError()}")
    }
}

public func sdlVersion(): Int32 {
    // P5：不再查询 SDL 版本（已不依赖 SDL 运行时）
    0
}

public func sdlRevision(): String {
    // P5：不再查询 SDL 修订号
    "lgui"
}

public func lastSdlError(): String {
    // P5：SDL 错误查询已移除；剩余调用点都会自行带上下文
    "SDL error (legacy path)"
}

/**
 * Throws `CuiException` when renderer defaults cannot be applied after window creation.
 */
internal func configureRenderer(window: CPointer<Unit>, renderer: CPointer<Unit>, scale: Float32, vsync: Bool): Unit {
    if (!unsafe { SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND) }) {
        destroyCreatedResources(window, renderer)
        throw CuiException("SDL_SetRenderDrawBlendMode failed: ${lastSdlError()}")
    }
    if (!unsafe { SDL_SetRenderScale(renderer, scale, scale) }) {
        destroyCreatedResources(window, renderer)
        throw CuiException("SDL_SetRenderScale failed: ${lastSdlError()}")
    }
    // 1 = sync to every vertical blank; 0 = SDL_RENDERER_VSYNC_DISABLED (uncapped present).
    let vsyncMode = if (vsync) {
        Int32(1)
    } else {
        Int32(0)
    }
    let _ = unsafe { SDL_SetRenderVSync(renderer, vsyncMode) }
}

/**
 * Releases partially-created SDL resources before propagating a setup failure.
 */
internal func destroyCreatedResources(window: CPointer<Unit>, renderer: CPointer<Unit>): Unit {
    unsafe {
        if (renderer.isNotNull()) {
            SDL_DestroyRenderer(renderer)
        }
        if (window.isNotNull()) {
            SDL_DestroyWindow(window)
        }
        SDL_Quit()
    }
}

public func normalizedScale(scale: Float32): Float32 {
    if (scale <= 0.0) {
        1.0
    } else {
        scale
    }
}

internal func scaledDimension(value: Int32, scale: Float32): Int32 {
    Int32(Float32(value) * scale)
}
