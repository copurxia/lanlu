package lanlu_client_next

// OHOS 入口：由 SDL3 libmain 的 SDL_main 经 Cangjie runtime 加载后调用。
// 仅做平台环境准备，然后复用与应用入口完全相同的 runApp()——
// 本文件在 Linux/Windows 构建中同样参与编译（@C 导出未被调用，无副作用）。
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path}
import lanlu_client_next.ui.EMBEDDED_LOGO_PNG

@C
public func cj_app_main(): Int64 {
    let base = "/data/storage/el2/base/files"
    setVariable("HOME", base)
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
            Directory.create(Path(kvDir), recursive: true)
            File.writeTo(Path(kvDir + "/lanlu_kv.bin"), SEED_KV)
        } catch (_) {}
    }
    // 移植自检（图片/网络/字幕 probe），仅在显式开启时执行
    if ((getVariable("OHOS_SELFTEST") ?? "0") == "1") {
        ohosSelftest(base)
    }
    return runApp()
}

// 移植自检：解码内嵌 PNG/WebP、HTTP/HTTPS 回环、mkv 字幕探测、ASS 渲染。
// 结果写入应用 files 目录（vipstest.txt/net.txt/net2.txt/avtest.txt/asstest.txt）。
func ohosSelftest(base: String): Unit {
    ohosImageSelftest(base)
    ohosNetSelftest(base)
    ohosMediaSelftest(base)
}
