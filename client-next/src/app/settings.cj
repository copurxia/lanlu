package lanlu_client_next.app

import lanlu_client_next.net.JsonCodec
import std.env.getVariable
import std.fs.{exists, rename, File, Directory, Path}
import std.io.{ByteBuffer, readToEnd}
import std.overflow.*
import stdx.encoding.json.stream.*

public class AppSettings <: JsonSerializable & JsonDeserializable<AppSettings> {
    public var serverUrl: String = ""
    public var token: String = ""
    public var username: String = ""

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("serverUrl").writeValue(serverUrl)
        w.writeName("token").writeValue(token)
        w.writeName("username").writeValue(username)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): AppSettings {
        let res = AppSettings()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "serverUrl" => res.serverUrl = r.readValue<String>()
                            case "token" => res.token = r.readValue<String>()
                            case "username" => res.username = r.readValue<String>()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid settings json")
            }
        }
        return res
    }
}

public func defaultSettingsPath(): String {
    let home = getVariable("HOME") ?? "."
    "${home}/.config/lanlu-client-next/config.json"
}

public func loadSettingsFrom(path: String): AppSettings {
    if (!exists(Path(path))) { return AppSettings() }
    try {
        JsonCodec.decode<AppSettings>(String.fromUtf8(File.readFrom(Path(path))))
    } catch (_: Exception) {
        try { rename(Path(path), to: Path("${path}.bak"), overwrite: true) } catch (_: Exception) {}
        AppSettings()
    }
}

public func saveSettingsTo(path: String, s: AppSettings): Unit {
    let p = Path(path)
    // cjc 1.1.3 的 Directory.create 对空路径和已存在目录都会抛异常，先做两道判断。
    let parent = p.parent
    if (!parent.toString().isEmpty() && !exists(parent)) {
        Directory.create(parent, recursive: true)
    }
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.writeValue(s)
    w.flush()
    File.writeTo(p, readToEnd(out))
}

// 服务器地址 → 稳定的短目录名（区分多服务器缓存）。
// FNV-1a 需要环绕乘法：仓颉整数运算默认溢出抛异常，且 cjc 1.1.3 没有 `*!` 运算符，
// 用 std.overflow 的 wrappingMul（截断高位，等同 C 无符号溢出行为）。
public func fnv1a64Hex(s: String): String {
    var hash: UInt64 = 0xcbf29ce484222325
    for (b in s.toArray()) {
        hash = hash ^ UInt64(b)
        hash = hash.wrappingMul(0x100000001b3)
    }
    let digits = "0123456789abcdef".toArray()
    let out = Array<UInt8>(16, repeat: 0)
    var v = hash
    for (i in 0..16) {
        out[15 - i] = digits[Int64(v & 0xF)]
        v = v >> 4
    }
    String.fromUtf8(out)
}

public func defaultCacheRoot(serverUrl: String): String {
    let home = getVariable("HOME") ?? "."
    "${home}/.cache/lanlu-client-next/${fnv1a64Hex(serverUrl)}"
}
