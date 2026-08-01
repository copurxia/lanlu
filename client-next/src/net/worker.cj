package lanlu_client_next.net

import std.collection.{ArrayList, HashMap}
import std.collection.concurrent.LinkedBlockingQueue
import std.sync.Mutex

public class ApiResult {
    public let name: String
    public let payload: ?Any
    public let error: String
    public let tag: String
    public init(name: String, payload: ?Any, error: String, tag!: String = "") {
        this.name = name
        this.payload = payload
        this.error = error
        this.tag = tag
    }
}

// 线程池任务项（阻塞队列元素）。
private class WorkItem {
    let name: String
    let inflightKey: String
    let tag: String
    let job: () -> Any
    init(name: String, inflightKey: String, tag: String, job: () -> Any) {
        this.name = name
        this.inflightKey = inflightKey
        this.tag = tag
        this.job = job
    }
}

// UI 线程提交任务 → 固定大小线程池执行 → 结果进信箱；主循环 onTick 每次迭代 drain 回 UI 线程。
// 双执行器（#22）：API 池与图片池各自独立队列 + 独立线程，互不阻塞——图片任务
//（下载 + vips 解码，慢链路下单个可达秒级）打满图片池时，元数据/搜索/进度等交互 API
// 仍能即时开工；反过来 API 慢请求也不占图片吞吐。图片并发硬上限（在途 4 个）不在本层，
// 由 model.cj 的 activeImages 计数保证（requestImage/finishImageTask）；两池共享 inflight
// 去重表（任务名全局命名空间，"img:" 前缀天然分域）。
public class ApiWorker {
    private static let API_THREADS: Int64 = 2
    private static let IMAGE_THREADS: Int64 = 4

    private let mutex = Mutex()
    private var results = ArrayList<ApiResult>()
    private var inflight = HashMap<String, Bool>()
    // 任务队列：容量给足（启动批量行加载 + 图片排队也不过几十），add 阻塞语义不触发。
    private let apiQueue = LinkedBlockingQueue<WorkItem>(4096, ArrayList<WorkItem>())
    private let imageQueue = LinkedBlockingQueue<WorkItem>(4096, ArrayList<WorkItem>())
    /*
     * 结果落地回调：每次有结果进入信箱后、于工作线程上下文调用。主循环用它唤醒可能正
     * 阻塞在 SDL_WaitEventTimeout 的 UI 线程（DesktopApp.requestWake）——drain 只在
     * onTick 发生，没有唤醒注入的话到货结果要等下一个输入事件/定时器才被泵回。
     * 实现必须轻量且不得抛异常（异常会逃出工作线程主循环）。
     */
    public var onResult: () -> Unit = { => }

    public init() {
        for (_ in 0..API_THREADS) {
            let _ = spawn { workLoop(apiQueue) }
        }
        for (_ in 0..IMAGE_THREADS) {
            let _ = spawn { workLoop(imageQueue) }
        }
    }

    // 工作线程主循环：阻塞取任务执行。异常绝不能逃出本循环：任务异常转成 error 结果，
    // inflight 必须复位，否则之后所有同名任务永远被拒。
    private func workLoop(queue: LinkedBlockingQueue<WorkItem>): Unit {
        while (true) {
            let item = queue.remove()
            let r = try {
                ApiResult(item.name, Some(item.job()), "", tag: item.tag)
            } catch (e: Exception) {
                ApiResult(item.name, None, e.message, tag: item.tag)
            }
            synchronized(mutex) {
                results.add(r)
                inflight.remove(item.inflightKey)
            }
            onResult()
        }
    }

    // 通用/API 任务：2 线程池。同名在途去重（返回 false 表示被拒）。
    public func submit(name: String, job: () -> Any): Bool {
        submitInternal(name, name, "", job)
    }

    /** Submits a logical task with a tag-specific in-flight identity. */
    public func submitTagged(name: String, tag: String, job: () -> Any): Bool {
        submitInternal(name, "${name}@${tag}", tag, job)
    }

    private func submitInternal(name: String, inflightKey: String, tag: String, job: () -> Any): Bool {
        synchronized(mutex) {
            if (inflight.contains(inflightKey)) { return false }
            inflight[inflightKey] = true
        }
        apiQueue.add(WorkItem(name, inflightKey, tag, job))
        return true
    }

    // 图片任务：4 线程独立池，与 API 池互不阻塞。去重语义同 submit。
    public func submitImage(name: String, job: () -> Any): Bool {
        synchronized(mutex) {
            if (inflight.contains(name)) { return false }
            inflight[name] = true
        }
        imageQueue.add(WorkItem(name, name, "", job))
        return true
    }

    // 信箱外投（长连流式任务专用）：不占用 inflight 名额、可同名重复投递，
    // 结果仍由主循环 onTick drain 回 UI 线程。
    public func post(name: String, payload: ?Any, error!: String = ""): Unit {
        synchronized(mutex) {
            results.add(ApiResult(name, payload, error))
        }
        onResult()
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
