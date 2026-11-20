package cui.base

// P5：只剩纹理管线仍在用的少量 SDL surface 声明（其余已随实现删除）。
// 这些调用点会在纹理路径完全后端化后一并移除。

internal let SDL_PIXELFORMAT_RGBA32: UInt32 = 376840196

foreign {
    func SDL_CreateSurfaceFrom(width: Int32, height: Int32, format: UInt32, pixels: CPointer<Unit>,
        pitch: Int32): CPointer<Unit>
    func SDL_DestroySurface(surface: CPointer<Unit>): Unit
    func SDL_ConvertSurface(surface: CPointer<Unit>, format: UInt32): CPointer<Unit>
}
