# lwindow

## backend.lwp / backend.headless（计划 §6、§9.5）

- `src/backend_lwp.cj`：把 `LwpMessage` 解成 `LWindowEvent` 的**唯一事件漏斗**（`decodeLwpEvent`）+
  主循环入口 `pollLwpEvents(ch)`。
- `src/backend_headless.cj`：内存通道上的假壳（`HeadlessShell`），用于不启动真壳就跑通
  「壳 → 通道 → 漏斗 → 事件」；也是 `lwtrace` 回放的载体。
- 回放：`channel.replay("x.lwtrace")` 把录制的壳侧消息重放进通道，引擎走同一条漏斗——
  `backend_test.cj` 的 `recordThenReplayYieldsSameEvents` 断言回放后事件序列与录制时逐字段一致。

### 宿主单测注意

本包依赖真实系统库（vips/vlc/rocksdb/SDL3）。CI 装了 apt 依赖 + 仓库内 SDL3，直接可跑：

```bash
export LWP_LIB_DIR="$PWD/packages/lwp/lib"
export LGUI_SDL_LIB_DIR="$PWD/packages/cangjie-gui/sdl/.sdl3"
bash packages/lwp/native/build.sh
(cd packages/lwindow && cjpm test)
```

本机若缺这些库，可在 `LWP_LIB_DIR`/`LGUI_SDL_LIB_DIR` 指向的目录放**空符号 stub**
（不入库；只为让链接通过，运行时这些路径不会被测试用到）。

### 输入源开关（过渡期）

`LANLU_LWP=1` 时引擎从协议通道取事件（`nextLwpEvent`），否则仍走文件桥。
两套并存是**过渡措施**，文件桥在 M6 删除清单里；出口只有一个：都产出 `LWindowEvent`。

壳侧对应要求（`docs/l-layer.md` M0-4 结论）：`liblwp_native.so` 必须以 `RTLD_GLOBAL` 加载、
且早于引擎；壳先 `lwp_open("lanlu")` 建通道，引擎同名 `lwp_open` 拿到同一实例。

### 两个 Cangjie 语言坑（已踩，务必注意）

1. `match (x) { case SOME_LET_CONST => ... }` 里的 `case` 是**绑定模式**，会匹配一切，
   后面的分支永远不可达（编译器只给 unreachable-pattern 警告）。协议 opcode 判等必须用 `if/else`。
2. `UInt32(floatValue)` 是**数值转换**（截断/溢出抛异常），不是 IEEE-754 位模式。
   浮点上线必须用 `CPointer<Float32>` 写原始字节。
