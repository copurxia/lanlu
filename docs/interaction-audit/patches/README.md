# p0-focus-visible 补丁序列（可直接 git am 落地）

> 由 `git format-patch --zero-commit c39458f..HEAD` 生成，**105 个补丁 = 分支全部 105 个提交**。
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
| 0042 | docs: 使用指南 §12 键盘与无障碍总览 |
| 0043 | docs: 组件文档 §12 焦点接入 + 架构文档 KeyRepeat/应用接入 |
| 0044 | fix ContextMenu Tab 关闭（浮层一致性） |
| 0045 | docs: 方向键边界语义两条约定（钳制 vs 回绕） |
| 0046 | docs: 光标形状约定（含禁用子树不认领光标） |
| 0047 | docs: 滚动交互统一契约（9 个表面一致） |
| 0048 | docs: 浮层栈次序契约（8 条规则对应测试） |
| 0049 | ListView 激活语义（双击/Enter/Space） |
| 0050 | docs: API 参考 ListView 行补 onActivate |
| 0051 | LazyRow Shift+滚轮横向滚动 |
| 0052 | docs: 滚动契约表补 Shift+滚轮 |
| 0053 | TextField 编辑菜单项 editMenuItems |
| 0054 | docs: API 参考补 editMenuItems |
| 0055 | TextArea editMenuItems 对齐 |
| 0056 | docs: TextArea 行补 editMenuItems |
| 0057 | KeyRepeat 补进 cui.cj 公开再导出 |
| 0058 | ComboBox 弹层 Home/End |
| 0059 | docs: API 参考 ComboBox 行补 Home/End |
| 0060 | Dropdown 弹层 Home/End |
| 0061 | docs: API 参考 Dropdown 行补 Home/End |
| 0062 | ContextMenu 键盘 Home/End |
| 0063 | docs: API 参考 ContextMenu 行补键位 |
| 0064 | docs: 组件文档与指南补最新 API |
| 0065-0070 | 基线削减（69→7 条豁免）与测试画布抽取 |
| 0071 | docs(README): sdl → lgui 更名纠正 |
| 0072 | docs: 四份文档更名残留清理 |
| 0073 | test: Table selectionRange 无选择边界 |
| 0074 | test: 禁用控件不认领悬停光标 |
| 0075 | test: Drawer 首次测试覆盖（3 例） |
| 0076 | test: ScrollBar 首次直接测试（3 例） |
| 0077 | test: Binding 双向投影首次测试（2 例） |
| 0078 | docs(examples): README 更名纠正 |
| 0079 | feat(examples): keyboard 交互示例 |
| 0080 | docs(api): 补 MenuItem.invoke 与 TextEditState 按词方法 |
| 0081 | fix: 帧上传预算——单张超预算图不再永久被拒 |
| 0082 | fix: 像素登记校验（尺寸/字节数不符拒绝，防越界读）|
| 0083 | fix: registerPixelImage 同步校验 |
| 0084 | docs(api): 内存像素图 API 段 |
| 0085 | docs(components): PixelImageView 段 |
| 0086 | feat: onPixelImageRejected 拒绝回调 |
| 0087 | docs(api): 补该回调说明 |
| 0088 | fix: 原生像素拒绝路径先释放再回调 |
| 0089 | test: 外部滚动偏移越界钳制 |
| 0090 | test: 控件身份解析契约 |
| 0091 | test: 图像适配几何四例 |
| 0092 | fix: 像素尺寸单边上限（防巨量 memcpy）|
| 0093 | docs: 补 pixelMaxImageSide 说明 |
| 0094 | fix(examples): calendar 徽标改用内存像素图 |
| 0095 | test: staged 淘汰回调契约 |
| 0096 | docs(examples): 按词操作提示 |
| 0097 | docs(components): TextField 按词操作 |
| 0098 | feat: TextArea 按词操作 |
| 0099 | docs(components): TextArea 按词操作 |
| 0100 | docs: 括号修正 |
| 0101 | feat: TreeView onActivate |
| 0102 | docs(components): TreeView onActivate |
| 0103 | feat: Table onActivate |
| 0104 | feat: Table.of 也接受 onActivate |
| 0105 | test: 锁定 Table.of 转发 |

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
