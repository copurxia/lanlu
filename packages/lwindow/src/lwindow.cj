package lwindow

import std.fs.{canonicalize, Path}

// Lanlu 平台适配层（对标 Chromium 的 ui/ozone）。
//
// 设计约束（用户明确要求）：
//   * 一切平台差异只能出现在本包内部（平台探测、后端实现）；
//   * 业务层（client-next）与 UI 框架（cui）只调用本包的跨平台 API；
//   * 新增平台 = 增加一个后端文件，不改业务代码。
//
// 当前收敛的内容：进程环境（HOME/XDG/openssl 路径）、字体配置、首次启动数据种子、
// 移植自检；后续窗口动作（最小化/关闭）、文件对话框、IME、剪贴板等继续迁入。

public enum LWindowPlatform {
    | Ohos
    | Desktop
}

// 平台探测：只在 lwindow 内部使用。判据是 OHOS 独有目录存在性（不依赖编译期宏，
// 便于同一份源码在桌面与鸿蒙上都能编译）。canonicalize 不读取文件内容，代价极低。
func detectPlatform(): LWindowPlatform {
    try {
        let _ = canonicalize(Path("/system/lib64/platformsdk"))
        return LWindowPlatform.Ohos
    } catch (_) {
        return LWindowPlatform.Desktop
    }
}

public let LWINDOW_PLATFORM: LWindowPlatform = detectPlatform()

// 平台初始化（initialize，避免与 Cangjie 构造函数关键字冲突）：设置路径/环境、字体配置、必要时投放首次启动数据。
// 必须在创建窗口之前调用；重复调用无副作用（内部幂等）。
public func initialize(): Unit {
    // 平台初始化失败不应阻断启动：退化为“未做平台准备”，由调用方继续跑。
    try {
        match (LWINDOW_PLATFORM) {
            case LWindowPlatform.Ohos => initPlatformOhos()
            case LWindowPlatform.Desktop => initPlatformDesktop()
        }
    } catch (e: Exception) {
        eprintln("[lwindow] platform init failed: ${e}")
    }
}

// 桌面后端：目前无需平台准备（SDL/系统默认路径即可）。
func initPlatformDesktop(): Unit {}
