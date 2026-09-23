package qwest

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.time.MonoTime

// keep-alive 连接池：每 (scheme,host,port) 一个空闲栈（后进先出，优先复用最热连接）。
// 只存空闲连接；在途连接由 Response 生命周期管理，读尽后归还。
class ConnectionPool {
    private let mutex = Mutex()
    private let idle = HashMap<String, ArrayList<Connection>>()
    private let maxIdlePerHost: Int64
    private let idleTtl: Duration
    private var closed = false

    init(maxIdlePerHost: Int64, idleTtl: Duration) {
        this.maxIdlePerHost = maxIdlePerHost
        this.idleTtl = idleTtl
    }

    // 取一条未过期的空闲连接；过期的顺手关掉。
    func take(key: String): ?Connection {
        let expired = ArrayList<Connection>()
        let picked: ?Connection = synchronized(mutex) {
            if (closed) {
                return None
            }
            match (idle.get(key)) {
                case Some(list) =>
                    var found: ?Connection = None
                    while (list.size > 0) {
                        let c = list.remove(at: list.size - 1)
                        if (MonoTime.now() - c.idleSince > idleTtl) {
                            expired.add(c)
                            continue
                        }
                        found = Some(c)
                        break
                    }
                    found
                case None => None
            }
        }
        // 关 socket 可能阻塞，放到锁外。
        for (c in expired) {
            c.close()
        }
        picked
    }

    // 归还连接；池满/已关闭/连接坏了则直接关闭。
    func give(conn: Connection): Unit {
        if (conn.broken || conn.isClosed()) {
            conn.close()
            return
        }
        let accepted = synchronized(mutex) {
            if (closed) {
                false
            } else {
                let list = match (idle.get(conn.key)) {
                    case Some(l) => l
                    case None =>
                        let l = ArrayList<Connection>()
                        idle.add(conn.key, l)
                        l
                }
                if (list.size >= maxIdlePerHost) {
                    false
                } else {
                    conn.idleSince = MonoTime.now()
                    list.add(conn)
                    true
                }
            }
        }
        if (!accepted) {
            conn.close()
        }
    }

    // 关闭全部空闲连接；此后 take 恒空、give 直接关连接。
    func closeAll(): Unit {
        let toClose = ArrayList<Connection>()
        synchronized(mutex) {
            closed = true
            for ((_, list) in idle) {
                for (c in list) {
                    toClose.add(c)
                }
            }
            idle.clear()
        }
        for (c in toClose) {
            c.close()
        }
    }
}
