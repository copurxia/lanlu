package lanlu_client_next.net

import std.collection.{ArrayList, HashMap}
import std.collection.concurrent.LinkedBlockingQueue
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

// 线程池任务项（阻塞队列元素）。
private class WorkItem {
    let name: String
    let job: () -> Any
    init(name: String, job: () -> Any) {
        this.name = name
        this.job = job
    }
}

// UI 线程提交任务 → 固定大小线程池执行 → 结果进信箱；主循环 onTick 每次迭代 drain 回 UI 线程。
// 早期每任务 spawn 一条新线程，高频图片任务下线程创建开销显著；改为 WORKER_THREADS 条
// 工作线程循环从阻塞队列取任务（生产者-消费者，与图片并发硬上限 4 对齐取 4 条）。
public class ApiWorker {
    private static let WORKER_THREADS: Int64 = 4

    private let mutex = Mutex()
    private var results = ArrayList<ApiResult>()
    private var inflight = HashMap<String, Bool>()
    // 任务队列：容量给足（启动批量行加载 + 图片排队也不过几十），add 阻塞语义不触发。
    private let queue = LinkedBlockingQueue<WorkItem>(4096, ArrayList<WorkItem>())

    public init() {
        for (_ in 0..WORKER_THREADS) {
            let _ = spawn { workLoop() }
        }
    }

    // 工作线程主循环：阻塞取任务执行。异常绝不能逃出本循环：任务异常转成 error 结果，
    // inflight 必须复位，否则之后所有同名任务永远被拒。
    private func workLoop(): Unit {
        while (true) {
            let item = queue.remove()
            let r = try {
                ApiResult(item.name, Some(item.job()), "")
            } catch (e: Exception) {
                ApiResult(item.name, None, e.message)
            }
            synchronized(mutex) {
                results.add(r)
                inflight.remove(item.name)
            }
        }
    }

    public func submit(name: String, job: () -> Any): Bool {
        synchronized(mutex) {
            if (inflight.contains(name)) { return false }
            inflight[name] = true
        }
        queue.add(WorkItem(name, job))
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
