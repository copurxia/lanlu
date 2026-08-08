package lanlu_client_next.net

import rocksdb_ffi.{RocksDb, RocksDbOperationResult}
import std.collection.ArrayList
import std.env.getVariable
import std.fs.{exists, Directory, Path}
import std.io.{ByteBuffer, readToEnd}
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.stream.*

// 离线缓存（第二个 RocksDB 实例，独立于设置库）：
// - resp:{serverHash}:{path?query} → {"saved_at":..,"body":..}：GET 响应原始 body 快照，
//   供网络异常时读穿透回退（离线回读走各端点原有解析路径，零新 DTO）。
// - progress:{serverHash}:{arcid} → {"page":N,"queued_at":..}：离线阅读进度队列，
//   服务端恢复后由 model 逐条补报。
// 多服务器靠 serverHash（fnv1a64Hex(baseUrl)，与 defaultCacheRoot 同源）前缀隔离；
// 打开失败降级为不可用（方法全部静默），不阻断启动。

public func defaultOfflineCacheRoot(): String {
    let home = getVariable("HOME") ?? "."
    "${home}/.cache/lanlu-client-next/offline-kv"
}

// 离线回退通知（跨线程安全）：worker 线程 mark 置位（仅方法调用，规避 cjc 1.1.3 的
// GC WriteStaticRef 屏障缺陷——闭包直接写捕获引用字段会 SIGSEGV），UI pump 轮询 take 取走。
public class OfflineNotice {
    private let mutex = Mutex()
    private var pending = false

    public func mark(): Unit {
        synchronized(mutex) {
            pending = true
        }
    }

    // 取走并清除标志；UI 线程调用。
    public func take(): Bool {
        synchronized(mutex) {
            let p = pending
            pending = false
            p
        }
    }
}

public class OfflineCache {
    private let db: RocksDb
    // scan+delete 组合操作加锁；单键 put/get 由 RocksDB C API 保证线程安全。
    private let cacheMutex = Mutex()

    private init(db: RocksDb) {
        this.db = db
    }

    public static func open(path: String): ?OfflineCache {
        try {
            if (!exists(Path(path))) {
                Directory.create(Path(path), recursive: true)
            }
            match (RocksDb.openLowMemory(path)) {
                case (true, Some(db), _) => return Some(OfflineCache(db))
                case (_, _, _) => return None
            }
        } catch (_: Exception) {
            return None
        }
    }

    private func respKey(serverHash: String, path: String): String {
        "resp:${serverHash}:${path}"
    }

    private func progressKey(serverHash: String, arcid: String): String {
        "progress:${serverHash}:${arcid}"
    }

    // 在线请求成功后写入响应快照（原始 body）。写失败静默。
    public func storeResponse(serverHash: String, path: String, body: String): Unit {
        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("saved_at").writeValue(DateTime.now().format("yyyy-MM-dd HH:mm:ss"))
            w.writeName("body").writeValue(body)
            w.endObject()
            w.flush()
            let _ = db.putResult(respKey(serverHash, path), String.fromUtf8(readToEnd(out)))
        } catch (_: Exception) {}
    }

    // 网络异常回退读：命中返回缓存 body，未命中/解析失败返回 None。
    public func getResponse(serverHash: String, path: String): Option<String> {
        try {
            match (db.getResult(respKey(serverHash, path))) {
                case RocksDbOperationResult<String>.Ok(v) =>
                    let body = parseJsonStringField(v, "body", "")
                    if (body.size > 0) {
                        return Some(body)
                    }
                    return None
                case _ => return None
            }
        } catch (_: Exception) {
            return None
        }
    }

    // 进度入队：同一档案后写覆盖（对齐 RN offlineProgressQueue）。
    public func enqueueProgress(serverHash: String, arcid: String, page: Int64): Unit {
        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("page").writeValue(page)
            w.writeName("queued_at").writeValue(DateTime.now().format("yyyy-MM-dd HH:mm:ss"))
            w.endObject()
            w.flush()
            let _ = db.putResult(progressKey(serverHash, arcid), String.fromUtf8(readToEnd(out)))
        } catch (_: Exception) {}
    }

    // 扫描某服务器的全部待补报进度：(arcid, page)。
    public func listProgress(serverHash: String): ArrayList<(String, Int64)> {
        let out = ArrayList<(String, Int64)>()
        let prefix = "progress:${serverHash}:"
        synchronized(cacheMutex) {
            match (db.scanByPrefixResult(prefix)) {
                case RocksDbOperationResult<Array<(String, String)>>.Ok(entries) =>
                    for (e in entries) {
                        let arcid = e[0][prefix.size..e[0].size]
                        if (arcid.size > 0) {
                            out.add((arcid, parseJsonInt64Field(e[1], "page", 0)))
                        }
                    }
                case _ => ()
            }
        }
        out
    }

    // 补报成功后删除队列项。
    public func deleteProgress(serverHash: String, arcid: String): Unit {
        try {
            let _ = db.deleteResult(progressKey(serverHash, arcid))
        } catch (_: Exception) {}
    }

    // 清理某服务器的全部离线数据（响应 + 进度），供“清理图片缓存”入口联动。
    public func clearServer(serverHash: String): Unit {
        let keys = ArrayList<String>()
        synchronized(cacheMutex) {
            for (p in ["resp:${serverHash}:", "progress:${serverHash}:"]) {
                match (db.scanByPrefixResult(p)) {
                    case RocksDbOperationResult<Array<(String, String)>>.Ok(entries) =>
                        for (e in entries) {
                            keys.add(e[0])
                        }
                    case _ => ()
                }
            }
            if (keys.size > 0) {
                let _ = db.deleteManyResult(keys.toArray())
            }
        }
    }

    public func close(): Unit {
        try {
            db.close()
        } catch (_: Exception) {}
    }
}

// ---- JSON 字段快路径（offline 值结构固定，缺失/坏数据回 fallback）----

private func parseJsonStringField(body: String, field: String, fallback: String): String {
    var out = fallback
    var buf = ByteBuffer()
    unsafe { buf.write(body.rawData()) }
    let r = JsonReader(buf)
    try {
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        if (n == field) {
                            out = decodeRaw<String>(r.readValueBytes(), fallback)
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => break
            }
        }
    } catch (_: Exception) {}
    out
}

private func parseJsonInt64Field(body: String, field: String, fallback: Int64): Int64 {
    var out = fallback
    var buf = ByteBuffer()
    unsafe { buf.write(body.rawData()) }
    let r = JsonReader(buf)
    try {
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        if (n == field) {
                            out = decodeRaw<Int64>(r.readValueBytes(), fallback)
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => break
            }
        }
    } catch (_: Exception) {}
    out
}
