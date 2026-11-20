package cui.base

// P5：窗口控制全部走 L 层（无 SDL 窗口）。
// 状态类设置（最小/最大尺寸、边框、置顶…）记录在对象里；
// 影响窗口管理器的操作（最小化/最大化/恢复/显示/隐藏）交给平台层命令通道。

// 由上层接到平台层（OHOS window API）：参数是命令名。
public var headlessWindowCommand: Option<(String) -> Unit> = None

private func dispatchWindowCommand(command: String): Unit {
    match (headlessWindowCommand) {
        case Some(handler) => handler(command)
        case None => ()
    }
}

extend SdlWindow {
    public func setPosition(x: Int32, y: Int32): Unit {
        // 位置由系统窗口管理器决定
    }

    public func position(): WindowPosition {
        WindowPosition(0, 0)
    }

    public func setMinimumSize(width: Int32, height: Int32): Unit {
    }

    public func setMaximumSize(width: Int32, height: Int32): Unit {
    }

    public func setBordered(bordered: Bool): Unit {
    }

    public func setIcon(iconPath: String): Unit {
        // P5：窗口图标由系统/ArkTS 侧处理
        ()}

    public func setResizable(resizable: Bool): Unit {
    }

    public func setAlwaysOnTop(onTop: Bool): Unit {
    }

    public func setOpacity(opacity: Float32): Unit {
    }

    public func show(): Unit {
        dispatchWindowCommand("show")
    }

    public func hide(): Unit {
        dispatchWindowCommand("hide")
    }

    public func raiseWindow(): Unit {
        dispatchWindowCommand("raise")
    }

    public func maximize(): Unit {
        dispatchWindowCommand("maximize")
    }

    public func minimize(): Unit {
        dispatchWindowCommand("minimize")
    }

    public func restore(): Unit {
        dispatchWindowCommand("restore")
    }

    public func setFullscreen(fullscreen: Bool): Unit {
        dispatchWindowCommand(if (fullscreen) { "fullscreen" } else { "unfullscreen" })
    }

    public func sync(): Unit {
    }

    public func flash(operation!: WindowFlash = WindowFlash.Briefly): Unit {
    }

    public func setRelativeMouseMode(enabled: Bool): Unit {
    }

    public func setDragRegions(regions: Array<(Int32, Int32, Int32, Int32)>): Unit {
        // 拖动区由 L 层窗口管理器负责（P5 后续接入 OHOS 窗口拖动）
    }

    public func clearDragRegion(): Unit {
    }

    public func setDragRegion(x: Int32, y: Int32, width: Int32, height: Int32): Unit {
    }
}
