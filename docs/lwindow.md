# lwindow：Lanlu 平台适配层（对标 Chromium `ui/ozone`）

## 为什么要有这一层

用户要求：**平台差异只能存在于平台适配层，业务代码里不写平台分支**。
Chromium 的做法是 `ui/views`（跨平台控件）+ `ui/ozone`（平台抽象）+ `ui/platform_impl/{x11,wayland,win,mac}`（具体实现）。
Lanlu 对应关系：

| Chromium | Lanlu | 内容 |
|---|---|---|
| `ui/views` | `packages/cangjie-gui`（cui） | 跨平台控件/布局/事件分发 |
| `ui/ozone` | **`packages/lwindow`** | 平台适配层：进程环境、路径、字体、窗口动作、文件对话框、IME、剪贴板 |
| `ui/platform_impl/ohos` | `packages/lwindow/src/ohos_*.cj` | OHOS 后端 |
| `…/linux` … | `lwindow/src/lwindow.cj` 内 `initPlatformDesktop` | 桌面后端 |
| `base/` 测试 | `packages/portcheck` | 移植自检（图片/网络/媒体/字幕） |

## 目录与职责

```
packages/lwindow/
  cjpm.toml                 静态库，无外部依赖（只用 std）
  src/lwindow.cj            公开 API + 平台探测 + 后端分发
  src/ohos_entry.cj         OHOS 后端：HOME/XDG/openssl 路径、fonts.conf、首次启动数据种子
  src/ohos_fontsconf.cj     最小 fonts.conf
  src/ohos_seed.cj          首次启动 KV 种子（构建期由 ohos/gen_seed_cj.py 生成）
packages/portcheck/
  src/portcheck.cj          公共入口：enabled() / runIfEnabled()
  src/ohos_selftest*.cj     图片(PNG/WebP)、HTTP(S)、媒体(mkv probe)、ASS 渲染自检
```

## 业务层看到的 API（当前）

```cangjie
// client-next/src/main.cj —— 无任何平台分支
@C
public func cj_app_main(): Int64 {
    lwindowInitialize()   // 平台环境准备（各后端实现不同）
    runIfEnabled()        // 移植自检（OHOS_SELFTEST=1 时执行）
    return runApp()
}

main(): Int64 { lwindowInitialize(); runIfEnabled(); return runApp() }
```

## 平台探测

`detectPlatform()` 只在本包内使用：`canonicalize("/system/lib64/platformsdk")` 成功即 OHOS，
否则桌面。**不用编译期宏**，同一份源码在两端都能编译；探测代价是一次路径解析。
`initialize()` 全程 try/catch —— 平台准备失败只降级，不阻断启动（真机踩过 FSException 崩溃）。

## 迁移清单（本轮完成 / 待续）

- ✅ 进程环境（HOME/XDG/openssl 动态库路径）、fonts.conf、首次启动种子
- ✅ 移植自检（从业务层 `src/ohos_*.cj` 全部移出，业务 `src/` 已无平台文件）
- ✅ **窗口几何/缩放策略**：`preferredWindowGeometry()`（contentScale + 可用区钳制 + 最小 960×640）
- ✅ **渲染驱动优先级**：`prepareRendererHints()`（Linux 桌面 vulkan→opengl 回退；Win/mac 交给 SDL 内置）
- ✅ **桌面集成**：`prepareDesktopIntegration()`（Wayland libdecor 插件目录）
- ✅ **系统字体回退**：`systemSansFontPath()`（无 fontconfig 平台用系统字体）
- ⏳ 窗口动作（最小化/关闭/退出）：平台实现已在 ArkTS/C++ 壳内，cui 走 SDL 事件；后续把“请求→动作”统一成 lwindow API
- ⏳ 文件对话框（open/save/folder）、IME 文本输入桥、剪贴板
- ⏳ 图标设置（当前业务层调用 `Surface.loadPngFromMemory` + `setIcon`）


## 约束

1. 业务层与 cui 不得引用带平台前缀的实现（`ohos_`/`win_`/`mac_`）。
2. 平台探测与后端分发只能出现在 `packages/lwindow` 内。
3. 新增平台 = 新增后端文件 + 在 `detectPlatform`/`initialize` 加一个分支，**不改业务代码**。
