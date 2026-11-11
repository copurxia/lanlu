# ffi-call 探针：引擎（仓颉 dylib）调壳（C）导出符号

计划 [docs/lwindow-platform-separation-plan.md](../../../docs/lwindow-platform-separation-plan.md) §10 M0-4：

> 复现并定位历史 FFI 崩溃：最小用例验证“引擎调用壳导出的 C 函数”在 (a) lgpu 只链接一份、
> (b) 引擎不在构造函数里自启动 时是否稳定。结论写回 [l-layer.md](../../../docs/l-layer.md)。

历史现象见 [l-layer.md](../../../docs/l-layer.md) 与 commit `d722178c` / `03461092`：
“ArkTS onTouch → napi pushInput → C++ 环形缓冲 → 仓颉 `lanlu_poll_input`”与
“引擎 → libmain 的 FFI”两次尝试都 SIGSEGV/SIGABRT，之后改用文件桥。

## 组成

| 文件 | 角色 |
|---|---|
| `shell.c` | 最小“壳”：导出 `lwp_probe`、`lwp_spawn_foreign`（后者在新线程里回调引擎的 `@C` 符号） |
| `shell_ctor.c` | 变体：在**构造函数里同步**启动引擎 |
| `shell_ctor2.c` | 变体：构造函数只起线程，**稍后**再启动引擎（≈ 现在 `lanlu_autostart_engine`） |
| `engine.cj` | 最小“引擎”：`@C cj_app_main` 调壳的 `lwp_probe`；导出 `@C cj_foreign_entry` 供外部线程回调 |
| `loader.c` | 最小“宿主”：`InitCJRuntime` → `LoadCJLibraryWithInit` → `cj_app_main` |
| `run.sh` | 构建三个变体并依次运行 |

## 运行

```
bash tools/probes/ffi-call/run.sh
```

需要 host 仓颉工具链（默认 `/workspace/.cjv/toolchains/sts-1.2.0`，`CJV_HOST_TOOLCHAIN` 可覆盖）与系统 `cc`。

## 变体与预期

| mode | 壳何时对引擎可见 | 预期 |
|---|---|---|
| `shell-first-g` | `dlopen(RTLD_GLOBAL)` 在加载引擎**之前** | 成功：`lwp_probe(6)=43`，外部线程回调返回 63 |
| `engine-first` | 加载引擎之后才 `dlopen(RTLD_GLOBAL)` | `LoadCJLibraryWithInit` 返回 -1；随后 `dlopen(RTLD_LAZY)` **仍返回 ok 且 `cj_app_main` 有返回值（垃圾值）**，引擎输出丢失，退出码 0 —— 静默错误 |
| `shell-local` | `dlopen(RTLD_LOCAL)` | 引擎永远解析不到符号：加载失败，退出码 1 |
| `ctor-autostart` | 壳的构造函数里**同步**启动 | 失败：`undefined symbol`（此时壳自身的符号还没进入全局作用域） |
| `ctor-deferred` | 构造起线程，稍后启动 | 成功，但依赖“壳的 dlopen 已完成”这一隐含时序 |

## 结论摘要

见 [l-layer.md](../../../docs/l-layer.md) 的「M0-4 最小用例结论」一节。要点：

1. 壳必须以 `RTLD_GLOBAL` 加载，且**在引擎加载之前**完成。
2. 在壳的构造函数里同步启动引擎一定失败；异步启动能工作但时序不确定。
3. 失败是静默的（`dlopen` 返回 ok、有“返回值”、退出码 0），所以不能用链接成功/退出码判断，
   必须用**显式握手**（引擎回报 hello_ack）确认链路可用 —— 这正是 LWP 的设计前提。
