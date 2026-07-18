package lanlu_client_next.net

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex

public class ApiResult {
    public let name: String
    public let payload: ?Any
    public let error: String
    public init(name: String, payload: ?Any, error: String) {
        this.name = name
        this.payload = payload
        this.error = error
    }
}

// UI 线程提交任务 → spawn 执行 → 结果进信箱；FrameHandler 每帧 drain 回 UI 线程。
// 模式与 packages/cangjie-gui/examples/process_manager/src/worker.cj 一致。
public class ApiWorker {
    private let mutex = Mutex()
    private var results = ArrayList<ApiResult>()
    private var inflight = HashMap<String, Bool>()

    public func submit(name: String, job: () -> Any): Bool {
        synchronized(mutex) {
            if (inflight.contains(name)) { return false }
            inflight[name] = true
        }
        let _ = spawn {
            // 异常绝不能逃出 spawn：Future 无人 get，异常会被静默吞掉，
            // inflight 不复位，之后所有同名任务永远被拒。
            let r = try {
                ApiResult(name, Some(job()), "")
            } catch (e: Exception) {
                ApiResult(name, None, e.message)
            }
            synchronized(mutex) {
                results.add(r)
                inflight.remove(name)
            }
        }
        return true
    }

    public func drain(): ArrayList<ApiResult> {
        synchronized(mutex) {
            let out = ArrayList<ApiResult>()
            out.add(all: results)
            results = ArrayList<ApiResult>()
            return out
        }
    }
}
