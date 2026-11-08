package postgresql_driver

import std.collection.*

/**
 * 单条池化 PGconn 的驱动侧状态：语句缓存 + 参数 arena + 二进制结果模式。
 *
 * 挂接方式：PGDatabase 用 HashMap<指针键, PGConnState> 保存（借出时取/建，归还时保留——
 * 缓存与 arena 都随连接存活，连接销毁时清理）。
 * 指针键：CPointer 无 ==/hash，用连接在池中的序号（borrow 顺序）不可行——改用
 * CPointer<Int64> 槽位分配：每条连接首次借出时分配一个自增 id，id -> state。
 * 连接 id 经 ThreadLocal/借出路径传递，见 PGDatabase.connStates。
 */
class PGConnState {
    let stmtCache: StmtCache
    let arena = ParamArena()
    let binaryResult: Bool   // 该连接是否启用二进制结果协议（auto/always/never 已在解析期归一化为 bool + 运行时白名单判定）

    init(stmtCacheCapacity: Int64, binaryResult: Bool) {
        this.stmtCache = StmtCache(capacity: stmtCacheCapacity)
        this.binaryResult = binaryResult
    }

    func destroy(): Unit {
        arena.destroy()
    }
}

/** 二进制结果协议模式（连接串 pool.binaryResult=auto|always|never，默认 auto）。 */
public enum BinaryResultMode {
    | Auto      // 结果 OID 全命中白名单才用二进制（推荐）
    | Always    // 强制二进制（非白名单类型将解码失败并抛错）
    | Never     // 恒文本（旧行为）
}

/** 解析 pool.binaryResult 值；非法值回 Auto。 */
func parseBinaryResultMode(s: String): BinaryResultMode {
    match (s) {
        case "auto" => BinaryResultMode.Auto
        case "always" => BinaryResultMode.Always
        case "never" => BinaryResultMode.Never
        case _ => BinaryResultMode.Auto
    }
}
