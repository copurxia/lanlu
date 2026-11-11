# LWP 迁移交接状态（2026-11-11 更新）

**验收报告：[lwp-acceptance-report.md](lwp-acceptance-report.md)**（2026-11-11，含缺口清单）
**验证纪律：[lwp-verification-discipline.md](lwp-verification-discipline.md)**（9 条硬规则，新人先读这个）
**API 清单：[lwp-platform-api.md](lwp-platform-api.md)**（哪些 API 被引擎用/仅测试用/已无引用）
**已知限制：[lwp-known-limitations.md](lwp-known-limitations.md)**（代码里真实存在的限制与刻意留白）
**消息覆盖：[lwp-message-coverage.md](lwp-message-coverage.md)**（64 条消息的覆盖与**决策表**：哪些预留、触发条件是什么）
计划：[lwindow-platform-separation-plan.md](lwindow-platform-separation-plan.md)
逐轮记录：[lwindow-plan-progress.md](lwindow-plan-progress.md)
新计划：[lwindow-title-buttons-plan.md](lwindow-title-buttons-plan.md)（三键 min/max/close 从业务层移除、统合到平台层）
**状态（2026-11-11 晚）**：P0–P5 全部完成并真机验证 —— 协议 64 条（`set_title_buttons`/`title_buttons_rect`/能力位）、
引擎编解码 + 42 项 lwindow 测试、OHOS 壳（配置应用 + vp2px 上报 + `windowWillClose`→close_request）、
业务层去三键（`selfDrawn=false`）。真机证据：`title buttons cfg applied visible=0x7` + `lwp title buttons 256x70px`
+ `ui title buttons width=134.7vp selfDrawn=false`；一条命令复验：
`bash packages/lpack-ohos/tools/verify-title-buttons.sh`（PASS）。剩余仅 P6 人工目视。
M6 手册：[m6-deletion-checklist.md](m6-deletion-checklist.md)

## 接手第一天该做什么（清单）

按顺序做，每一步都有可验证的输出。

1. **读这三份**（约 20 分钟）：本文件 → `lwp-acceptance-report.md`（现状与缺口）
   → `lwp-verification-discipline.md`（10 条踩坑规则，能帮你少走我走过的弯路）。
2. **跑一遍守卫与测试**（约 5 分钟，全部应 PASS）：
   ```bash
   bash tools/check-no-file-bridge.sh && python3 tools/check-deps.py \
     && python3 tools/check-platform-isolation.py && python3 tools/check-docs-consistency.py \
     && bash tools/check-layering.sh && bash tools/check-no-sdl.sh \
     && python3 tools/lwp-gen.py --check && python3 tools/lwp-gen.py --check-abi \
     && bash packages/lwp/test.sh \
     && bash packages/lplatform-ohos/selftest/run-tests.sh \
     && bash packages/lpack-ohos/tools/build-ohos.sh --self-check \
     && bash packages/lpack-linux/tools/build-deb.sh --self-test
   ```
3. **构建 + 装机 + 冒烟**（约 3 分钟）：`build-ohos.sh` → `sign-hap.sh` → `hdc install`
   → `aa start` → 用 `tools/ohos-input-probe.sh 690 21` 点搜索框。
   看到 hilog 里 `cursor shape` / `ime cursor` / `frames=` 三条，说明输入/光标/帧提交都活着。
4. **确认你要做什么**：看 `lwp-acceptance-report.md` §4 的缺口表与
   `lwp-message-coverage.md` 的决策表 —— **剩下的事都需要外部条件**（产品决策/桌面环境/设备人工操作）。
5. **改东西之前**先看 `lwp-platform-api.md`（哪些 API 真被引擎用）与
   `lwp-known-limitations.md`（哪些是刻意留白，别当成 bug 修）。

> 快照：`/workspace/lanlu/tmp/snapshots/final-107-1020.tgz`（源码 + 文档，903MB）。

## 常见任务导航（新接手先看这里）

每条都是**实际走过一遍的流程**，命令可直接复制。

### 改/加一条协议消息
1. 改 `packages/lwp/protocol/*.toml`：**追加**在对应 interface 段的末尾（插在中间会平移 opcode）；
2. `python3 tools/lwp-gen.py` 重新生成头文件/Cangjie/ABI；
3. `python3 tools/lwp-gen.py --check-abi` 必须 PASS（破坏性变更会被拦下）；
4. 引擎侧：`packages/lwp/src/lwp_encode.cj` 加编码 + `packages/lwindow/src/window_client.cj` 加方法；
5. 壳侧：`lplatform-ohos/shell/native/lwp_window.cpp` 的泵里加解析分支；
6. 测试：`bash packages/lwp/test.sh`、`cd packages/lwindow && cjpm test`、Wayland 侧 `cargo test`。

### 加一个壳能力（比如新输入事件）
- 能力位在 `packages/lwp/protocol/core.toml` 的 `capabilities` 表；壳在 hello 里置位
  （OHOS：`lwp_client.cpp` 的 `h->capabilities`；Wayland：`shell.rs` 的 `caps`）；
- **只有真实现了才置位** —— 引擎靠它走降级路径（见 §"已知限制"）。

### 真机验证 / 看日志
```bash
bash packages/lpack-ohos/tools/build-ohos.sh          # 构建
bash packages/lpack-ohos/tools/sign-hap.sh            # 签名
hdc install -r client-next/build/ohos/target/ohos/hap/entry/build/default/outputs/default/entry-default-signed.hap
bash tools/ohos-input-probe.sh 690 21                 # 点搜索框+移动（自动换算窗口偏移）
```
- 协议取证：启动时加 `--ps lanlu.env.LANLU_LWP_TRACE /data/storage/el2/base/files/x.lwtrace`，
  再 `hdc file recv` + `python3 tools/lwtrace.py stats|dump|verify`；
- 引擎打点：`--ps lanlu.env.LANLU_PROBE_LGPU 1`，读
  `/data/app/el2/100/base/com.example.cmakehap/files/probe_trace.txt`；
- **hilog 里的 C 侧 `LOGI_LWP` 不可靠**，判断"有没有执行"只认 trace 与 ArkTS 的 `console.info`。

### 跑测试与守卫
见下面「守卫与测试」一节；`lwindow` 的宿主测试需要 `LWP_LIB_DIR` 等环境变量（同节）。

### 为什么 Wayland 壳不用 winit
计划 §M3W 的"实现偏离"：要精确控制 xdg-shell 请求顺序/configure-ack 时序，
且假合成器测试要能逐字节断言 wire 请求 —— winit 把这两点都藏起来了。

### 崩溃/异常怎么查
1. 先看 `.lwtrace`（最后一帧前后各有什么消息）；
2. 再看 `probe_trace.txt`（引擎侧打点，含 `lwp stats` / `violations`）；
3. 真机上区分"**冻结**"和"**死锁**"：`pidof` + CPU 占用，冻结（0%）通常是被系统挂起；
4. 复查 `docs/lwp-verification-discipline.md` 第 2 条：先做"已知会成功"的正对照，再怀疑产品。

### 接入一个新平台（比如 Windows）
需要实现两件事：① `liblwp` 可加载（通道库是跨平台的 C）；② 一个壳主循环：
连窗口系统 → 发 `hello` → 处理 `window.create`/`surface.*`/输入 → 回 `frame.done`。
参考实现：`packages/lplatform-wayland/src/shell.rs`（协议面最全）。
打包脚本参照 `packages/lpack-linux/tools/build-deb.sh`（带 `--self-test`）。

## 一句话结论

**协议层、OHOS 壳、Wayland 壳三部分都已跑通并有自动化验证；文件桥从 35 处删到 2 处。**
剩下的都是"需要外部条件"或"需要引擎侧大改"的项，见文末。

## 已完成（按里程碑）

| 里程碑 | 内容 | 证据 |
|---|---|---|
| M0 平台拆分 | `packages/lplatform-*`、`lpack-*` 成型，主仓无平台代码，8 项守卫进 CI | `tools/check-*.{py,sh}` 全绿 |
| M1 协议+传输 | IDL 13 接口 / 56 消息 + 生成器 + `liblwp_native.so`（环形队列/blob/eventfd）+ 检查器 + `.lwtrace` 录制回放 | `packages/lwp/test.sh`（12 仓颉 + C 套件） |
| M2 窗口/系统 | 握手、configure/ack、surface 生命周期、frame 闭环、system.info、剪贴板、对话框、窗口状态、`lw_test`、IME 请求 | 真机 7 条判据（见下） |
| M3 协议规则 | 违约计数（unackedConfigure/frameTimeout/attachOutOfOrder）、vsync 能力降级、能力位握手 | `lwindow` 36 项单测 |
| M6 文件桥删除 | 输入 / 剪贴板 / 对话框 / 窗口命令 / 抓帧五类文件桥全部删除 | 基线 35 → 2 |
| M1W Wayland 壳 | 连接合成器、xdg-shell 建窗、输入转发、wl_shm 上屏 | 假合成器 4 项集成测试 |

## OHOS 真机验收（MOR-M1 / API 26，2026-11-11）

| # | 判据 | 结果 |
|---|---|---|
| 1 | 指针点击/拖拽 + 键盘 | ✅ 425 motion / 4 button / 2 key |
| 2 | `lwp stats` 计数器 | ✅ dropped/bad/unknown/notHandshaked 全 0 |
| 3 | `lwp violations` | ✅ 三项全 0 |
| 4 | 文件桥停用 | ✅ `window_cmd poller skipped (lwp active)` |
| 5 | 调试开关受控 | ✅ release 下 `lanlu_env.txt` 失效 |
| 6 | 连续 resize 不崩 | ✅ 20/20 最大化还原 + 54 次真实 resize |
| 7 | `.lwtrace` 取证 | ✅ 901 条记录，verify PASS |

未覆盖：滚轮、输入法文本（`uitest` 无法注入这两类）。
**滚轮**已于第 69 轮接上 ArkUI `onAxisEvent` → `lw_input.pointer_axis`，只差人工滚动确认。

## Wayland 侧（M1W）

本机没有系统合成器，因此**在仓库内实现了假合成器**（手写 wire 协议，`tests/mock_compositor.rs`），
4 项集成测试覆盖：全局枚举 / 建窗+configure+ack / seat 输入转发（坐标精确）/ wl_shm 上屏（含缓冲复用）。

## 本轮新增的关键修复（2026-11-11）

**每帧 tick 吞输入事件**：`LwpWindowClient.poll()` 与输入共用 EVENT 队列，
遇到不认识的输入消息直接丢弃；而它由 `lwpFrameTick()` 每帧调用。
后果：指针移动常被吞 → 光标形状/IME 锚点失效、悬停与拖拽偶发丢失。

修法：`poll()` 把非生命周期消息**放回暂存区**，`nextLwpEvent()` 优先消费；
`awaitConfigure()` 同样修正。回归测试：`pollDoesNotSwallowInputEvents`（lwindow 39 项）。

**教训**：输入类问题先确认"消息有没有到达消费方"，一行 `probeTrace` 比三轮重构有效。

## 仍缺的事（与验收报告 §4 保持一致）

| 缺口 | 性质 | 现状 |
|---|---|---|
| 拖放的业务语义（拖到书库做什么） | **需产品决策** | 协议 4 条事件 + 壳 + 引擎接收都已就绪并打点 |
| 滚轮 | 需人工验证 | 已接线（ArkUI `onAxisEvent` → `pointer_axis`）；`uitest` 无法注入 |
| xdg-desktop-portal（文件对话框 / Settings） | 需 D-Bus 环境 | 未做 |
| 真实合成器目视验证 | 需桌面环境 | 本机无 weston/sway；CI 有 `smoke-weston.sh --require` 只验握手 |
| 引擎渲染到 Wayland fd | 需引擎改动 + 环境 | 壳侧 `wl_shm` 已通；`lgpu` 需"渲染到内存"导出 |
| OHOS 的 `attach.serial` 消费、dmabuf 路径 | 需设备复验 | 协议有字段，OHOS 侧未消费（当前直渲染不需要） |

> 注：早期版本这里写"cursor shapes 全量"——**已完成并真机验证**（第 83/90 轮，
> `lw_seat.set_cursor` 上链 + 系统 `PointerStyle` 生效）。

## 守卫与测试（每轮必跑）

```bash
python3 tools/check-deps.py                 # 依赖白名单（10 条已知）
python3 tools/check-platform-isolation.py   # 平台标识隔离（73 处已知）
bash tools/check-no-file-bridge.sh          # 文件桥只减不增（现 2 处）
bash tools/check-layering.sh                # 业务层无平台代码
bash tools/check-no-sdl.sh                  # 去 SDL 进度尺
python3 tools/lwp-gen.py --check-abi        # 协议只允许追加
bash packages/lwp/test.sh                   # 协议 + 通道 + lwtrace
bash packages/lplatform-ohos/selftest/run-tests.sh   # 壳侧发送端
(cd packages/lplatform-wayland && cargo test)        # Wayland 壳（11 项）
```

## 进程模型（2026-11-11 补充）

壳与引擎**同进程**是当前实现的隐含前提，两处直接依赖：
`lwp_open()` 的进程内单例；`attach.buffer` 当进程内 fd 用。

HarmonyOS 26.0.1 新增子进程 API（`startNativeChildProcess` / `getChildProcessInfos` /
`processMode=NEW_PROCESS_ATTACH_TO_PARENT` + C API），使「引擎跑在子进程」变得可行
（收益：引擎崩溃不拖垮壳）。**若要做，边界改动清单见计划 §5.2.1** —— 关键是
`attach` 的 fd 必须改走 `SCM_RIGHTS`，属 `protocol_major` 级改动。当前决定：暂不拆。

## 宿主机跑 client-next 测试的**真实**前置条件（2026-11-11 更正）

之前记的是"需要 cargo"，**不准确**。实测（第 73 轮）：
- cargo 在 `/workspace/horizon-ohos/.tooling/rust190/bin`，**可用**；
  `fontkit` / `webview` 的 Rust 原生依赖能正常编（webview 1m50s 编完）；
- 真正的卡点是 **ffmpeg 开发头**：`packages/libavformat_ffi/native/lanlu_avformat_bridge.c`
  需要 `libavcodec/avcodec.h`，宿主机没有；`/workspace/lanlu/.research-ohos/ohos-stubs/ffmpeg`
  里只有 OHOS 的 `.so`（无头文件，也不能在 x86_64 上链接）。

**结论**：要在宿主机跑 client-next 的 246 个测试，先 `apt install libavformat-dev libavcodec-dev`
（CI 里就是这么做的），并把 `pkg-config --libs libavformat` 的结果传给 FFI 搜索路径。
在那之前，这些测试只能在 CI 跑。

## 环境坑（踩过的）

- `/tmp` 是 512M tmpfs：**构建"失败但没有输出"几乎都是它满了**（脚本第一句就挂）。
  构建前先 `df -h /tmp`，必要时清掉历史残留。
- 应用沙箱可写路径是 `/data/storage/el2/base/files`；host 视角的 `/data/app/el2/100/...`
  从应用内 `fopen` **会失败且无显式报错**。
- 平台包的 C++/ArkTS 源码**未被 git 跟踪**（`git status` 显示 `??`），删改前务必先做快照
  （`/workspace/lanlu/tmp/snapshots/`）。
