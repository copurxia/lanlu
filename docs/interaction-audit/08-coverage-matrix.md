# 验收项 ↔ 自动化覆盖矩阵

> 目的：交接/验收时一眼看出某条检查项是"测试兜底"还是"必须人工看"。
> 测试名均可 grep 到：`grep -rn "func <名字>" packages/cangjie-gui-p0`。基线见
> [test-baseline-names.txt](test-baseline-names.txt)（40 ERROR + 1 FAILED 属环境）。

图例：✅ 有自动化覆盖；🟡 框架侧有覆盖、应用侧需人工；❌ 仅人工验收；⛔ 已知未实现。

| 检查项 | 覆盖 | 对应测试 |
|---|---|---|
| A1 点进输入框激活边 | ✅ | `pointerFocusPaintsActiveFieldChrome`、`unfocusedFieldKeepsIdleChrome`、`textAreaSharesTheSameActivationPolicy` |
| A2 字段悬停三态 | ✅ | `fieldSurfaceHasDistinctHoverState`、`textFieldHoverIdMatchesFieldId` |
| A3 Tab 外环 / 鼠标不画外环 | ✅ | `keyboardFocusAddsRingOnTopOfActiveChrome`、`drawFocusRingPaintsAccentHaloOutsideBounds` |
| A4 回车提交（登录） | 🟡 | 框架：`textFieldEnterCallsSubmitWhenFocused`、`textFieldEnterWithoutSubmitPreservesNoop`；应用接线需人工 |
| A5 回车提交（弹窗/合集） | 🟡 | 同上（应用补丁 0001 未在完整环境编译验证） |
| A6 打开即聚焦 | 🟡 | 框架：`modalOpenFocusesFirstStop`、`autofocusClaimsFocusOnceOnFirstFrame`；应用各处需人工 |
| A7 关闭弹窗焦点回原位 | ✅ | `modalDismissRestoresPriorFocus`、`modalTabCyclesDialogFocusOnly`、`modalEscapeDismissesAndHiddenRegistersNothing` |
| A8 只读字段不抢焦 | ✅ | `editableTextAreaJoinsFocusRingButReadOnlyDoesNot`、`editableTextAreaRequestsTextCursorButReadOnlyDoesNot` |
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
| F1 深浅主题对照 | ❌ | 仅人工（配色无快照测试） |
| F2 高 DPI / 窗口尺寸 | ❌ | 仅人工 |
| F3 输入法候选框位置 | 🟡 | 桌面：`focusedCaretReportsImeAnchorInBothBlinkPhases`（基线中为 ERROR，需真实渲染后端）；真机仍须人工 |
| F4 重启后无残留焦点环 | ❌ | 仅人工 |

## 覆盖统计

共 31 条（A8 / B6 / C4 / D3 / E6 / F4）：

- 自动化兜底（✅）：**20** 条
- 框架有覆盖、应用侧需人工（🟡）：**7** 条（A4、A5、A6、B1、D1、D2、F3）
- 仅人工（❌）：**4** 条（D3、F1、F2、F4）
- 已知未实现（⛔）：0 条

> 结论：合并后真正需要人工盯的是**应用层接线**（回车、初始聚焦、自绘件布局）与**视觉/DPI/IME**，
> 框架行为本身已被 60+ 个新用例覆盖。
