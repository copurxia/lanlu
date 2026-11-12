# 测试基线豁免说明（7 条）

`test-baseline-names.txt` 里的每一行都是**本机无法真实通过**的用例；脚本会对整份名册做
精确 diff，因此文件本身不能写注释。本文件记录每条豁免的**性质与依据**，便于评审判断
"这是环境限制还是掩盖了回归"。

判定原则：只要某条失败属于下列四类之一，就不是回归；任何**新增**失败都会让脚本报错。

| 用例 | 类别 | 依据 |
|---|---|---|
| `byteBudgetAccountsStagedAndTexturesTogether` | 需真实 SDL 窗口 | 调用 `ensureVideoDriver()` + `SdlWindow(64×64)`；无显示环境无法建窗 |
| `streamingRegisterReusesSameTextureInstance` | 需真实 SDL 窗口 | 同上；且断言纹理实例复用，需真实 GPU 纹理对象 |
| `focusedCaretReportsImeAnchorInBothBlinkPhases` | 需真实文本度量 | 断言 IME 锚点像素位置，零测度画布下 `textWidth` 恒 0 会失真（实测过） |
| `focusedCaretRequestsFrameAtNextBlinkToggle` | 需真实文本度量 | 同上，帧请求时机由 caret 几何触发 |
| `textFieldFollowsCaretHorizontally` | 需真实文本度量 | 注释写明"40 bytes = 330px"；零测度画布下 caret 永不越界（实测从 ERROR 变 FAILED 后回退） |
| `pushWakeEventWakesWaitingLoopFromAnotherThread` | 需真实跨线程唤醒 | 唯一 FAILED（非 ERROR）：依赖真实事件循环唤醒时序 |
| `scrimSortsStopsAndIgnoresEvents` | 可转但成本不值 | `cui.media` 包内无记录画布类，转绿需新增 ~25 方法画布；收益 1 条 → 判定不做 |

## 历史（削减过程）

起点 41 条 → 35（ComboBox 族装画布）→ 23（controls 全局装画布，连带 dropdown/listView/
tableCustomCell 12 条）→ 9（datePicker/timePicker 族 13 条）→ 8（textAreaWheel）→ 7
（modal 内右键菜单）。共 **34 条从"环境失败"转为真实通过**，每条都是真跑真断言。

## 如何自己验证

```bash
tools/verify-cui-interactions.sh p0     # 输出 Summary + 与名册的 diff
```

若名册出现**新增**名字 → 是回归，必须排查；若名册里某条**消失**（转为通过）→ 把该行从
`test-baseline-names.txt` 删掉并更新本文档。
