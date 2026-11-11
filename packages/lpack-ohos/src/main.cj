package ohos

import std.fs.*
import std.process.*
import std.env.*

var gOut: String = ""

func rd(p: String): String {
    return String.fromUtf8(File.readFrom(Path(p)))
}

func parentDir(rel: String): String {
    let parts = rel.split("/")
    var pr = gOut
    if (parts.size <= 1) { return pr }
    var i = 0
    while (i < parts.size - 1) {
        pr = pr + "/" + parts[i]
        i = i + 1
    }
    return pr
}

func writeOut(rel: String, content: String): Unit {
    let dir = parentDir(rel)
    if (!exists(Path(dir))) {
        Directory.create(Path(dir), recursive: true)
    }
    File.writeTo(Path(gOut + "/" + rel), content.toArray())
}

func meta(toml: String, sec: String, key: String): String {
    var cur = ""
    var res = ""
    for (line in toml.split("\n")) {
        var raw = line
        match (raw.indexOf("#")) {
            case Some(i) => raw = raw[0..i]
            case None => ()
        }
        let t = raw.trimAscii()
        if (t.size > 0) {
            if (t.startsWith("[")) {
                cur = t
            } else if (cur == sec) {
                let eq = t.split("=")
                if (eq.size >= 2 && eq[0].trimAscii() == key) {
                    var v = eq[1].trimAscii()
                    v = v.replace("\"", "").replace("[", "").replace("]", "")
                    res = v.trimAscii()
                }
            }
        }
    }
    return res
}

func opt(toml: String, sec: String, key: String, dflt: String): String {
    let v = meta(toml, sec, key)
    if (v.size == 0) { return dflt }
    return v
}


// ── app profile（lpack-ohos/app-profiles/<app>/app.toml，计划 §4.3）───────────
// 应用元数据的唯一来源。数组支持单行或跨行；# 之后视为注释。
func arrayOf(toml: String, sec: String, key: String): String {
    var cur = ""
    var buf = ""
    var collecting = false
    for (line in toml.split("\n")) {
        var t = line
        match (t.indexOf("#")) {
            case Some(i) => t = t[0..i]
            case None => ()
        }
        t = t.trimAscii()
        if (t.size == 0) { continue }
        if (t.startsWith("[")) {
            cur = t
            continue
        }
        if (collecting) {
            buf = buf + " " + t
            if (t.contains("]")) { break }
            continue
        }
        if (cur == sec && (t.startsWith(key + " ") || t.startsWith(key + "="))) {
            match (t.indexOf("=")) {
                case Some(i) =>
                    let rest = t[i + 1..].trimAscii()
                    if (rest.startsWith("[")) {
                        buf = rest
                        if (rest.contains("]")) { break }
                        collecting = true
                    }
                case None => ()
            }
        }
    }
    return buf.replace("[", "").replace("]", "").replace("\"", "").trimAscii()
}

// 优先 profile，其次 cjpm.toml 的 [package.metadata.ohos]（兼容旧构建）。
func pick(profile: String, toml: String, key: String, dflt: String): String {
    if (profile.size > 0) {
        let v = meta(profile, "[app]", key)
        if (v.size > 0) { return v }
    }
    return opt(toml, "[package.metadata.ohos]", key, dflt)
}

func pickArray(profile: String, toml: String, key: String): String {
    if (profile.size > 0) {
        return arrayOf(profile, "[app]", key)
    }
    return ""
}

func quotedList(raw: String): String {
    var out = ""
    for (x in raw.split(",")) {
        let v = x.trimAscii()
        if (v.size > 0) {
            if (out.size > 0) { out = out + ", " }
            out = out + "\"" + v + "\""
        }
    }
    return out
}

func permJson(raw: String): String {
    let parts = raw.split(",")
    var count = 0
    for (x in parts) {
        if (x.trimAscii().size > 0) { count = count + 1 }
    }
    var out = ""
    var idx = 0
    for (x in parts) {
        let v = x.trimAscii()
        if (v.size == 0) { continue }
        idx = idx + 1
        out = out + "      { \"name\": \"" + v + "\" }"
        if (idx < count) { out = out + "," }
        out = out + "\n"
    }
    return out
}

func sh(cmd: String): Int64 {
    return execute("bash", ["-c", cmd], stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
}

main(args: Array<String>): Int64 {
    var sign = false
    for (a in args) { if (a == "--sign") { sign = true } }

    let toml = rd("cjpm.toml")
    // 应用元数据：优先 OHOS_APP_PROFILE 指向的 app.toml；缺省回退 cjpm.toml（兼容旧构建）
    var profile = ""
    match (getVariable("OHOS_APP_PROFILE")) {
        case Some(v) =>
            if (exists(Path(v))) {
                profile = rd(v)
            } else {
                eprintln("[hapgen] WARN: OHOS_APP_PROFILE 不存在，回退 cjpm.toml 元数据: " + v)
            }
        case None => ()
    }
    let pkgName = opt(toml, "[package]", "name", "app")
    let bundle = pick(profile, toml, "bundle-name", "com.example." + pkgName)
    let appName = pick(profile, toml, "app-name", pkgName)
    let vcode = pick(profile, toml, "version-code", "1000000")
    let apiLevel = pick(profile, toml, "api-level", "26")
    let apiVer = apiLevel + ".0.0"
    let shim = pick(profile, toml, "shim-module", pkgName + "_shim")
    let engine = pkgName
    var ui = pick(profile, toml, "ui", "xcomponent")
    match (getVariable("OHOS_UI")) {
        case Some(v) => if (v.size > 0) { ui = v }
        case None => ()
    }
    var lgpuLib = ""
    match (getVariable("OHOS_LGPU_LIB")) {
        case Some(v) => lgpuLib = v
        case None => ()
    }
    var lwpInclude = ""
    match (getVariable("OHOS_LWP_INCLUDE")) {
        case Some(v) => lwpInclude = v
        case None => ()
    }
    var sdl3Prefix = ""
    match (getVariable("OHOS_SDL3_PREFIX")) {
        case Some(v) => sdl3Prefix = v
        case None => ()
    }
    var devicesRaw = pickArray(profile, toml, "device-types")
    if (devicesRaw.size == 0) {
        devicesRaw = opt(toml, "[package.metadata.ohos]", "device-types", "phone")
    }
    let permissions = pickArray(profile, toml, "permissions")
    let querySchemes = pickArray(profile, toml, "query-schemes")
    var devices = ""
    for (d in devicesRaw.split(",")) {
        let x = d.trimAscii()
        if (x.size > 0) {
            if (devices.size > 0) { devices = devices + ", " }
            devices = devices + "\"" + x + "\""
        }
    }

    let tplRoot = getVariable("OHOS_TEMPLATES").getOrThrow()
    let assetsDir = getVariable("OHOS_ASSETS").getOrThrow()
    let cangjieHome = getVariable("CANGJIE_HOME").getOrThrow()
    let libcxx = getVariable("OHOS_LIBCXX").getOrThrow()
    let tplRootSdl3 = tplRoot + "_sdl3"

    gOut = "target/ohos/hap"
    sh("pkill -9 -f daemon-process-boot-script.js 2>/dev/null || true; pkill -9 -f hvigor-java-daemon.jar 2>/dev/null || true; sleep 1; rm -rf " + gOut + " 2>/dev/null || mv " + gOut + " /tmp/oldhap.$ 2>/dev/null || true")
    if (!exists(Path(gOut))) { Directory.create(Path(gOut), recursive: true) }

    let baseRels = [
        "AppScope/app.json5",
        "AppScope/resources/base/element/string.json",
        "AppScope/resources/base/media/layered_image.json",
        "build-profile.json5",
        "oh-package.json5",
        "hvigorfile.ts",
        "hvigor/hvigor-config.json5",
        "entry/build-profile.json5",
        "entry/hvigorfile.ts",
        "entry/obfuscation-rules.txt",
        "entry/oh-package.json5",
        "entry/src/main/module.json5",
        "entry/src/main/ets/entryability/EntryAbility.ets",
        "entry/src/main/ets/entrybackupability/EntryBackupAbility.ets",
        "entry/src/main/ets/pages/Index.ets",
        "entry/src/main/resources/base/element/color.json",
        "entry/src/main/resources/base/element/float.json",
        "entry/src/main/resources/base/element/string.json",
        "entry/src/main/resources/base/profile/backup_config.json",
        "entry/src/main/resources/base/profile/main_pages.json",
        "entry/src/main/resources/base/media/layered_image.json",
        "entry/src/main/resources/dark/element/color.json",
        "entry/src/main/cpp/napi_init.cpp",
        "entry/src/main/cpp/CMakeLists.txt",
        "entry/src/main/cpp/types/lib__SHIM__/Index.d.ts",
        "entry/src/main/cpp/types/lib__SHIM__/oh-package.json5"
    ]
    var rels = baseRels
    if (ui == "sdl3") {
        rels = [
        "AppScope/app.json5",
        "AppScope/resources/base/element/string.json",
        "AppScope/resources/base/media/layered_image.json",
        "build-profile.json5",
        "oh-package.json5",
        "hvigorfile.ts",
        "hvigor/hvigor-config.json5",
        "entry/build-profile.json5",
        "entry/hvigorfile.ts",
        "entry/obfuscation-rules.txt",
        "entry/oh-package.json5",
        "entry/src/main/module.json5",
        "entry/src/main/ets/entryability/EntryAbility.ets",
        "entry/src/main/ets/entrybackupability/EntryBackupAbility.ets",
        "entry/src/main/ets/pages/Index.ets",
        "entry/src/main/resources/base/element/color.json",
        "entry/src/main/resources/base/element/float.json",
        "entry/src/main/resources/base/element/string.json",
        "entry/src/main/resources/base/profile/backup_config.json",
        "entry/src/main/resources/base/profile/main_pages.json",
        "entry/src/main/resources/base/media/layered_image.json",
        "entry/src/main/resources/dark/element/color.json",
        "entry/src/main/cpp/CMakeLists.txt",
        "entry/src/main/cpp/input_filter.cpp",
        "entry/src/main/cpp/shell_napi.cpp",
        "entry/src/main/cpp/lwp_client.cpp",
        "entry/src/main/cpp/lwp_window.cpp",
        "entry/src/main/cpp/types/libmain/Index.d.ts",
        "entry/src/main/cpp/types/libmain/oh-package.json5",
        "entry/src/main/cpp/types/libSDL3/Index.d.ts",
        "entry/src/main/cpp/types/libSDL3/oh-package.json5"
        ]
    }
    for (rel in rels) {
        var srcPath = tplRoot + "/" + rel
        if (ui == "sdl3" && exists(Path(tplRootSdl3 + "/" + rel))) {
            srcPath = tplRootSdl3 + "/" + rel
        }
        var c = rd(srcPath)
        c = c.replace("__BUNDLE__", bundle)
        c = c.replace("__APP__", appName)
        c = c.replace("__SHIM__", shim)
        c = c.replace("__ENGINE__", engine)
        c = c.replace("__VCODE__", vcode)
        c = c.replace("__API_VER__", apiVer)
        c = c.replace("__DEVICES__", devices)
        c = c.replace("__SDL3_PREFIX__", sdl3Prefix)
        c = c.replace("__PERMISSIONS__", permJson(permissions))
        c = c.replace("__QUERY_SCHEMES__", quotedList(querySchemes))
        c = c.replace("__LGPU_LIB__", lgpuLib)
        c = c.replace("__LWP_INCLUDE__", lwpInclude)
        writeOut(rel.replace("__SHIM__", shim), c)
    }

    // pngs
    sh("mkdir -p " + gOut + "/entry/src/main/resources/base/media " + gOut + "/AppScope/resources/base/media")
    sh("cp " + assetsDir + "/startIcon.png " + gOut + "/entry/src/main/resources/base/media/startIcon.png")
    sh("cp " + assetsDir + "/background.png " + gOut + "/entry/src/main/resources/base/media/background.png")
    sh("cp " + assetsDir + "/foreground.png " + gOut + "/entry/src/main/resources/base/media/foreground.png")
    sh("cp " + assetsDir + "/background.png " + gOut + "/AppScope/resources/base/media/background.png")
    sh("cp " + assetsDir + "/foreground.png " + gOut + "/AppScope/resources/base/media/foreground.png")

    // libs: engine + cangjie runtime + libc++
    let engineSo = "target/aarch64-linux-ohos/release/" + pkgName + "/lib" + pkgName + ".so"
    sh("mkdir -p " + gOut + "/entry/libs/arm64-v8a")
    sh("cp " + engineSo + " " + gOut + "/entry/libs/arm64-v8a/lib" + engine + ".so")
    sh("cp " + cangjieHome + "/runtime/lib/linux_ohos_aarch64_cjnative/*.so " + gOut + "/entry/libs/arm64-v8a/")
    sh("cp " + libcxx + " " + gOut + "/entry/libs/arm64-v8a/libc++.so")
    // bundle extra shared libs (e.g. SDL3, SDL3_ttf, vips ...) into the HAP
    match (getVariable("OHOS_EXTRA_LIBS")) {
        case Some(v) =>
            for (d in v.split(":")) {
                let dd = d.trimAscii()
                if (dd.size > 0) {
                    sh("cp -a " + dd + "/*.so* " + gOut + "/entry/libs/arm64-v8a/ 2>/dev/null || true")
                }
            }
        case None => ()
    }
    if (ui == "sdl3" && sdl3Prefix.size > 0) {
        sh("cp -a " + sdl3Prefix + "/lib/*.so* " + gOut + "/entry/libs/arm64-v8a/ 2>/dev/null || true")
    }
    // 打包卫生：
    // 1) 依赖库常同时存在 foo.so（链接别名）与 foo.so.N（SONAME 实体），内容相同——
    //    运行时只需要实体，别名会让 HAP 无谓翻倍。
    // 2) 单元测试框架与生产无关。
    // 3) 剥离调试信息（只动 HAP 里的副本，不碰工具链/SDK 目录）。
    let libs = gOut + "/entry/libs/arm64-v8a"
    // 依赖库归一化到 SONAME：加载器只认 NEEDED 里的 SONAME，而 cp -a 会把链接名
    // （foo.so）和版本名（foo.so.N.M）一起带进来——同名内容重复浪费体积，还可能
    // 触发 hvigor 重复文件检查。这里对每个库只保留其 SONAME 命名的一份。
    // 注意：不能简单删符号链接——例如 SDL3 的 SONAME 是 libSDL3.so.0，链接名
    // libSDL3.so 并不是加载器要找的名字。
    sh("cd " + libs + " && sn=\$(ls *.so *.so.* 2>/dev/null); for f in \$sn; do [ -f \"\$f\" ] || continue; soname=\$(readelf -d \"\$f\" 2>/dev/null | grep SONAME | awk '{print \$NF}' | tr -d '[]' | head -1); [ -n \"\$soname\" ] || continue; if [ \"\$f\" = \"\$soname\" ]; then continue; fi; if [ ! -f \"\$soname\" ] || [ -L \"\$soname\" ]; then rm -f \"\$soname\"; cp -f \"\$f\" \"\$soname\"; fi; rm -f \"\$f\"; done")
    // libSDL3.so.0 已无人依赖（依赖名统一为 libSDL3.so），删掉避免冗余
    sh("if [ -f " + libs + "/libSDL3.so ]; then rm -f " + libs + "/libSDL3.so.0; fi")
    sh("rm -f " + libs + "/libcangjie-std-unittest*.so")
    match (getVariable("OHOS_STRIP")) {
        case Some(strip) =>
            if (strip.size > 0) {
                sh(strip + " --strip-unneeded " + libs + "/*.so " + libs + "/*.so.* 2>/dev/null || true")
            }
        case None => ()
    }



    // build
    if (sign) {
        sh("cd " + gOut + " && ( unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy ALL_PROXY all_proxy; export no_proxy='*' NO_PROXY='*'; devecocli signature generate --product default --type debug )")
    }
    let rc = sh("cd " + gOut + " && devecocli build --assemble-type assembleHap")
    sh("ls -la " + gOut + "/entry/build/default/outputs/default/*.hap")
    return rc
}
