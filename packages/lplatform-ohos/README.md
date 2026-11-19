# lplatform-ohos —— 鸿蒙壳（平台包）

计划：[docs/lwindow-platform-separation-plan.md](../../docs/lwindow-platform-separation-plan.md) §4.2、§9.1。

本包是**唯一允许出现 OHOS 平台代码的运行时位置**（另一个是 `lpack-ohos`，只做工程生成与打包）。
目标：NDK C API 能做的全部下沉到这里，ArkTS 只保留系统强制的薄壳（≤200 行）。

## 目录

```
shell/native/        C/C++ 壳，被 lpack-ohos 生成的 CMake 工程编译成 libmain.so
  shell_napi.cpp       NAPI 模块注册、引擎自启动、剪贴板桥、输入事件桥（→ M1 改为 LWP）
  input_filter.cpp     窗口级 鼠标/键盘/触摸 过滤器（→ M2 改为发 LWP 事件）
  CMakeLists.txt       链接 OHOS NDK 库与 lgpu 静态库
  types/libmain/       ArkTS 侧类型声明（Index.d.ts）
shell/arkts/         ArkTS 薄壳模板，构建时覆盖到生成的工程里
  entryability/EntryAbility.ets
  pages/Index.ets
deps/                鸿蒙原生依赖 shim 与交叉编译脚本（M0-3 从 packages/*/native-ohos 迁入）
selftest/            真机自检（M5 从 packages/portcheck 的 ohos_selftest* 迁入）
```

## 构建

由 `lpack-ohos` 驱动，不单独构建：

```
bash packages/lpack-ohos/tools/build-ohos.sh   # 内部：交叉编译引擎 → 本包壳 → lpack-ohos 生成工程 → hvigor → 签名
```

`build-ohos.sh` 会把 `shell/` 覆盖到 `lpack-ohos` 模板的暂存副本上（`packages/lpack-ohos/target/<app>/.hap-templates`），
因此**壳源码只有这一份**，模板里不再重复存放。

## 迁移状态（M0）

- [x] 壳源码从仓外 `.research-ohos/packages/ohos/templates_sdl3` 迁入本包
- [x] `sdl_main.c`（已不编译的死代码）不再迁入
- [ ] `deps/`：vips / rocksdb / libvlc / fontkit / lgpu 的 `native-ohos/` 迁入
- [ ] `selftest/`：`portcheck/ohos_selftest*.cj` 迁入并改为经 `lwp test` 接口驱动
- [ ] M1：文件桥（`input_events.txt` 等）改为 LWP 协议通道
