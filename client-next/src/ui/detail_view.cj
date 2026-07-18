package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.ArchiveMeta

// 档案详情页：meta 未到货时显示加载态，到货后展示完整元数据与操作按钮。
public func detailView(model: AppModel): Unit {
    match (model.meta.value) {
        case None =>
            VStack {
                // hug 须在 padding 前：容器默认 flexible:true，不 hug 会沿父主轴
                // （纵向）拉伸与 Panel 平分高度（同 Task 8 工具条的约束）。
                HStack { Button("← 返回", {=> model.page.value = Page.Library }) }.hug().padding(8.vp)
                Panel { Label("加载中…").muted() }
            }
        case Some(m) => detailBody(model, m)
    }
}

private func detailBody(model: AppModel, m: ArchiveMeta): Unit {
    VStack {
        HStack { Button("← 返回", {=> model.page.value = Page.Library }) }.hug().padding(8.vp)
        ScrollView {
            HStack {
                if (m.coverAssetId > 0) {
                    remoteImage(model, "asset:${m.coverAssetId}", "/api/assets/${m.coverAssetId}",
                        240.vp, 340.vp)
                } else {
                    Panel { Label("无封面").muted() }.width(240.vp).height(340.vp)
                }
                VStack {
                    Label(m.title).fontSize(20.fp).wrap()
                    if (m.description.size > 0) { Label(m.description).muted().wrap() }
                    FlowRow {
                        ForEach(m.tags.toArray(), key: { t: String => t }) { t =>
                            // padding 须在 background 前：Background 只画自身 frame，
                            // 反序会让底色贴死文字、padding 沦为 chip 外的空白。
                            Label(t).padding(8.vp, 2.vp).background(Theme.dark().accent, 6.vp)
                        }
                    }.spacing(6.vp)
                    Label("${m.pagecount} 页 · ${formatSize(m.size)} · 已读 ${m.progress} 页").muted()
                    if (m.archivetype != "image") {
                        Label("该档案类型（${m.archivetype}）暂不支持内置阅读").muted()
                    }
                    HStack {
                        Button(readButtonLabel(m), {=>
                            let start = if (m.progress >= m.pagecount) { 1 } else { m.progress + 1 }
                            model.openReader(m.arcid, start)
                        }).role(ButtonRole.Primary).enabled(m.archivetype == "image" && m.pagecount > 0)
                        Button(if (m.isfavorite) { "取消收藏" } else { "收藏" }, {=>
                            model.toggleFavorite(m.arcid, !m.isfavorite)
                        })
                        Button(if (m.isnew) { "标记为已读" } else { "标记为未读" }, {=>
                            model.toggleIsNew(m.arcid, !m.isnew)
                        })
                    }.spacing(8.vp).hug()
                }.spacing(10.vp).padding(16.vp).flex()
            }.crossAxisAlignment(CrossAxisAlignment.Start)
        }
    }
}

private func readButtonLabel(m: ArchiveMeta): String {
    if (m.progress <= 0) { return "开始阅读" }
    if (m.progress >= m.pagecount) { return "重新阅读" }
    "继续阅读（第 ${m.progress + 1} 页）"
}

private func formatSize(bytes: Int64): String {
    if (bytes >= 1073741824) { return "${bytes / 1048576 / 1024}.${(bytes / 1048576) % 1024 / 100} GB" }
    if (bytes >= 1048576) { return "${bytes / 1048576} MB" }
    if (bytes >= 1024) { return "${bytes / 1024} KB" }
    "${bytes} B"
}
