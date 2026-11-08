package lanlu_client_platform

// client-next platform seam: UI/loop/renderer/paths behind a backend interface.
// Desktop backend wraps CangjieGUI(SDL); OHOS backend will use SDL3 (HarmonyOS port).
// Pure Cangjie (no cui/SDL types) so both backends can implement it.

public interface PlatformPaths {
    func filesDir(): String
    func cacheDir(): String
}

public interface Renderer {
    func beginFrame(): Unit
    func clear(r: Float32, g: Float32, b: Float32): Unit
    func present(): Unit
    func width(): Int32
    func height(): Int32
}

public interface Window {
    func size(): (Int32, Int32)
    func setTitle(title: String): Unit
    func setTextInputArea(x: Int32, y: Int32, w: Int32, h: Int32): Unit
}

public interface AppRuntime {
    func run(): Int32
    func requestWake(): Unit
}

public interface PlatformBackend {
    func name(): String
    func createWindow(width: Int32, height: Int32): Window
    func createRenderer(window: Window): Renderer
    func paths(): PlatformPaths
    func runtime(): AppRuntime
}

// Backend selection is compile-time (one backend per binary); see platform_select.cj in app.
public func backendName(b: PlatformBackend): String {
    return b.name()
}
