package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*

// 阅读页（T2 重写）：舞台 + 底部 dock 的组合壳。
// - 方向键 ←/→/↑/↓ 映射为 KeyCode 走 model.readerKeyTurn（LTR/RTL/TTB 换算与
//   webtoon 豁免全在 ReaderModel.keyDirection，视图不再硬编码 ±1）；Esc 返回详情，
//   但页面导航/阅读设置抽屉开着时先关抽屉（抽屉是 overlay，Esc 本由 Drawer 在事件
//   落树前消费并 onDismiss，这里的判断是兜底：overlay 未注册的瞬间也保持语义一致）。
// - 滚轮：不在这里消费，放行给 ReaderStage——长图模式先滚图、到边缘再翻页；
//   webtoon 在单一纵向内容面内连续滚动并按可见位置同步页码；其余模式 spread 步进。
// - 点击区：左 30% 上一页 / 中央 40% 显隐 chrome / 右 30% 下一页（原型 30/40/30）；
//   tapTurnPage == false 时左右两区不挂（中央显隐恒在）。双击缩放与失败重试在
//   ReaderStage 自身 handle 里（cui clickCount 判定，见 reader_stage.cj）。
// - 舞台为自绘 ReaderStage（双页/翻页动画/音频舞台/媒体信息浮层），dock 为底部
//   lane 胶囊（reader_dock.cj），随 chrome 显隐滑动——顶栏显隐由 main.cj 不渲染实现，
//   dock 在视图内部叠层实现（不进 main.cj）。
// 任何鼠标移动/按键/滚轮都经 noteReaderActivity 刷新 chrome 自动隐藏计时。
// 事件在子树前由 EventHandler 截获（写法参照 examples/command_palette）。
public func readerView(model: AppModel): Unit {
    // 订阅 ReaderModel 非 State 变更（mode/spread/lane 等），再读 reader.* 普通属性。
    let _ = model.readerVersion.value
    EventHandler(onEvent: { event =>
        match (event) {
            case UiEvent.KeyDown(Key.Left, false) =>
                model.noteReaderActivity()
                model.readerKeyTurn(KeyCode.KeyLeft)
                true
            case UiEvent.KeyDown(Key.Right, false) =>
                model.noteReaderActivity()
                model.readerKeyTurn(KeyCode.KeyRight)
                true
            case UiEvent.KeyDown(Key.Up, false) =>
                model.noteReaderActivity()
                model.readerKeyTurn(KeyCode.KeyUp)
                true
            case UiEvent.KeyDown(Key.Down, false) =>
                model.noteReaderActivity()
                model.readerKeyTurn(KeyCode.KeyDown)
                true
            // PgDn/PgUp（SDL scancode 78/75，Key 枚举未收录走 RawScancode）与空格：
            // html 页页内翻滚；非 html 页不消费（方向键翻页不受影响）。
            case UiEvent.KeyDown(Key.RawScancode(78), false) =>
                model.noteReaderActivity()
                model.readerHtmlPageTurn(down: true)
            case UiEvent.KeyDown(Key.RawScancode(75), false) =>
                model.noteReaderActivity()
                model.readerHtmlPageTurn(down: false)
            case UiEvent.KeyDown(Key.Space, false) =>
                model.noteReaderActivity()
                model.readerHtmlPageTurn(down: true)
            case UiEvent.KeyDown(Key.Escape, false) =>
                // 抽屉开着先关抽屉（互斥，两个都关一遍无副作用），否则返回详情。
                if (model.readerSettingsOpen.value || model.readerSidebarOpen.value) {
                    model.closeReaderPanels()
                } else {
                    model.openDetail(model.readerArcid)
                }
                true
            case UiEvent.MouseWheel(_, _, _, _) =>
                // 不消费：滚轮语义在 ReaderStage（长图先滚图、边缘翻页、webtoon 连续滚动），
                // 这里只刷新自动隐藏计时并放行（事件会落到舞台 handle）。
                model.noteReaderActivity()
                false
            case UiEvent.MouseMove(_, _) =>
                // 不消费：hover 态还要落到底下各控件；仅刷新自动隐藏计时。
                model.noteReaderActivity()
                false
            case _ => false
        }
    }) {
        // 抽屉挂阅读页根部：不占布局空间（Drawer 经 overlay 自锚定视口边缘），
        // 且页面区叠在顶栏浮层之下恒吃满全高（main.cj ZStack 方案 b）。
        ZStack {
            readerBody(model)
            readerSidebarDrawer(model)
            readerSettingsDrawer(model)
        }
    }
}

private func readerBody(model: AppModel): Unit {
    if (model.pages.value.size == 0) {
        Panel { Label(model.t("reader.loadingPages")).muted() }
        return
    }
    // chrome 可见时，内容区预留顶栏高度（52vp），避免舞台内容被顶栏遮挡。
    // 顶栏是 ZStack 浮层，不占布局空间；这里用固定 padding 把内容区下推。
    // padding 在 chrome 切换时瞬间生效（不参与顶栏 Spring 动画），避免逐帧重排。
    let topPad = if (model.reader.chromeVisible) {
        Float32(READER_BAR_HEIGHT)
    } else {
        0.0f32
    }
    // frontend 的条漫模式不响应边缘点击翻页；否则透明点击层会在滚动面下方仍把
    // 单击解释成上一/下一页，破坏连续滚动位置。
    let tapTurns = model.reader.tapTurnPage && match (model.reader.mode) {
        case ReadingMode.Webtoon => false
        case _ => true
    }
    ZStack {
        // 点击区叠在舞台之下：舞台自绘不消费翻页语义的点击（失败重试/双击缩放/
        // 音频控制除外，见 ReaderStage.handle），落到底层照样触发。
        HStack {
            // flex 必须落在 HStack 直接子级上（ClickArea 的 ZStack 不透传 flex），
            // 因此用 Flexible(weight:) 包裹分配比例。
            if (tapTurns) {
                Flexible(weight: 3.0) {
                    ClickArea(onClick: {=> model.readerTurnPage(false) }) {
                        // 透明撑开：Panel 会绘制不透明底色盖住页面，故用 Spacer。
                        Spacer().fillHeight()
                    }
                }
            }
            Flexible(weight: if (tapTurns) { 4.0 } else { 10.0 }) {
                // 中央点击：autoHide 开启时切换 chrome 显隐（标准阅读器交互）；autoHide
                // 关闭时不应隐藏 chrome——用户没开自动隐藏就是期望 chrome 始终可见，
                // 否则任何点击（占 100% 宽度）都会误藏 chrome 且移动鼠标无法恢复。
                ClickArea(onClick: {=>
                    if (model.reader.autoHide) {
                        model.toggleReaderChrome()
                    }
                }) {
                    Spacer().fillHeight()
                }
            }
            if (tapTurns) {
                Flexible(weight: 3.0) {
                    ClickArea(onClick: {=> model.readerTurnPage(true) }) {
                        Spacer().fillHeight()
                    }
                }
            }
        }
        // 舞台：图片 spread（含翻页动画/双击缩放）/音频舞台/类型占位 + 媒体信息浮层。
        ReaderStage(model)
        // 底部 lane 胶囊：随 chrome 显隐（Spring 滑出/淡出在 dock 内部）。
        readerDock(model)
    }.flex().padding(0.0, topPad, 0.0, 0.0)
}
