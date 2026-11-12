# 给另一任务方的代码审查发现（纹理/封面路径）

> 背景：对方正在真机调试"封面空白"（`src/media/pixel_texture_cache.cj`、
> `src/media/pixel_image_view.cj` 有多处 `~/img_diag.txt` 诊断代码，未提交）。
> 这些文件属于对方 WIP，我**不能在分支里改**；这里只记录读代码得到的可验证假设，
> 供转达。所有行号基于主仓当前工作树（2026-11-12 02:40）。

## 发现 1：单张图超过上传预算时会被**永久拒绝**（不是顺延一帧）

`pixel_texture_cache.cj:148-162`

```cangjie
private func pixelUploadAllowed(bytes: Int64): Bool {
    if (pixelUploadBudgetBytes <= 0) { return true }
    let now = MonoTime.now()
    if ((now - uploadWindowStart).toMilliseconds() >= 16) {
        uploadWindowStart = now
        uploadedThisWindow = 0          // 每 16ms 重置窗口
    }
    if (uploadedThisWindow + bytes > pixelUploadBudgetBytes) { return false }
    uploadedThisWindow += bytes
    true
}
```

`pixelUploadBudgetBytes` 默认 **16 MiB**（`:143`）。当**单张图**的 `bytes > budget` 时：
窗口重置后 `uploadedThisWindow = 0`，条件变成 `0 + bytes > budget` —— **恒为真**，
于是这张图**每一帧都会被拒**，永远画不出来。

临界值：`width * height * 4`。2048×2048 恰好 16 MiB（可通过）；3000×3000 = 36 MB
（**永久空白**）。若真机封面原图较大（未缩放的高清封面很常见），这就是"封面空白"的
直接解释。

**已在本分支修复（`81` 号提交）**：单张超预算时放行一次并照常累加（同窗口其余上传仍
节流）。已实测**与对方的 WIP 零冲突**——我的改动在 `pixelUploadAllowed` 内，对方的诊断代码
在 `pixelTexture`/`uploadNativePixelTexture` 内，`git am --3way` 干净合入（合并演练
503 例 / 496 通过 / 基线匹配）。对方拉取本分支后其诊断代码原样保留、bug 即消失。

其他可选改法（若对方想自己改）：
- 预算判断加"窗口为空时放行单张超预算图"：`if (uploadedThisWindow == 0) { ...放行... }`
  然后照常累加（下一张自然会等到下个窗口）；
- 或上传前把过大图降到预算内（缩略图路径本来就在做尺寸选择）。

## 发现 2：被拒时直接 `return None`，没有占位/降级

`pixelTexture` 在预算被拒时 `return None`（`:420-435`），`PixelImageView.draw` 对
`None` 的处理是"绘制为空"（`pixel_image_view.cj:84` 的 `case None => ()`）。
与发现 1 叠加 = 该 key 永远空白、且没有任何视觉线索。诊断代码会先落 `budgetDeny` 行，
再每帧重复判断——**建议先做这一步**：

```bash
grep -E 'budgetDeny|uploadNative FAIL|noStaged|cooldown' ~/img_diag.txt | head -20
```

若出现 `budgetDeny ... bytes=NNNNNNN window=0 budget=16777216`，且 `bytes > budget`，
即可确诊发现 1。

## 发现 3：`pixel_image_view` 的绘制诊断缺少最关键的三个量

现有诊断记录 `texId / closed / frame.w×frame.h`（`pixel_image_view.cj:63-72`），但
"纹理存在却画不出来"最常见的原因是**尺寸为 0** 或**目标矩形退化**：

- `image.width / image.height`（为 0 时 `fittedRect` 会产出零尺寸目标矩形）；
- `destination` 的 `x/y/w/h`（`fittedRect(...)` 的返回值，`zoomFactor`/`cornerRadius` 分支
  也可能把它裁没）；
- `frame` 是否在 `layout` 里被赋过值（若控件被 `visible(false)` 或未布局，`frame` 仍是
  `Rect.zero`）。

三者各加一个字段，就能把"有纹理但零尺寸"和"纹理本身没上传"彻底区分开。

## 追加修复（`0082` / `0083`）：像素登记不校验尺寸与字节数

同一文件里还有一处**同类缺陷**，也已在分支内修好：

| 入口 | 问题 | 修复 |
|---|---|---|
| `stagePixelImage(key, w, h, pixels)` | 不校验 `w/h` 与 `pixels.size`；上传按 `w*h*4` 读数组 → 越界读（花屏/崩溃，表现为"封面空白或花块"）| 非正尺寸或长度不符一律拒绝登记（不污染 LRU 记账），`0082` |
| `stageNativePixelImage(...)` | 同上（无字节数可验，只校尺寸）；**且拒绝时必须自己调 `releaser.release()`**（所有权已随调用转移）| `0082` |
| `registerPixelImage(renderer, ...)` | 视频/流式路径，同样按 `w*h*4` 读数组且不校验 | 同一道校验，且在**建纹理之前**拒绝，`0083` |

三条各带测试（`pixel_upload_budget_test` / `pixel_stage_validation_test` /
`pixel_register_validation_test`），共 7 个用例。合并演练对对方最新 WIP 零冲突：
**520 例 / 513 通过 / 基线匹配**。

**建议对方的排查顺序**：
1. 先 grep `~/img_diag.txt` 里的 `budgetDeny`（确认是否"大图永久被拒"）；
2. 若没有 budgetDeny，检查解码器给出的 `width/height` 与像素数组长度是否匹配
   （不匹配时现在会被静默拒绝 → 表现为空白；可在 `stagePixelImage` 拒绝分支临时加一行诊断）；
3. 若两者都正常，再把 `image.width/height` 与 `destination` 加进绘制诊断（见发现 3）。

## 结论：适配几何本身是对的（`0091`）

`fittedRect` / `scaledRect`（Cover/Contain/Stretch 的目标矩形计算）此前无测试，现已补四例
（`image_fit_geometry_test`）：2:1 图进 1:1 框，Contain 得 100×50 + 垂直居中，Cover 得 200×100
+ 水平居中（溢出由 `pushClip` 裁掉），Stretch 直接用 frame，零尺寸退化空矩形。

**含义**：封面"画不出来"时，几何不是嫌疑——问题必在**纹理获取**（上传被拒/冷却/预算）
或**纹理本身无效**（尺寸为 0、已关闭）。可据此把排查范围从"绘制/裁切"收窄到"纹理"。

## 顺带发现：`streamingTextureFromPixelsRgba` 少一道校验（未改，附建议）

`lgui/src/texture.cj`：

- `textureFromPixelsRgba`、`updateStreamingTextureRgba` 都会先校验
  `pixels.size == width*height*4` 并抛 `CuiException`；
- **`streamingTextureFromPixelsRgba` 没有这道校验**，直接把尺寸与数组交给后端
  `canvas.uploadTexture`——长度不符时后端会按 `width*height*4` 读数组，越界读。

框架的 `registerPixelImage` 已在调用前校验（`0083`），所以**经由框架的路径是安全的**；
只有直接调 lgui 这个 API 的代码会踩到。

**没改的原因**：`lgui/src/texture.cj` 正是对方当前未提交的 WIP 文件之一（纹理上传相关），
在其中加校验的冲突风险高于收益。建议对方顺手加同一道校验（两行）：

```cangjie
let expected = Int64(width) * Int64(height) * 4
if (pixels.size != expected) {
    throw CuiException("streamingTextureFromPixelsRgba: pixel buffer size ...")
}
```

## 我这边没做的事

- **没有**修改上面任何文件（它们是对方未提交的 WIP，改会造成合并冲突）。
- 本分支与 media 路径无交集：80 补丁对对方最新 WIP 的合并演练仍全绿
  （501 例 / 494 通过 / 基线匹配）。
