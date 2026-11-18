package portcheck

// OHOS 移植自检实现（仅在 OHOS_SELFTEST=1 时由 ohos_entry 调用）。
import std.env.getVariable
import std.fs.{File, Path, exists}
import std.time.MonoTime
import lcodec.{SystemImageDecoder, VipsApi, decodeBytesToRgba, sniffImageFormat, sniffedImageFormatName, decodeFileToRgba}
import qwest.*
import libavformat_ffi.*
import libass_ffi.*
import libvlc_ffi.{VlcPlayer}
import webview.{WebviewSession, HtmlFrame, warmup as wvWarmup}
// 自检图片由本包自带（selftest_asset.cj）

private func decodeMsg(p: String): String {
    let fn = unsafe { LibC.mallocCString(p) }
    let img = VipsApi.imageNewFromFile(fn)
    unsafe { LibC.free(fn) }
    if (img.isNull()) {
        return "FAIL"
    }
    let w = VipsApi.imageWidth(img)
    let h = VipsApi.imageHeight(img)
    var sz: UIntNative = 0
    let mem = unsafe { VipsApi.writeToMemory(img, CPointer<UIntNative>(inout sz)) }
    VipsApi.unref(img)
    VipsApi.free(mem)
    return "w=${w} h=${h} sz=${sz}"
}

func ohosImageSelftest(base: String): Unit {
    try {
        let n = unsafe { LibC.mallocCString("lanlu-selftest") }
        let rc = VipsApi.initialize(n)
        unsafe { LibC.free(n) }
        File.writeTo(Path(base + "/vt.png"), SELFTEST_PNG)
        File.writeTo(Path(base + "/vt.webp"), WEBP_SAMPLE)
        let m1 = decodeMsg(base + "/vt.png")
        let m2 = decodeMsg(base + "/vt.webp")
        // lcodec 存在性 + 诊断能力：嗅探结果写盘（不依赖解码成败）；再用 lcodec 管线解一张 PNG，
        // 失败时异常信息应带 format= 前缀（这是本次统合的核心验收点）。
        var m3 = "n/a"
        try {
            let d = decodeFileToRgba(base + "/vt.png")
            m3 = "lcodec w=${d.width} h=${d.height} sz=${d.size}"
            d.close()
        } catch (e: Exception) {
            m3 = "lcodec " + e.message
        }
        // 字节入口（顶栏/登录卡 logo 用的就是这条）：自检里解同一张 PNG 字节，
        // 真机一眼看出"内存入口/临时文件回退"是否成立。
        var m4 = "n/a"
        try {
            let d = decodeBytesToRgba(SELFTEST_PNG)
            m4 = "bytes w=${d.width} h=${d.height} sz=${d.size}"
            d.close()
        } catch (e: Exception) {
            m4 = "bytes " + e.message
        }
        let sysBytes = if (SystemImageDecoder.available()) {
            if (SystemImageDecoder.bytesSupported()) {
                "CreateFromData ok"
            } else {
                "CreateFromData missing(API<12) -> temp-file fallback"
            }
        } else {
            "system decoder unavailable: " + SystemImageDecoder.unavailableReason()
        }
        let sniffs = "png=" + sniffedImageFormatName(sniffImageFormat(base + "/vt.png")) +
            " webp=" + sniffedImageFormatName(sniffImageFormat(base + "/vt.webp"))
        // 远端格式探测（可选，样本不入库）：从环境变量取 URL → 下载 → lcodec 解码。
        //   LANLU_CODEC_PROBE_URL  → probe1（例如真实 AVIF）
        //   LANLU_CODEC_PROBE2_URL → probe2（例如 JPEG/PNG 封面）
        // 真机命令示例：
        //   aa start ... --ps lanlu.env.OHOS_SELFTEST 1
        //               --ps lanlu.env.LANLU_CODEC_PROBE_URL  http://192.168.0.131:18080/test.avif
        //               --ps lanlu.env.LANLU_CODEC_PROBE2_URL http://192.168.0.131:18080/cover.jpg
        let p1 = probeImageFromEnv(base, "1", "LANLU_CODEC_PROBE_URL")
        let p2 = probeImageFromEnv(base, "2", "LANLU_CODEC_PROBE2_URL")
        // 运行时装载诊断：图片后端是 dlopen 进来的（不参与链接），真机缺库时这里能直接看到原因。
        let backend = if (VipsApi.available()) { "loaded" } else { "unavailable: " + VipsApi.unavailableReason() }
        let report = "rc=${rc}\npng: ${m1}\nwebp: ${m2}\nlcodec: ${m3}\nemb: ${m4}\nsysbytes: ${sysBytes}" +
            "\nprobe1: ${p1}\nprobe2: ${p2}\nsniff: ${sniffs}\nbackend: ${backend}\n"
        File.writeTo(Path(base + "/vipstest.txt"), report.toArray())
    } catch (_) {
    }
}

// 从环境变量取 URL（可选）→ 下载到 $HOME/probe_<tag>.img → 用 lcodec 解码并报告。
private func probeImageFromEnv(base: String, tag: String, envName: String): String {
    match (getVariable(envName)) {
        case Some(url) =>
            let dest = base + "/probe_" + tag + ".img"
            let dl = try {
                let (origin, reqPath) = splitUrl(url)
                let c = ClientBuilder().baseUrl(origin).build()
                let r = c.get(reqPath).send()
                let bytes = r.bytes()
                let st = r.status
                c.close()
                if (st != 200) {
                    return "download status=${st}"
                }
                File.writeTo(Path(dest), bytes)
                "downloaded ${bytes.size}B"
            } catch (e: Exception) {
                return "download FAIL: " + e.message
            }
            try {
                let d = decodeFileToRgba(dest)
                let s = "w=${d.width} h=${d.height} sz=${d.size} fmt=" +
                    sniffedImageFormatName(sniffImageFormat(dest)) + " (" + dl + ")"
                d.close()
                s
            } catch (e: Exception) {
                "FAIL: " + e.message + " [" + dl + "]"
            }
        case None => "absent"
    }
}

// URL → (origin, path)：qwest 的 baseUrl 只接受 origin（scheme://host:port）。
private func splitUrl(url: String): (String, String) {
    let start = match (url.indexOf("://")) {
        case Some(i) => i + 3
        case None => 0
    }
    let rest = url[start..]
    match (rest.indexOf("/")) {
        case Some(i) => (url[0..(start + i)], rest[i..])
        case None => (url, "/")
    }
}

private func httpMsg(url: String, trustAll: Bool): String {
    try {
        var cb = ClientBuilder().baseUrl(url)
        if (trustAll) {
            cb = cb.tlsVerify(TlsVerify.TrustAll)
        }
        let c = cb.build()
        let r = c.get("/").send()
        let body = r.text()
        c.close()
        return "status=${r.status} body=${body}"
    } catch (ex: Exception) {
        return "ERR ${ex}"
    }
}

func ohosNetSelftest(base: String): Unit {
    // 回环目标默认为主机调试地址，可用 OHOS_NET_HOST 覆盖
    let host = getVariable("OHOS_NET_HOST") ?? "192.168.0.131"
    File.writeTo(Path(base + "/net.txt"), httpMsg("http://${host}:18080", false).toArray())
    File.writeTo(Path(base + "/net2.txt"), httpMsg("https://${host}:18443", true).toArray())
}

func ohosMediaSelftest(base: String): Unit {
    try {
        File.writeTo(Path(base + "/mix.mkv"), MIXED_MKV)
        let (r, c, cr, cc) = libavVersions()
        var am = "ver runtime=${r}/${c} compiled=${cr}/${cc}"
        let streams = probeSubtitleStreams(base + "/mix.mkv")
        am += " streams=${streams.size}"
        if (streams.size > 0) {
            am += " first=${streams[0].codecName}"
        }
        File.writeTo(Path(base + "/avtest.txt"), am.toArray())
    } catch (ex2: Exception) {
        File.writeTo(Path(base + "/avtest.txt"), ("EXC " + ex2.message).toArray())
    }
    try {
        File.writeTo(Path(base + "/basic.ass"), BASIC_ASS)
        let amsg = try {
            let rend = AssRenderer(1280, 720)
            let track = rend.readAssDocument(BASIC_ASS)
            let bmp = rend.render(1000, [track])
            let s = "bitmap=${bmp.width}x${bmp.height} at(${bmp.x},${bmp.y}) rgba_bytes=${bmp.rgba.size}"
            track.close()
            rend.close()
            s
        } catch (ex3: Exception) {
            "EXC ${ex3.message}"
        }
        File.writeTo(Path(base + "/asstest.txt"), amsg.toArray())
    } catch (ex4: Exception) {
        File.writeTo(Path(base + "/asstest.txt"), ("EXC " + ex4.message).toArray())
    }
    try {
        File.writeTo(Path(base + "/test.mp4"), TEST_MP4)
        let vmsg = try {
            let player = VlcPlayer()
            player.open(base + "/test.mp4", muted: false)
            var frames = 0
            var lastW: Int32 = 0
            var lastH: Int32 = 0
            let t0 = MonoTime.now()
            while (MonoTime.now() - t0 < Duration.second * 4) {
                let _ = player.timeSec()  // 驱动解码（pull 模型）
                let fr = player.takeFrame()
                if (let Some(f) <- fr) {
                    frames += 1
                    lastW = f.width
                    lastH = f.height
                    if (frames == 1) {
                        // 首帧校验像素非全黑
                        var nonBlack = 0
                        for (i in 0..1000) { if (f.rgba[Int64(i) * 4] > 10) { nonBlack += 1 } }
                        if (nonBlack > 100) { frames += 1000 }  // 标记首帧有效
                    }
                }
                sleep(Duration.millisecond * 30)
            }
            player.seek(6.0)
            var seekTime = 0.0
            let ts = MonoTime.now()
            while (MonoTime.now() - ts < Duration.second * 2) {
                let _ = player.timeSec()
                seekTime = player.timeSec()
                if (seekTime > 5.5) { break }
                sleep(Duration.millisecond * 30)
            }
            let dur = player.durationSec()
            let t = player.timeSec()
            player.stop()
            player.close()
            "frames=${frames} last=${lastW}x${lastH} dur=${dur}s time=${t}s seekTo=${seekTime}s"
        } catch (ex5: Exception) {
            "EXC ${ex5.message}"
        }
        File.writeTo(Path(base + "/vlctest.txt"), vmsg.toArray())
    } catch (ex6: Exception) {
        File.writeTo(Path(base + "/vlctest.txt"), ("EXC " + ex6.message).toArray())
    }
    try {
        let wmsg = try {
            wvWarmup()
            let w = WebviewSession(800, 600, 1.0)
            w.loadHtml("<html><body><h1>Hello Blitz</h1><p>lanlu html reader</p></body></html>".toArray(), "about:blank")
            var fr: ?HtmlFrame = None
            let ts = MonoTime.now()
            while (MonoTime.now() - ts < Duration.second * 3) {
                fr = w.takeFrame()
                match (fr) { case Some(_) => break; case None => () }
                sleep(Duration.millisecond * 30)
            }
            let s = match (fr) {
                case Some(f) => "ok w=${f.width} h=${f.height} rgba=${f.rgba.size}"
                case None => "no frame"
            }
            w.close()
            s
        } catch (ex7: Exception) {
            "EXC ${ex7.message}"
        }
        File.writeTo(Path(base + "/wvtest.txt"), wmsg.toArray())
    } catch (ex8: Exception) {
        File.writeTo(Path(base + "/wvtest.txt"), ("EXC " + ex8.message).toArray())
    }
catch (ex9: Exception) {
        File.writeTo(Path(base + "/inject.txt"), ("EXC " + ex9.message).toArray())
    }
}
