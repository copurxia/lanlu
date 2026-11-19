package lwindow

import lbase.{ClipboardBackend, clipboardBackend}

// OHOS 后端：平台环境准备（对标 Chromium ui/ozone 的 platform_impl）。
// 由 lwindow 的平台选择逻辑在启动时调用；业务层只看到 LWindow.init()。
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path}

func initPlatformOhos(): Unit {
    let base = "/data/storage/el2/base/files"
    setVariable("HOME", base)
    // 剪贴板后端由引擎侧注册（LWindowClipboard -> lw_clipboard.*，M6 第 2 步）。
    // 这里不再安装文件桥后端。
    setVariable("XDG_CONFIG_HOME", base + "/.config")
    setVariable("XDG_DATA_HOME", base + "/.local/share")
    setVariable("XDG_CACHE_HOME", "/data/storage/el2/base/cache")
    // stdx TLS 动态加载系统 openssl（app 命名空间默认搜不到）
    setVariable("STDX_OPENSSL_CRYPTO_FILE", "/system/lib64/platformsdk/libcrypto_openssl.z.so")
    setVariable("STDX_OPENSSL_SSL_FILE", "/system/lib64/platformsdk/libssl_openssl.z.so")
    // Blitz/fontique 经 fontconfig 找字体：写入最小 fonts.conf 并指路（系统层职责）
    try {
        let fc = base + "/fonts.conf"
        File.writeTo(Path(fc), FONTS_CONF_XML.toArray())
        setVariable("FONTCONFIG_FILE", fc)
        setVariable("FONTCONFIG_PATH", base)
    } catch (_) {}
    setVariable("LANLU_VLC_LOG", "/data/storage/el2/base/files/vlclog.txt")
    setVariable("LLASS_LOG_FILE", "/data/storage/el2/base/files/asslog.txt")
    // 调试种子：把预置 KV（联调用 mock 会话）落到应用存储，仅 CN_OHOS_SEED_FILE 构建时非空。
    if (SEED_KV.size > 0) {
        try {
            let kvDir = base + "/.config/lanlu-client-next/kv"
            let kvFile = kvDir + "/lanlu_kv.bin"
            // 仅首次写入：已有 KV（迁移/真实使用产生）绝不覆盖。
            var seeded = true
            try {
                let _ = File.readFrom(Path(kvFile))
            } catch (_) {
                seeded = false
            }
            if (!seeded) {
                Directory.create(Path(kvDir), recursive: true)
                File.writeTo(Path(kvFile), SEED_KV)
            }
        } catch (_) {}
    }
    // 调试后门：只在可调试构建（ArkTS 注入 LANLU_DEBUGGABLE=1，来源 bundleInfo.appInfo.debug）
    // 且显式放行时启用，release 包不再受 lanlu_env.txt 影响（计划 §11 风险记录）。
    if ((getVariable("LANLU_DEBUGGABLE") ?? "0") != "1") {
        return
    }
    // 测试钩子：$HOME/lanlu_env.txt（每行 KEY=VALUE，# 注释）注入进程环境变量。
    // ArkTS 侧无法给应用进程设置环境变量，联调/自动化（如 LANLU_BENCH_*）需要这条通道。
    // 文件不存在即空操作，对正常使用无影响。
    // 优先设备侧可写目录 /data/local/tmp（hdc 可直接投放），其次应用沙箱内。
    // File 没有 exists，用读取失败来区分。
    var envText = ""
    try {
        envText = String.fromUtf8(File.readFrom(Path("/data/local/tmp/lanlu_env.txt")))
    } catch (_) {
        try {
            envText = String.fromUtf8(File.readFrom(Path(base + "/lanlu_env.txt")))
        } catch (_) {}
    }
    if (envText.size > 0) {
        for (line0 in envText.split("\n")) {
            let line = line0.trimAscii()
            if (line.size == 0 || line.startsWith("#")) {
                continue
            }
            match (line.indexOf("=")) {
                case Some(eq) =>
                    if (eq > 0 && eq + 1 < line.size) {
                        setVariable(line[0..eq], line[eq + 1..line.size])
                    }
                case None => ()
            }
        }
    }
}
