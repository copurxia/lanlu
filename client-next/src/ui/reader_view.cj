package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.percentEncode

// 阅读器：←/→ 键与滚轮翻页、Esc 返回详情；左侧 200vp 点击区上一页、其余区域下一页。
// 顶部条：返回、页码指示。事件在子树前由 EventHandler 截获（写法参照 examples/command_palette）。
public func readerView(model: AppModel): Unit {
    EventHandler(onEvent: { event =>
        match (event) {
            case UiEvent.KeyDown(Key.Left, false) =>
                model.gotoPage(model.readerIndex.value - 1)
                true
            case UiEvent.KeyDown(Key.Right, false) =>
                model.gotoPage(model.readerIndex.value + 1)
                true
            case UiEvent.KeyDown(Key.Escape, false) =>
                model.openDetail(model.readerArcid)
                true
            case UiEvent.MouseWheel(_, dy, _, _) =>
                if (dy > 0.0) { model.gotoPage(model.readerIndex.value + 1) }
                else if (dy < 0.0) { model.gotoPage(model.readerIndex.value - 1) }
                true
            case _ => false
        }
    }) {
        VStack {
            // hug 须在 padding 前：容器默认 flexible:true，不 hug 会沿父 VStack
            // 主轴（纵向）拉伸挤占页面区（同 Task 8/9 工具条的约束）。
            HStack {
                Button("← 详情", {=> model.openDetail(model.readerArcid) })
                Label("第 ${model.readerIndex.value} / ${model.pages.value.size} 页").muted()
                Spacer()
            }.spacing(12.vp).hug().padding(6.vp)
            readerBody(model)
        }
    }
}

private func readerBody(model: AppModel): Unit {
    let total = model.pages.value.size
    if (total == 0) {
        Panel { Label("加载页列表…").muted() }
        return
    }
    let cur = model.readerIndex.value
    let pid = model.pages.value[cur - 1].id
    let key = "page:${model.readerArcid}:${pid}"
    let url = "/api/archives/${model.readerArcid}/page?path=${percentEncode(pid)}"
    // 首次进入/翻页后请求当前页并预取
    if (model.imageState(key).value == "") {
        model.requestImage(key, url)
        model.prefetchAround()
    }
    // flex 让页面区吃掉顶条之外的剩余高度（ZStack 默认非 flexible，
    // 不加 flex 时 ImageView 自然高只有 preferredHeight 96vp）。
    ZStack {
        // 点击区叠在页面之下：ImageView 不消费事件，落到底层照样翻页；
        // 失败态的重试 ClickArea 在上层才能接到点击（不被翻页区遮蔽）。
        HStack {
            // 透明撑开：Panel 会绘制不透明底色盖住页面，故用 Spacer。
            ClickArea(onClick: {=> model.gotoPage(cur - 1) }) {
                Spacer().width(200.vp).fillHeight()
            }
            // flex 必须落在 HStack 直接子级上（ClickArea 的 ZStack 不透传 flex），
            // 因此用 Flexible 包裹让右区吃掉剩余宽度。
            Flexible {
                ClickArea(onClick: {=> model.gotoPage(cur + 1) }) {
                    Spacer().fillHeight()
                }
            }
        }
        pageImage(model, key, url)
    }.flex()
}

private func pageImage(model: AppModel, key: String, url: String): Unit {
    let st = model.imageState(key)
    if (st.value == "error") {
        ClickArea(onClick: {=> model.retryImage(key, url) }) {
            Panel { Label("加载失败，点击重试").muted() }
        }
    } else if (st.value.startsWith("/")) {
        ImageView(st.value).fit(ImageFit.Contain)
    } else {
        Panel { Label("加载中…").muted() }
    }
}
