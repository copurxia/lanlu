package lwp

// liblwp 的仓颉绑定（计划 §5.2）。FFI 边界只传标量与字节缓冲，
// 不传 lwp_header 结构体——避免跨语言结构体 ABI（这与生成器的解码策略一致）。
//
// 加载顺序（docs/l-layer.md M0-4 结论）：liblwp.so 由壳以 RTLD_GLOBAL 加载且早于引擎；
// 链路是否可用只认 core.hello_ack，不看链接是否成功。

// ── 方向（与 C 侧 LWP_REQUEST / LWP_EVENT 一致）──
public let LWP_REQUEST: Int32 = 0
public let LWP_EVENT: Int32 = 1

// ── 错误码（负数；与 C 侧一致）──
public let LWP_ERR_EINVAL: Int32 = -22
public let LWP_ERR_EAGAIN: Int32 = -11
public let LWP_ERR_EMSGSIZE: Int32 = -90
public let LWP_ERR_ENOENT: Int32 = -2
public let LWP_ERR_EPROTO: Int32 = -71

// ── 头标志 ──
public let LWP_FLAG_BLOB: UInt32 = 1
public let LWP_FLAG_DROPPABLE: UInt32 = 2
public let LWP_INLINE_MAX: Int64 = 320

foreign {
    func lwp_open(name: CString, slots: UInt32, out: CPointer<CPointer<UInt8>>): Int32
    func lwp_close(ch: CPointer<UInt8>): Unit
    func lwp_send_parts(ch: CPointer<UInt8>, dir: Int32, iface: UInt16, opcode: UInt16,
        flags: UInt32, body: CPointer<UInt8>, len: UInt32): Int32
    func lwp_recv_parts(ch: CPointer<UInt8>, dir: Int32, iface: CPointer<UInt16>, opcode: CPointer<UInt16>,
        flags: CPointer<UInt32>, timeNs: CPointer<UInt64>, body: CPointer<UInt8>, cap: UInt32,
        outLen: CPointer<UInt32>): Int32
    func lwp_wait(ch: CPointer<UInt8>, dir: Int32, timeoutMs: Int32): Int32
    func lwp_wake(ch: CPointer<UInt8>, dir: Int32): Int32
    func lwp_checker_enable(ch: CPointer<UInt8>, strict: Int32): Int32
    func lwp_trace_open(ch: CPointer<UInt8>, path: CString): Int32
    func lwp_trace_close(ch: CPointer<UInt8>): Unit
    func lwp_trace_replay(ch: CPointer<UInt8>, path: CString, dirFilter: Int32): Int32
    func lwp_stats_summary(ch: CPointer<UInt8>, out: CPointer<UInt8>, cap: UInt32): Int32
    func lwp_now_ns(): UInt64
}

/// 一条收到的协议消息。
public struct LwpMessage {
    public let iface: UInt16
    public let opcode: UInt16
    public let flags: UInt32
    public let timeNs: UInt64
    public let body: Array<UInt8>

    public init(iface: UInt16, opcode: UInt16, flags: UInt32, timeNs: UInt64, body: Array<UInt8>) {
        this.iface = iface
        this.opcode = opcode
        this.flags = flags
        this.timeNs = timeNs
        this.body = body
    }
}

/// 通道句柄。进程内单例由 C 侧保证（同名 lwp_open 返回同一实例）。
public class LwpChannel {
    private let handle: CPointer<UInt8>

    private init(handle: CPointer<UInt8>) {
        this.handle = handle
    }

    /// 打开（或复用）通道。失败抛 LwpException。
    public static func open(name: String, slots!: UInt32 = 256): LwpChannel {
        let cname = unsafe { LibC.mallocCString(name) }
        let out = unsafe { LibC.malloc<CPointer<UInt8>>(count: 1) }
        let rc = unsafe { lwp_open(cname, slots, CPointer<CPointer<UInt8>>(out)) }
        unsafe { LibC.free(cname) }
        let h = unsafe { out.read() }
        unsafe { LibC.free(out) }
        if (rc != 0 || h.isNull()) {
            throw LwpException("lwp_open failed rc=${rc}")
        }
        LwpChannel(h)
    }

    /// 发送一条消息。返回 C 侧错误码（0 成功）；满队列为 LWP_ERR_EAGAIN。
    public func send(dir: Int32, iface: UInt16, opcode: UInt16, body: Array<UInt8>,
        flags!: UInt32 = 0): Int32 {
        if (body.size == 0) {
            return unsafe { lwp_send_parts(handle, dir, iface, opcode, flags, CPointer<UInt8>(), 0) }
        }
        let buf = unsafe { LibC.malloc<UInt8>(count: body.size) }
        for (i in 0..body.size) {
            unsafe { (buf + i).write(body[i]) }
        }
        let rc = unsafe {
            lwp_send_parts(handle, dir, iface, opcode, flags, CPointer<UInt8>(buf), UInt32(body.size))
        }
        unsafe { LibC.free(buf) }
        rc
    }

    /// 收取一条消息；无消息返回 None。
    public func recv(dir: Int32, cap!: Int64 = 512): ?LwpMessage {
        let buf = unsafe { LibC.malloc<UInt8>(count: cap) }
        let iface = unsafe { LibC.malloc<UInt16>(count: 1) }
        let opcode = unsafe { LibC.malloc<UInt16>(count: 1) }
        let flags = unsafe { LibC.malloc<UInt32>(count: 1) }
        let t = unsafe { LibC.malloc<UInt64>(count: 1) }
        let outLen = unsafe { LibC.malloc<UInt32>(count: 1) }
        let rc = unsafe {
            lwp_recv_parts(handle, dir, CPointer<UInt16>(iface), CPointer<UInt16>(opcode),
                CPointer<UInt32>(flags), CPointer<UInt64>(t), CPointer<UInt8>(buf), UInt32(cap),
                CPointer<UInt32>(outLen))
        }
        var msg: ?LwpMessage = None
        if (rc == 0) {
            let n = Int64(unsafe { outLen.read() })
            let body = Array<UInt8>(n, repeat: 0)
            for (i in 0..n) {
                body[i] = unsafe { (buf + i).read() }
            }
            msg = LwpMessage(unsafe { iface.read() }, unsafe { opcode.read() },
                unsafe { flags.read() }, unsafe { t.read() }, body)
        }
        unsafe { LibC.free(buf) }
        unsafe { LibC.free(iface) }
        unsafe { LibC.free(opcode) }
        unsafe { LibC.free(flags) }
        unsafe { LibC.free(t) }
        unsafe { LibC.free(outLen) }
        msg
    }

    /// 等待有数据 / 被 wake / 超时。返回 true 表示可以尝试 recv。
    public func wait(dir: Int32, timeoutMs: Int32): Bool {
        unsafe { lwp_wait(handle, dir, timeoutMs) } == 0
    }

    /// 打断对端的等待。
    public func wake(dir: Int32): Unit {
        let _ = unsafe { lwp_wake(handle, dir) }
    }

    /// 发送 core.hello_ack（引擎 -> 壳），完成握手。
    /// 必须在收到壳的 core.hello 之后调用（壳侧握手由 lwp_client.cpp 负责）。
    public func sendHelloAck(engineVersion!: UInt32 = 1, engineName!: String = "lanlu"): Bool {
        let name = engineName.toArray()
        var body = Array<UInt8>(LWP_LW_CORE_HELLO_ACK_SIZE + name.size, repeat: 0)
        // size 字段（总长）
        let total = UInt32(LWP_LW_CORE_HELLO_ACK_SIZE + name.size)
        body[0] = UInt8(total & 0xFF)
        body[1] = UInt8((total >> 8) & 0xFF)
        body[2] = UInt8((total >> 16) & 0xFF)
        body[3] = UInt8((total >> 24) & 0xFF)
        body[4] = UInt8(LWP_PROTOCOL_MAJOR)
        body[6] = UInt8(LWP_PROTOCOL_MINOR)
        // engine_version u32 @8
        body[8] = UInt8(engineVersion & 0xFF)
        body[9] = UInt8((engineVersion >> 8) & 0xFF)
        body[10] = UInt8((engineVersion >> 16) & 0xFF)
        body[11] = UInt8((engineVersion >> 24) & 0xFF)
        // engine_name string @12：off=16, len=n
        body[12] = UInt8(LWP_LW_CORE_HELLO_ACK_SIZE)
        body[14] = UInt8(name.size)
        for (i in 0..name.size) {
            body[LWP_LW_CORE_HELLO_ACK_SIZE + i] = name[i]
        }
        send(LWP_REQUEST, LWP_IFACE_LW_CORE, LWP_LW_CORE_HELLO_ACK_OPCODE, body) == 0
    }

    /// 启用协议检查器（strict 时违规返回 LWP_ERR_EPROTO）。
    public func enableChecker(strict!: Bool = true): Unit {
        let _ = unsafe { lwp_checker_enable(handle, if (strict) { 1 } else { 0 }) }
    }

    /// 开始/结束 .lwtrace 录制。
    public func traceOpen(path: String): Bool {
        let p = unsafe { LibC.mallocCString(path) }
        let rc = unsafe { lwp_trace_open(handle, p) }
        unsafe { LibC.free(p) }
        rc == 0
    }

    public func traceClose(): Unit {
        unsafe { lwp_trace_close(handle) }
    }

    /// 回放 .lwtrace：把「发送」记录按原样重新入队。dirFilter < 0 表示两个方向。
    /// 返回回放条数，负数为错误码。计划 §16.3。
    public func replay(path: String, dirFilter!: Int32 = -1): Int32 {
        let p = unsafe { LibC.mallocCString(path) }
        let rc = unsafe { lwp_trace_replay(handle, p, dirFilter) }
        unsafe { LibC.free(p) }
        rc
    }

    public func close(): Unit {
        unsafe { lwp_close(handle) }
    }

    /// 统计摘要（诊断用）：真机排障时打到 hilog/probeTrace，不依赖抓包。
    /// 格式由 C 侧 `lwp_stats_summary` 决定（不跨 FFI 传结构体，避免布局猜测）。
    public func statsSummary(): String {
        let cap: Int64 = 256
        let buf = unsafe { LibC.malloc<UInt8>(count: cap) }
        let n = unsafe { lwp_stats_summary(handle, CPointer<UInt8>(buf), UInt32(cap)) }
        var out = ""
        if (n > 0) {
            let bytes = Array<UInt8>(Int64(n), repeat: 0)
            for (i in 0..Int64(n)) {
                bytes[i] = unsafe { (buf + i).read() }
            }
            out = String.fromUtf8(bytes)
        }
        unsafe { LibC.free(buf) }
        out
    }

    public static func nowNs(): UInt64 {
        unsafe { lwp_now_ns() }
    }
}

public class LwpException <: Exception {
    public init(message: String) {
        super(message)
    }
}
