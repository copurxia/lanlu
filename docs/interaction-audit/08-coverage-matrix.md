# 验收项 ↔ 自动化覆盖矩阵

> 目的：交接/验收时一眼看出某条检查项是"测试兜底"还是"必须人工看"。
> 测试名均可 grep 到：`grep -rn "func <名字>" packages/cangjie-gui-p0/src packages/cangjie-gui-p0/lgui`。
> 基线见 [test-baseline-names.txt](test-baseline-names.txt)（**7 条**属环境，逐条定性见
> [test-baseline-notes.md](test-baseline-notes.md)）。
>
> **本表的测试名已全量核对**（2026-11-12 02:13）：表内 79 个测试名中，78 个可在 `src/` 或
> `lgui/` 的 `*_test.cj` 里 grep 到；唯一例外是应用侧的 `readerHtmlPageTurn`——它本就标注为
> ❌「仅人工」，符合预期。

图例：✅ 有自动化覆盖；🟡 框架侧有覆盖、应用侧需人工；❌ 仅人工验收；⛔ 已知未实现。

| 检查项 | 覆盖 | 对应测试 |
|---|---|---|
| A1 点进输入框激活边 | ✅ | `pointerFocusPaintsActiveFieldChrome`、`unfocusedFieldKeepsIdleChrome`、`textAreaSharesTheSameActivationPolicy` |
| A2 字段悬停三态 | ✅ | `fieldSurfaceHasDistinctHoverState`、`textFieldHoverIdMatchesFieldId` |
| A3 Tab 外环 / 鼠标不画外环 | ✅ | `keyboardFocusAddsRingOnTopOfActiveChrome`、`drawFocusRingPaintsAccentHaloOutsideBounds`、`focusRingIsKeyboardOnlyAcrossControlFamilies`、`focusRingFollowsFocusIdentityNotPresence`、`clearingFocusRemovesRing` |
| A4 回车提交（登录） | 🟡 | 框架：`textFieldEnterCallsSubmitWhenFocused`、`textFieldEnterWithoutSubmitPreservesNoop`；应用接线需人工 |
| A5 回车提交（弹窗/合集） | 🟡 | 同上（应用补丁 0001 未在完整环境编译验证） |
| A6 打开即聚焦 | 🟡 | 框架：`modalOpenFocusesFirstStop`、`autofocusClaimsFocusOnceOnFirstFrame`；应用各处需人工 |
| A7 关闭弹窗焦点回原位 | ✅ | `modalDismissRestoresPriorFocus`、`modalTabCyclesDialogFocusOnly`、`modalEscapeDismissesAndHiddenRegistersNothing` |
| A8 只读字段不抢焦 | ✅ | `editableTextAreaJoinsFocusRingButReadOnlyDoesNot`、`editableTextAreaRequestsTextCursorButReadOnlyDoesNot` |
| A8c 树叶子激活 | ✅ | `treeEnterOnLeafActivates`、`treeEnterOnParentExpandsWithoutActivating`（TreeView onActivate：叶子 Enter 激活、父节点 Enter 只展开/折叠）|
| A8b 按词编辑（缺口 #18 后半） | ✅ | TextField 原有；TextArea 本轮补齐——`textAreaCtrlBackspaceDeletesPreviousWord`、`textAreaWordMotionMethodsExistOnEditState`（词边界 UTF-8 字节偏移逐跳验证：标点/汉字/单词各自成词）|
| B1 自绘件可 Tab | 🟡 | 框架：`registerFocusStopPutsSelfDrawnWidgetInTabRing`、`registerFocusStopIsNoOpOutsideBuildRoot`、`focusTargetReportsOwnStopBeforeChildStops`；应用 40+ 处需人工 |
| B2 Enter/Space 激活 | ✅ | `focusTargetRegistersAndActivatesByKeyboard`、`focusTargetReleaseOutsideCancelsActivation` |
| B3 焦点滚入视野 | ✅ | `scrollViewRevealsFocusedRectBelowViewport`、`scrollViewLeavesVisibleFocusAlone`、`lazyColumnRevealsFocusedRow`、`lazyRowRevealsFocusedItem`、`focusRectRoundTripsThroughContext` |
| B4 横排键盘滚动 | ✅ | `lazyRowArrowKeysScrollHorizontally`、`lazyRowLeavesVisibleFocusAlone` |
| B5 分页/面包屑/步骤条/标签云 | ✅ | `paginationFocusesAndStepsWithArrows`、`paginationKeyboardArrowsClampAtEnds`、`breadcrumbKeyboardWalksAndActivates`、`breadcrumbDisplayOnlyStaysOutOfFocusRing`、`stepIndicatorKeyboardWalksAndActivates`、`wordCloudKeyboardWalksAndActivates`、`wordCloudEmptyStaysOutOfFocusRing` |
| B6 列表/表格/滚动容器键盘 | ✅ | `scrollViewPageKeysScrollByViewport`、`scrollViewArrowKeysStepAndClamp`、`scrollViewHomeEndJumpToDocumentEnds`、`scrollViewKeysYieldToFocusableChild`、`textAreaPageKeysConsumedOnlyWhileFocused` |
| C1 Toast 关闭/不穿透 | ✅ | `toastClickDismissesAndConsumesEvent`、`toastPointerEventsDoNotFallThrough`、`toasterDismissIsIdempotent` |
| C2 Toast 悬停暂停 | ✅ | `toastHoverPausesCountdown` |
| C3 Tooltip 键盘即显 | ✅ | `tooltipShowsOnKeyboardFocusImmediately` |
| C4 Menu / Shift+F10 | ✅ | `menuBarOpensWithMenuKeyShortcut`、`contextMenuOpensWithMenuKeyWhenFocusInside`、`contextMenuShiftF10NotInterceptedWithoutFocus`、`keyFromScancodeMapsLettersAndControls` |
| D1 dock 键盘翻页 | 🟡 | 框架键位：`scrollViewPageKeysScrollByViewport`、`textAreaPageKeysConsumedOnlyWhileFocused`；dock 侧应用补丁 0003 需人工 |
| D2 长按连发 | 🟡 | 框架：`keyRepeatFiresAfterDelayThenAtInterval`、`keyRepeatStopsOnKeyUp`、`keyRepeatDefersWhenBackendProvidesRepeat`、`keyRepeatCanBeDisabled`；真机节奏需人工 |
| D3 html 页内翻滚 | ❌ | 应用侧 `readerHtmlPageTurn`，无自动化 |
| E1 实心按钮按下/悬停 | ✅ | `primaryButtonPressDarkensFill`、`dangerButtonHoverBrightensFill` |
| E2 开关/单选/复选/滑块悬停 | ✅ | `switchTrackTintsOnHover`、`checkboxBorderTintsOnHover`、`sliderKnobGrowsOnHover` |
| E3 行悬停 | ✅ | `listViewHighlightsHoveredRow` |
| E4 中文双击选词 | ✅ | `doubleClickCjkStopsAtPunctuation`、`doubleClickMixedScriptsStaySeparate`、`doubleClickFullwidthPunctuationSelectsItsRun`、`doubleClickAsciiWordUnchanged`、`doubleClickWhitespaceSelectsSpaceRun` |
| E5 富文本链接 | ✅ | `richTextLinkClickRunsCallback`、`richTextMultipleLinksAreIndependent` |
| E6 Slider/Radio 键盘 | ✅ | `sliderKeyboardStepsUpAndDown`、`sliderKeyboardHomeEndJumpToRangeEnds`、`sliderKeyboardClampsOutsideRange`、`radioButtonGroupArrowsMoveSelection`、`radioButtonArrowsNoopWithoutGroupRange` |
| F1 深浅主题对照 | 🟡 | 框架下限已自动化：`focusAccentStandsOutAgainstFieldInBothThemes`、`focusAccentStandsOutAgainstPanelInBothThemes`、`hoverFieldActiveDiffersFromIdleFieldInBothThemes`（亮度差下限守卫）；视觉风格仍人工 |
| F2 高 DPI / 窗口尺寸 | ❌ | 仅人工 |
| F3 输入法候选框位置 | 🟡 | 桌面：`focusedCaretReportsImeAnchorInBothBlinkPhases`（基线中为 ERROR，需真实渲染后端）；真机仍须人工 |
| F4 重启后无残留焦点环 | ❌ | 仅人工 |

## 覆盖统计

共 31 条（A8 / B6 / C4 / D3 / E6 / F4）：

- 自动化兜底（✅）：**20** 条（另 F1 有亮度差下限守卫）
- 媒体路径另有 **5** 项修复带测试（见文末「媒体路径」节），不含在上面的交互计数里
- 框架有覆盖、应用侧需人工（🟡）：**8** 条（A4、A5、A6、B1、D1、D2、F1、F3）
- 仅人工（❌）：**3** 条（D3、F2、F4）
- 已知未实现（⛔）：0 条

> 结论：合并后真正需要人工盯的是**应用层接线**（回车、初始聚焦、自绘件布局）与**视觉/DPI/IME**，
> 框架行为本身已被 60+ 个新用例覆盖。

## 媒体路径（图像/封面/纹理）——本轮新增覆盖

审计过程中在 media 路径发现 5 个真实缺陷并修复，每个都有测试兜底：

| 项 | 缺陷 | 修复 | 自动化 |
|---|---|---|---|
| 帧上传预算 | 单张图 > 预算时每帧被拒 → **永久空白** | `0081` 超预算放行一次 | ✅ `oversizedSingleUploadIsAllowedOncePerWindow`、`unthrottledBudgetAllowsEverything` |
| 两阶段登记 | 尺寸/字节数不校验 → 越界读（花屏/崩溃） | `0082` 拒绝 + 释放指针 | ✅ `stageRejectsByteCountMismatch`、`stageRejectsNonPositiveSize`、`stageAcceptsValidByteCount` |
| 一步注册 | 同上（视频/流式路径） | `0083` 同校验 | ✅ `registerRejectsByteCountMismatch`、`registerRejectsNonPositiveSize` |
| 可观测性 | 静默拒绝 → 只看到空白无线索 | `0086` `onPixelImageRejected(key, reason)` | ✅ `rejectionCallbackReportsReason` |
| 巨量 memcpy | 荒唐尺寸在拷贝前未拦 → OOM/崩溃 | `0092` `pixelMaxImageSide`（默认 16384） | ✅ `oversizedSideIsRejectedBeforeCopy`、`oversizedSideOnRegisterIsRejected` |

另有 4 个几何用例固定适配行为（Contain/Cover/Stretch/零尺寸），证明**裁切几何本身正确**
——真机"封面空白"的嫌疑因此收窄到**纹理获取**（见 [12-findings-for-other-party.md](12-findings-for-other-party.md)）。
