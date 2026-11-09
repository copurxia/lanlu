package portcheck

// 移植自检入口（跨平台）：OHOS_SELFTEST=1 时执行，结果写入 HOME 下文本文件，
// 便于 `hdc file recv` 取回核对。桌面构建默认关闭，行为与之前一致。
import std.env.getVariable
import std.fs.{File, Path}
import libavformat_ffi.probeSubtitleStreams
import sdl.input.Clipboard

public func enabled(): Bool {
    (getVariable("OHOS_SELFTEST") ?? "0") == "1"
}

// 媒体探测自检：LANLU_PROBE_URL=<url> 时用 libavformat 探测该 URL（支持 http），
// 结果写入 $HOME/probe.txt 便于 hdc 取回。用于验证自造样片/线上片源是否可解。
func runProbeIfRequested(): Unit {
    let url = getVariable("LANLU_PROBE_URL") ?? ""
    if (url.size == 0) {
        return
    }
    let base = getVariable("HOME") ?? "."
    var out = "url=" + url + "\n"
    try {
        let streams = probeSubtitleStreams(url)
        out += "streams=" + streams.size.toString() + "\n"
        for (s in streams) {
            out += "  idx=" + s.streamIndex.toString() + " codec=" + s.codecName +
                " lang=" + s.language + " title=" + s.title + "\n"
        }
    } catch (e: Exception) {
        out += "probe failed: " + e.toString() + "\n"
    }
    try {
        File.writeTo(Path(base + "/probe.txt"), out.toArray())
    } catch (_) {}
}

// 剪贴板自检：LANLU_PROBE_CLIPBOARD=1 时写入一段文本再读回，结果落 $HOME/clipboard.txt。
// 用于确认真机上 SDL 剪贴板后端（OHOS pasteboard）是否可用——复制/粘贴是阅读器的基础能力。
public func runClipboardProbeIfRequested(): Unit {
    if ((getVariable("LANLU_PROBE_CLIPBOARD") ?? "0") != "1") {
        return
    }
    let base = getVariable("HOME") ?? "."
    var out = ""
    let want = "lanlu-clip-ok"
    try {
        Clipboard.setText(want)
        let got = Clipboard.getText()
        out = "set=" + want + "\ngot=" + got + "\nmatch=" + (got == want).toString() + "\n" +
            "hasText=" + Clipboard.hasText().toString() + "\n"
    } catch (e: Exception) {
        out = "clipboard failed: " + e.toString() + "\n"
    }
    try {
        File.writeTo(Path(base + "/clipboard.txt"), out.toArray())
    } catch (_) {}
}

public func runIfEnabled(): Unit {
    runProbeIfRequested();
    runClipboardProbeIfRequested();
    if (!enabled()) {
        return
    }
    let base = getVariable("HOME") ?? "."
    ohosImageSelftest(base)
    ohosNetSelftest(base)
    ohosMediaSelftest(base)
}
