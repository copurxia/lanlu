package cui.base

// 仅剩少量窗口相关 FFI 声明（P5 收尾中；SDL 窗口创建已移除）。

foreign {
    func SDL_DestroyWindow(window: CPointer<Unit>): Unit
}
