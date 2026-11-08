package postgresql_driver

import std.collection.*

/**
 * 参数构造 arena：替代 run() 每参数 mallocCString + free 的分配模式。
 *
 * 原路径（connection.cj run）：每次执行对 SQL 与每个参数各做一次 mallocCString，
 * 用完 free——高频查询下 C 堆分配/释放是可测开销（fastnative-analysis 第五节 5）。
 * 本 arena 在【连接级】持有可增长缓冲：参数文本先在仓颉侧拼成 UTF-8 字节，再
 * 一次性 memcpy 进 C 缓冲并记录 NUL 终止；borrow 周期结束后 reset 归还复用。
 *
 * 生命周期：PGConnState 每条池化连接一个 Arena；单条连接同一时刻只被一条仓颉
 * 线程使用，无需加锁。
 *
 * 布局：一个连续 CPointer<UInt8> 缓冲 + CString 槽位数组。prepare() 时逐参数写入，
 * build() 产出 paramValues 指针数组（指向槽位）。
 */
class ParamArena {
    private var buf: CPointer<UInt8>
    private var bufCap: Int64
    private var bufUsed: Int64 = 0
    // 每个参数在 buf 内的起始下标（-1 表示该参数为 NULL 指针）
    private var slotOff = ArrayList<Int64>()
    private var slotLen = ArrayList<Int64>()

    static let INITIAL_CAP: Int64 = 4096

    init() {
        bufCap = INITIAL_CAP
        buf = unsafe { LibC.malloc<UInt8>(count: bufCap) }
    }

    /** 释放底层缓冲（连接销毁时调用）。 */
    func destroy(): Unit {
        unsafe { LibC.free(buf) }
        buf = CPointer<UInt8>()
        bufCap = 0
        bufUsed = 0
    }

    private func ensure(extra: Int64): Unit {
        if (bufUsed + extra <= bufCap) {
            return
        }
        var newCap = bufCap * 2
        while (newCap < bufUsed + extra) {
            newCap = newCap * 2
        }
        let nb = unsafe { LibC.malloc<UInt8>(count: newCap) }
        // 逐字节搬运（编译为机器 mov；LibC 无 memcpy 绑定，不为此新增 C 符号）
        for (i in 0..bufUsed) {
            unsafe { (nb + i).write((buf + i).read()) }
        }
        unsafe { LibC.free(buf) }
        buf = nb
        bufCap = newCap
    }

    /** 开始一轮参数装配（清空槽位，缓冲字节保留复用）。 */
    func reset(): Unit {
        slotOff.clear()
        slotLen.clear()
        bufUsed = 0
    }

    /** 追加一个参数（文本形式）。value 为 None 表示 SQL NULL（记录 -1 槽位）。 */
    func add(text: ?String): Unit {
        match (text) {
            case None =>
                slotOff.add(-1)
                slotLen.add(0)
            case Some(s) =>
                let bytes = s.toArray()
                // 参数后补 NUL 终止
                ensure(bytes.size + 1)
                let start = bufUsed
                for (i in 0..bytes.size) {
                    unsafe { (buf + (start + i)).write(bytes[i]) }
                }
                unsafe { (buf + start + bytes.size).write(0u8) }
                bufUsed = start + bytes.size + 1
                slotOff.add(start)
                slotLen.add(Int64(bytes.size))
        }
    }

    /** 参数个数。 */
    func count(): Int64 { Int64(slotOff.size) }

    /**
     * 产出 paramValues 指针数组（每槽指向 buf 内 NUL 终止串；NULL 参数为空指针）。
     * 返回 acquireArrayRawData 句柄，调用方用完必须 releaseArrayRawData。
     * 空指针用 CString(CPointer()) 表达（libpq 把空 paramValues[i] 视为 NULL）。
     */
    func buildParams(): Array<CString> {
        let n = slotOff.size
        if (n == 0) {
            return Array<CString>(0, { _ => CString(CPointer()) })
        }
        let arr = Array<CString>(n, { i =>
            let off = slotOff[i]
            if (off < 0) {
                CString(CPointer())
            } else {
                CString(unsafe { buf + off })
            }
        })
        arr
    }
}
