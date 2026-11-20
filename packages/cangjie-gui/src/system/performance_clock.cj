package cui.system

// P5：性能时钟改用 libc 单调时钟（不再依赖 SDL 计时器）。
// CLOCK_MONOTONIC=1（Linux/OHOS 一致）；delay 用 nanosleep。

foreign {
    func nanosleep(req: CPointer<Timespec>, rem: CPointer<Timespec>): Int32
}

private const CLOCK_MONOTONIC: Int32 = 1

private func monotonicNanoseconds(): UInt64 {
    var ts = Timespec()
    unsafe { clock_gettime(CLOCK_MONOTONIC, inout ts) }
    UInt64(ts.tv_sec) * 1000000000 + UInt64(ts.tv_nsec)
}

public class PerformanceClock {
    public static func ticksMilliseconds(): UInt64 {
        monotonicNanoseconds() / 1000000
    }

    public static func ticksNanoseconds(): UInt64 {
        monotonicNanoseconds()
    }

    public static func counter(): UInt64 {
        monotonicNanoseconds()
    }

    public static func frequency(): UInt64 {
        1000000000
    }

    public static func delayNanoseconds(ns: UInt64): Unit {
        var req = Timespec()
        req.tv_sec = Int64(ns / 1000000000)
        req.tv_nsec = Int64(ns % 1000000000)
        unsafe { nanosleep(inout req, CPointer<Timespec>()) }
    }

    public static func delayPrecise(ns: UInt64): Unit {
        delayNanoseconds(ns)
    }

    public static func millisecondsToNanoseconds(ms: UInt64): UInt64 {
        ms * SDL_NS_PER_MS
    }
}
