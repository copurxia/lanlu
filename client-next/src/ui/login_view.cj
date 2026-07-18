package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*

// 登录页：地址/账号/密码三个输入框 + 连接按钮。
public func loginView(model: AppModel): Unit {
    // rememberState 的初值参数是 () -> T 闭包。
    let url = rememberState<String>("login.url", {=> model.settings.serverUrl})
    let user = rememberState<String>("login.user", {=> model.settings.username})
    let pass = rememberState<String>("login.pass", {=> ""})

    VStack {
        Label("lanlu 桌面客户端").fontSize(24.fp)
        Label("连接到 lanlu 服务器").muted()
        // CUI TextField 暂无 placeholder，用小字 Label 提示字段含义。
        Label("服务器地址，如 http://127.0.0.1:8082").muted()
        TextField(url, key: "login-url").width(360.vp)
        Label("用户名").muted()
        TextField(user, key: "login-user").width(360.vp)
        // CUI 暂无密码掩码输入，v1 明文输入。
        Label("密码（明文显示）").muted()
        TextField(pass, key: "login-pass").width(360.vp)
        Button("连接并登录", {=>
            model.connectAndLogin(url.value.trimAscii(), user.value.trimAscii(), pass.value)
        }).role(ButtonRole.Primary).width(220.vp)
        if (model.loading.value) {
            Label("正在连接…").muted()
        }
    }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Center).padding(40.vp)
}
