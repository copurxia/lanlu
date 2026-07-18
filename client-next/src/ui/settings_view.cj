package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*

// 设置页：服务器信息 / 图片缓存 / 账号 / 关于。
public func settingsView(model: AppModel): Unit {
    // 进场加载一次：rememberState 随页面卸载清除（StateStore 未访问条目即删），
    // 故每次进入设置页都会重新拉取；不能用 serverInfo.isNone() 当触发条件——
    // info 失败时 toast 引发重建会反复重投，形成错误循环。
    let loaded = rememberState<Bool>("settings.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadServerInfo()
        model.refreshCacheInfo()
    }
    VStack {
        // 返回条 hug 按内容收缩（容器默认 flexible:true，不 hug 会沿纵轴拉伸，同书库工具条）。
        HStack { Button("← 返回书库", {=> model.page.value = Page.Library }) }.hug().padding(8.vp)
        VStack {
            Panel {
                VStack {
                    Label("服务器").fontSize(18.fp)
                    Label(model.settings.serverUrl).muted()
                    match (model.serverInfo.value) {
                        case Some(info) =>
                            Label("${info.name} · ${info.versionName} ${info.version} · ${info.totalArchives} 个档案").muted()
                        case None => Label("服务器信息加载中…").muted()
                    }
                }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start)
            }
            Panel {
                VStack {
                    Label("缓存").fontSize(18.fp)
                    Label(model.cacheInfo.value).muted()
                    Button("清理图片缓存", {=> model.clearCache() }).role(ButtonRole.Danger)
                }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start)
            }
            Panel {
                VStack {
                    Label("账号").fontSize(18.fp)
                    Label(model.settings.username).muted()
                    Button("退出登录", {=> model.logout() }).role(ButtonRole.Danger)
                }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start)
            }
            Label("lanlu 桌面客户端 v0.1.0 · CangjieGUI").muted()
            // 外层跨轴保持默认 Stretch 让 Panel 通栏；各 Panel 内部 VStack 用 Start
            // 让按钮保持自然宽度（跨轴 Stretch 会把按钮拉满整行，同书库卡片的处理）。
        }.spacing(12.vp).padding(16.vp)
    }
}
