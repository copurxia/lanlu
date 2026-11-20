package cui.base

import lbase.CuiException

import std.env.{getVariable, setVariable}

/*
 * streaming 纹理（SDL_TEXTUREACCESS_STREAMING + SDL_UpdateTexture）测试。
 * 无显示环境用 offscreen 视频驱动建窗（与 cui.desktop idle_wait_test 同一做法）。
 *
 * 注：原「纹理回读像素」用例依赖从未入库的 surfaceToRgbaArray 辅助函数（lgui 时代
 * 就无法编译），随 P6 的 SDL 读回路径退役一并移除；输入校验用例保留。
 */

private func ensureVideoDriver(): Unit {
    if (getVariable("SDL_VIDEODRIVER").isNone() && getVariable("WAYLAND_DISPLAY").isNone() &&
        getVariable("DISPLAY").isNone()) {
        setVariable("SDL_VIDEODRIVER", "offscreen")
    }
}

private func solidPixels(width: Int32, height: Int32, r: UInt8, g: UInt8, b: UInt8): Array<UInt8> {
    let total = Int64(width) * Int64(height)
    let pixels = Array<UInt8>(total * 4, repeat: 0u8)
    var i: Int64 = 0
    while (i < total) {
        pixels[i * 4] = r
        pixels[i * 4 + 1] = g
        pixels[i * 4 + 2] = b
        pixels[i * 4 + 3] = 255u8
        i++
    }
    pixels
}

@Test
func streamingRejectsBadInputs(): Unit {
    ensureVideoDriver()
    let window = SdlWindow(WindowSpec("streaming guard test", 32, 32))
    try {
        let renderer = window.renderer
        // 初始像素长度不符：创建即抛。
        var threw = false
        try {
            let _ = renderer.streamingTextureFromPixelsRgba(2, 2, Array<UInt8>(3, repeat: 0u8))
        } catch (_: CuiException) {
            threw = true
        }
        @Expect(threw)
        // 尺寸与纹理不符的更新：抛（防止 pitch 错位写花显存）。
        let texture = renderer.streamingTextureFromPixelsRgba(2, 2, solidPixels(2, 2, 1u8, 2u8, 3u8))
        try {
            threw = false
            try {
                renderer.updateStreamingTextureRgba(texture, 4, 4, solidPixels(4, 4, 0u8, 0u8, 0u8))
            } catch (_: CuiException) {
                threw = true
            }
            @Expect(threw)
            // 已关闭纹理的更新：抛。
            texture.close()
            threw = false
            try {
                renderer.updateStreamingTextureRgba(texture, 2, 2, solidPixels(2, 2, 0u8, 0u8, 0u8))
            } catch (_: CuiException) {
                threw = true
            }
            @Expect(threw)
        } finally {
            texture.close()
        }
    } finally {
        window.close()
    }
}
