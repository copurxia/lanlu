# p0-focus-visible 补丁序列（可直接 git am 落地）

> 由 `git format-patch --zero-commit c39458f..HEAD` 生成，**41 个补丁 = 分支全部 41 个提交**。
> 已校验：在 `c39458f` 的干净克隆上 `git am --3way patches/*.patch` 全部干净应用，
> 重建出的 tree hash 与分支 tip **完全一致**（`b902e1a3dfe413252109cafd4d52f31e1c481c27`）。
> 补丁文件名为 ASCII 截断（git 生成），提交标题在补丁内是标准 UTF-8 编码，`git am` 会正确还原。

## 何时用补丁而不是合并分支

主仓 `packages/cangjie-gui` 长期有他人未提交改动（合并被挡住）时，可用补丁在干净克隆里
落地、评审或真机重编；也可只落地前若干个补丁（例如先只要 P0）。

```bash
cd /path/to/cangjie-gui
git status --short          # 期望为空，否则 --3way 可能把他人改动搅进提交

git am --3way /path/to/lanlu/docs/interaction-audit/patches/*.patch   # 全部
git am --3way /path/to/lanlu/docs/interaction-audit/patches/000{1,2}-*.patch  # 只要 P0
```

## 分组对照

| 补丁 | 内容 |
|---|---|
| 0001 | **P0** 字段族点击聚焦可见 + 键盘外环；Pagination/Breadcrumb/StepIndicator 键盘化 |
| 0002 | **P0** Slider 焦点可见性 + Up/Down/Home/End |
| 0003–0004 | **P1** Modal 打开即聚焦 / 关闭恢复焦点、Drawer 恢复焦点（+ 文档） |
| 0005–0006 | `Key` 补 PageUp/PageDown/Menu + ScrollView 键盘滚动；TextArea 翻页 |
| 0007 | ContextMenu 键盘唤起（Menu / Shift+F10） |
| 0008–0009 | **FocusTarget** 自绘件焦点底座（+ 文档） |
| 0010 | Toast 可关闭 / 不穿透 / 悬停暂停 |
| 0011 | Tooltip 键盘聚焦即显 |
| 0012 | 只读字段点击不进焦 + WordCloud 键盘化 |
| 0013 | RadioButton `groupRange` 组内方向键 |
| 0014 | TextField `onSubmit` 回车提交钩子 |
| 0015 | 字段族悬停三态 + 禁用蒙版按圆角 |
| 0016 | 列表 / 表格行悬停高亮 |
| 0017 | 中文 / 日文双击选词按脚本分组 |
| 0018 | MenuBar Menu / F10 唤起 |
| 0019–0020 | 焦点矩形上报 + ScrollView / LazyColumn reveal-on-focus |
| 0021 | architecture 文档（reveal 机制） |
| 0022 | 实心按钮（Primary/Danger）按下 / 悬停反馈 |
| 0023–0024 | RichText `RichSpan.link` 可点击链接（+ 文档） |
| 0025 | 开关 / 单选 / 复选 / 滑块悬停反馈 |
| 0026 | 测试探针预置 `Canvas.releaseTexture`（合并零适配） |
| 0027 | LazyRow 键盘横向滚动 + 焦点滚入视野 |
| 0028 | 开放 `registerFocusStop`：应用层自绘件可自行登记焦点停靠点（缺口 #2 第二个入口） |
| 0029 | 公开 `drawFocusRing`：应用自绘件画同一种焦点环 |
| 0030 | 框架级按键长按连发 `KeyRepeat`（OHOS 无原生 repeat） |
| 0031 | Picker/Stepper Home/End + Table 键盘排序（#20 收尾） |
| 0032 | 按词编辑：Ctrl+跳词/删词（#18 收尾） |
| 0033 | ListView Shift 区间选择（#9 收尾，20 类缺口全部落地） |
| 0034 | 焦点指示色主题对比度下限守卫（F1 部分自动化） |
| 0035 | Table 区间选择（#9 表格版） |
| 0036 | 焦点环契约测试（只在键盘到达时绘制） |
| 0037 | ReorderableList 键盘重排（Alt+Up/Down） |
| 0038 | RichText 链接键盘可达（Left/Right 切换 + Enter 触发） |
| 0039 | ComboBox 箭头悬停反馈 |
| 0040 | docs: API 参考补全焦点/键盘/交互 API（§12） |
| 0041 | docs: 修正指向旧 sdl/ 目录的失效链接 |

## 已知冲突面

- `src/controls/modal.cj`：主仓该文件有他人未提交改动。若那批先落地，0003 可能冲突——
  `--3way` 多数情况可自动合并；手工解时保留对方的渲染/模糊改动、采纳本补丁的
  `claimInitialFocus` 与 `contentFocusables`。
- 其余改动只新增文件或触及对方未改的文件（已逐文件核对，见 PR 描述 §六）。

## 应用后验证

```bash
tools/verify-cui-interactions.sh            # 主仓
tools/verify-cui-interactions.sh p0         # 分支工作树
```

期望：`TOTAL 444 / PASSED 403 / ERROR 40 / FAILED 1`，脚本输出「基线匹配」。
