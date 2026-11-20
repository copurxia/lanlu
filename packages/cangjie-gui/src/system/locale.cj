package cui.system

import lbase.CuiException

import cui.base.{lastSdlError}
import std.collection.ArrayList
import std.env.getVariable
import std.fs.{File, Path}

/** A language and optional country reported by the operating system, in preference order. */
public struct LocalePreference {
    public let language: String
    public let country: ?String

    public init(language: String, country!: ?String = None) {
        this.language = language
        this.country = country
    }

    /** Returns a BCP-47-like display tag such as `en-US` or `zh`. */
    public func tag(): String {
        match (country) {
            case Some(value) => "${language}-${value}"
            case None => language
        }
    }
}

/** Cross-platform locale queries backed by SDL. */
public class SystemLocales {
    /**
     * Returns the operating system's preferred locales in priority order.
     *
     * Throws `CuiException` when the platform cannot provide locale information.
     */
    public static func preferred(): Array<LocalePreference> {
        // P5：无 SDL —— OHOS 应用默认简体中文环境；如需真实系统语言，
        // 由壳层通过 $HOME/locale.txt 写入（"zh-CN\nen-US" 形式），这里优先读取。
        let fromShell = readShellLocales()
        if (fromShell.size > 0) {
            return fromShell
        }
        [LocalePreference("zh", country: Some("CN"))]
    }
}


/// 壳层可用 $HOME/locale.txt 覆盖系统语言（每行一个 BCP-47 标签）。
private func readShellLocales(): Array<LocalePreference> {
    let home = getVariable("HOME") ?? "."
    let text = try {
        String.fromUtf8(File.readFrom(Path(home + "/locale.txt")))
    } catch (_: Exception) {
        return Array<LocalePreference>()
    }
    let result = ArrayList<LocalePreference>()
    for (line in text.split("\n")) {
        let tag = line.trimAscii()
        if (tag.size == 0) {
            continue
        }
        match (tag.indexOf("-")) {
            case Some(dash) => result.add(LocalePreference(tag[0..dash], country: Some(tag[dash + 1..])))
            case None => result.add(LocalePreference(tag))
        }
    }
    result.toArray()
}
