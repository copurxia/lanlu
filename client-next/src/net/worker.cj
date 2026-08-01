package lanlu_client_next.net

import std.collection.{ArrayList, HashMap}
import std.collection.concurrent.{ConcurrentLinkedQueue, LinkedBlockingQueue}
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
// 三执行器（#22 双池扩展为三级流水线，见 P1.6）：API 池、图片下载池、图片解码池各自
// 独立队列 + 独立线程，互不阻塞——图片下载（慢网络链路）打满下载池时，元数据/搜索/
// 进度等交互 API 仍能即时开工；解码池独立避免下载过快积压大量待解码结果。下载完成在
// 下载线程内提交解码任务（解码队列有界，满则阻塞下载线程产生背压，禁止无界积累
// decoded/native 图片）。图片并发硬上限（下载在途 4 个）在 model.cj 的 activeImages
// 计数（requestImage/finishImageTask）；三池共享 inflight 去重表（任务名全局命名空间）。
public class ApiWorker {
    private static let API_THREADS: Int64 = 2
    private static let DOWNLOAD_THREADS: Int64 = 4
    private static let DECODE_THREADS: Int64 = 2

    private let mutex = Mutex()
    // 结果信箱：无锁并发队列（P2.8）——drain 循环取到空，不再每次新建并复制结果列表。
    private let results = ConcurrentLinkedQueue<ApiResult>()
    private var inflight = HashMap<String, Bool>()
    // 任务队列：API/下载队列容量给足（启动批量行加载 + 图片排队也不过几十），add 阻塞
    // 语义不触发；解码队列有界（32）作为背压阀：满时下载线程的 submitDecode 阻塞。
    private let apiQueue = LinkedBlockingQueue<WorkItem>(4096, ArrayList<WorkItem>())
    private let downloadQueue = LinkedBlockingQueue<WorkItem>(4096, ArrayList<WorkItem>())
    private let decodeQueue = LinkedBlockingQueue<WorkItem>(32, ArrayList<WorkItem>())
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
        for (_ in 0..DOWNLOAD_THREADS) {
            let _ = spawn { workLoop(downloadQueue) }
        }
        for (_ in 0..DECODE_THREADS) {
            let _ = spawn { workLoop(decodeQueue) }
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
                inflight.remove(item.inflightKey)
            }
            results.add(r)
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

    // 图片下载任务：4 线程独立池，与 API/解码池互不阻塞。去重语义同 submit。
    public func submitImage(name: String, job: () -> Any): Bool {
        submitTo(name, name, "", job, downloadQueue)
    }

    // 图片下载阶段（别名保留：原有 submitImage 语义即下载池）。
    public func submitDownload(name: String, job: () -> Any): Bool {
        submitTo(name, name, "", job, downloadQueue)
    }

    // 图片解码阶段：独立有界队列（32），满则阻塞调用线程（下载线程）产生背压。
    public func submitDecode(name: String, job: () -> Any): Bool {
        submitTo(name, name, "", job, decodeQueue)
    }

    private func submitTo(name: String, inflightKey: String, tag: String, job: () -> Any,
        queue: LinkedBlockingQueue<WorkItem>): Bool {
        synchronized(mutex) {
            if (inflight.contains(inflightKey)) { return false }
            inflight[inflightKey] = true
        }
        queue.add(WorkItem(name, inflightKey, tag, job))
        return true
    }

    // 信箱外投（长连流式任务专用）：不占用 inflight 名额、可同名重复投递，
    // 结果仍由主循环 onTick drain 回 UI 线程。
    public func post(name: String, payload: ?Any, error!: String = ""): Unit {
        results.add(ApiResult(name, payload, error))
        onResult()
    }

    // 取走全部结果（UI 线程循环取到空，无整列表复制；ConcurrentLinkedQueue 非阻塞）。
    public func drain(): ArrayList<ApiResult> {
        let out = ArrayList<ApiResult>()
        while (true) {
            match (results.remove()) {
                case Some(r) => out.add(r)
                case None => break
            }
        }
        out
    }
}
