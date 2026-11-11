# lplatform-wayland —— Wayland 壳（平台包）

计划：[docs/lwindow-platform-separation-plan.md](../../docs/lwindow-platform-separation-plan.md) §4.4、§8A、§9.3。

**状态：骨架（M0 建立，实现在 M1W 开始）。** 本包是桌面端唯一允许出现 Wayland/Linux 平台代码的运行时位置。

## 职责

宿主程序 `lanlu`：先建 LWP 通道并连接 Wayland、发出初始状态，再加载仓颉引擎：

```
main ─ lwp_open ── hello + 初始快照（display/window/surface/config/paths）
     ─ dlopen libcangjie-runtime.so
     ─ InitCJRuntime → LoadCJLibraryWithInit("liblanlu_engine.so")
     ─ 引擎线程 cj_app_main()
     ─ 主线程：winit 事件循环 + LWP 请求处理
```

引擎在 Windows 上不可用、macOS 不在范围内：**桌面只支持 Wayland 会话**（计划 §0）。

## 选型（计划 §9.3、§15.3）

窗口与输入复用 horizon 已 vendored 的 winit 0.31（`winit-wayland` 后端），不自己写
`wayland-client` 状态机；壳内只保留一个翻译层：

- `winit::WindowEvent` → LWP 事件（`seat.*`、`window.*`、`surface.*`、`frame.*`）
- LWP 请求 → `winit::Window` 方法（`drag_window`、`set_ime_cursor_area`、`pre_present_notify`…）

`third_party/` 的 winit 与 wgpu-hal 从 horizon 同步（`tools/sync-winit.sh`、`tools/sync-wgpu-hal.sh`），
不受平台隔离规则约束（计划 §2 原则 10）。

## 目录（M1W 落地）

```
src/main.rs      参数、lwp_open、加载引擎
src/app.rs       winit ApplicationHandler：唯一的协议 ↔ winit 翻译层
src/keys.rs      winit KeyEvent → seat.keyboard.key（KeyCode 与 LWP 一一对应）
src/ime.rs       winit Ime ↔ text_input
src/cursor.rs    主题光标；cursor-shape-v1 直接绑定（winit 未用时）
src/clipboard.rs arboard / wl-clipboard-rs
src/portal.rs    xdg-desktop-portal：FileChooser、OpenURI、Settings
src/system.rs    XDG 目录、LANG/LC_*、fontconfig
tests/           weston headless 下的协议一致性测试（计划 §16.5）
```

## 未决

- 容器内缺 Wayland 开发头文件：用 `wayland-sys` 的 `dlopen` 特性，编译不依赖系统头文件。
- xdg-desktop-portal 需要 D-Bus 客户端：离线缓存没有 `zbus`/`dbus`，M3W 前须联网 vendor 或 dlopen `libdbus-1.so.3`。
