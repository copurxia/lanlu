# client-next on HarmonyOS — 人工验收清单

> 前置：设备已连接（`hdc list targets` 有输出）、DevEco 调试签名可用（能生成 signed HAP）。
> 一条命令跑自动项：`bash /workspace/lanlu/.research-ohos/verify-cn.sh`

## 0. 自动门禁（无需设备，随时可跑）

```bash
bash /workspace/lanlu/.research-ohos/check-soname-closure.sh   # 依赖闭包 + 架构
bash /workspace/lanlu/.research-ohos/check-symbol-consistency.sh
bash packages/lplatform-ohos/deps/rocksdb/run-host-test.sh
bash packages/lplatform-ohos/deps/fontkit/run-host-test.sh
```

## 1. 启动与基础渲染

- [ ] 安装启动后进程存活：`hdc shell "ps -ef | grep clientnext"`
- [ ] 窗口有内容（非空白）：`devecocli ui screenshot` 后与停止态对比像素差 > 0
- [ ] hilog 里有 `[LANLU-SHELL] startFilter win=... rc=0`
- [ ] 应用图标/名称正常（桌面显示 logo，不是空白方块）

## 2. 输入

- [ ] **键盘**：↑/↓ 能移动焦点或滚动（截图应有变化）
- [ ] **鼠标**：移动指针位置与内容对齐（尤其纵向；若偏移，记录 `hilog | grep LANLU-INPUT` 的 `disp=(x,y) local=(x,y)`）
- [ ] **滚轮**：列表/阅读页可滚动
- [ ] **文本输入**：点进登录框能输入中文/英文（IME 桥接）；退格、回车、左右方向键、Ctrl+C/V 生效
- [ ] 手机形态设备：点输入框弹出软键盘

## 3. 登录与书库（需要后端）

- [ ] 添加服务器 → 保存后能探测在线状态
- [ ] 输入用户名/密码登录成功 → 进入书库
- [ ] 书库三行（继续阅读/随机/最新）有数据
- [ ] **封面图片正常显示**（这是 vips 双 free 修复的验证点——此前必崩）
- [ ] 分类切换、搜索可用

## 4. 阅读

- [ ] 打开图片档案翻页、缩放正常
- [ ] HTML 档案（Blitz）能渲染正文（字体不是方块）
- [ ] 阅读进度上报成功（换设备/重启后仍记得）

## 5. 播放

- [ ] 视频档案能播放，画面 640×360 级别正常
- [ ] **有声音**（音频渲染器输出）
- [ ] 拖动进度条后**音画同步**（本轮修复点）
- [ ] 字幕轨自动选择并渲染（ASS 字幕样式正常）

## 6. 文件交互

- [ ] 上传档案：点上传 → 系统选择器 → 选中后能开始上传
- [ ] 导出/下载单个文件：选保存位置 → 文件出现在目标位置
- [ ] 批量下载到文件夹：选目录 → 完成后文件出现在该目录（若 provider 拒绝，文件保留在应用沙箱并打日志）

## 7. 窗口行为

- [ ] 拖拽改窗口大小：内容跟随重排（不糊不歪）
- [ ] 标题栏**最小化**按钮生效（本轮新接）
- [ ] 标题栏**关闭**按钮：应用真正退出（不残留空白窗口）
- [ ] 再次冷启动：设置/会话仍在（KV 持久化）

## 8. 稳定性

- [ ] 反复冷启动 3 次均正常（无 SIGTRAP）
- [ ] 打开带封面的书库后放置 5 分钟：CPU 占用应接近 0（空闲不渲染）
- [ ] 后台切回：画面恢复、无花屏

## 失败时请提供

1. `hdc shell "hilog -x" | grep -E 'LANLU|CANGJIE|signo'` 最近 100 行
2. 应用数据目录：`/data/app/el2/100/base/<bundle>/files/` 下 `vlclog.txt`、`asslog.txt`、`imgdbg`（若存在）
3. 复现步骤与期望/实际
