package lanlu.shared.utils

import std.io.*
import stdx.log.*
import stdx.logger.*
import std.sync.*
import std.fs.*
import std.convert.*
import std.time.DateTime
import std.env.{getVariable, getStdOut}

private class GlobalLoggerWrapper <: Logger {
    static let instance = GlobalLoggerWrapper()

    private let ref: AtomicReference<Logger>

    private init() {
        ref = AtomicReference<Logger>(SimpleLogger(getStdOut()))
    }

    public func replace(logger: Logger): Unit {
        ref.store(logger)
    }

    private func load(): Logger {
        ref.load()
    }

    public func close(): Unit {
        load().close()
    }

    public func isClosed(): Bool {
        load().isClosed()
    }

    public func log(record: LogRecord): Unit {
        load().log(record)
    }

    public func withAttrs(attrs: Array<Attr>): Logger {
        load().withAttrs(attrs)
    }

    public mut prop level: LogLevel {
        get() {
            load().level
        }
        set(value) {
            load().level = value
        }
    }
}

/**
 * 按大小滚动的文件日志输出流。
 *
 * - 活动日志持续追加写入 activePath（默认 ./data/logs/system/system.log）。
 * - 文件大小超过 maxBytes 时，先原子改名为归档文件 system-YYYY-MM-DD-<seq>.log，
 *   再新建一个空的活动文件继续追加。
 * - 写入失败时自动尝试重开句柄；仍失败则降级写入 stdout，绝不向调用方抛出，
 *   避免 stdx 日志器写入失败拖垮 CronService 调度循环等上游逻辑。
 */
class RollingFileLogStream <: OutputStream & Resource {
    private let activePath: String
    private let dir: Path
    private let maxBytes: Int64
    private var file: ?File = None
    private var written: Int64 = 0
    private var closed: Bool = false
    private let lock = Mutex()

    init(path: String, maxBytes: Int64) {
        this.activePath = path
        this.dir = Path(path).parent
        this.maxBytes = maxBytes
        FileUtils.ensureDirectoryExists(this.dir)
        openActive()
    }

    /**
     * （重新）打开活动日志文件。OpenMode.Append 在文件不存在时会创建，
     * 已存在时不截断。written 同步为当前文件长度，以便继续追加时正确累计。
     */
    private func openActive(): Unit {
        let f = File(activePath, OpenMode.Append)
        file = f
        written = f.length
    }

    /**
     * 滚动归档：关闭当前文件，把 system.log 改名为 system-日期-序号.log，再新建空文件。
     * 异常向上抛出，由 write 统一捕获处理。
     */
    private func rollover(): Unit {
        match (file) {
            case Some(f) =>
                try {
                    f.close()
                } catch (_: Exception) {
                }
            case None => ()
        }
        file = None

        let p = Path(activePath)
        let stem = p.fileNameWithoutExtension
        let ext = p.extensionName
        let date = DateTime.now().format("yyyy-MM-dd")

        var seq = 1
        var archive = ""
        while (true) {
            archive = "${dir}/${stem}-${date}-${seq}.${ext}"
            if (!exists(archive)) {
                break
            }
            seq += 1
        }

        rename(activePath, to: archive)
        openActive()
    }

    private func writeOnce(buffer: Array<Byte>): Unit {
        match (file) {
            case None =>
                openActive()
                match (file) {
                    case Some(f) =>
                        f.write(buffer)
                        written += buffer.size
                    case None =>
                        // 极端防御：openActive 成功后 file 必为 Some，理论不可达
                        ()
                }
            case Some(f) =>
                f.write(buffer)
                written += buffer.size
        }
    }

    public func write(buffer: Array<Byte>): Unit {
        synchronized(lock) {
            if (closed) {
                try {
                    openActive()
                    closed = false
                } catch (_: Exception) {
                    // 复活失败，直接走降级路径
                }
            }

            // 仅当已有写入且本次写入会超阈值时滚动；单次写入本身超大也照写一次
            if (written > 0 && written + buffer.size > maxBytes) {
                try {
                    rollover()
                } catch (_: Exception) {
                    // 滚动失败：尽量继续往当前文件写，交给下面的失败重试兜底
                }
            }

            try {
                writeOnce(buffer)
            } catch (_: Exception) {
                // 主路径写入失败：重开句柄后重试一次
                try {
                    openActive()
                    writeOnce(buffer)
                } catch (_: Exception) {
                    // 仍失败：降级写入 stdout，绝不向调用方抛出
                    try {
                        getStdOut().write(buffer)
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    public func flush(): Unit {
        synchronized(lock) {
            match (file) {
                case Some(f) =>
                    try {
                        f.flush()
                    } catch (_: Exception) {
                    }
                case None => ()
            }
        }
    }

    public func close(): Unit {
        synchronized(lock) {
            match (file) {
                case Some(f) =>
                    try {
                        f.close()
                    } catch (_: Exception) {
                    }
                case None => ()
            }
            file = None
            closed = true
        }
    }

    public func isClosed(): Bool {
        closed
    }
}

public func initializeLogging(): Unit {

    let logLevel = getLogLevel()
    let logFormat = getLogFormat()
    let output = getLogOutput()

    let logger: Logger
    match (logFormat) {
        case "json" =>
            logger = JsonLogger(output)
        case "text" =>
            logger = TextLogger(output)
        case _ =>
            logger = SimpleLogger(output)
    }

    logger.level = logLevel
    GlobalLoggerWrapper.instance.replace(logger)

    let globalLogger = GlobalLoggerWrapper.instance.withAttrs([("component", "logging")])
    globalLogger.info("Logging system initialized", ("level", logLevel.toString()), ("format", logFormat))
}

public func getLogger(component: String): Logger {
    GlobalLoggerWrapper.instance.withAttrs([("component", component)])
}

public func getLogger(attrs: Array<Attr>): Logger {
    GlobalLoggerWrapper.instance.withAttrs(attrs)
}

private func getLogLevel(): LogLevel {
    let levelStr = getVariable("LOG_LEVEL") ?? "INFO"
    match (levelStr) {
        case "TRACE" => LogLevel.TRACE
        case "DEBUG" => LogLevel.DEBUG
        case "INFO" => LogLevel.INFO
        case "WARN" => LogLevel.WARN
        case "ERROR" => LogLevel.ERROR
        case _ => LogLevel.INFO
    }
}

private func getLogFormat(): String {
    getVariable("LOG_FORMAT") ?? "simple"
}

private func getLogOutput(): OutputStream {
    let logFile = getVariable("LOG_FILE") ?? "./data/logs/system/system.log"
    if (logFile.size == 0) {
        return getStdOut()
    }
    let maxBytes = getMaxSizeBytes()
    try {
        return RollingFileLogStream(logFile, maxBytes)
    } catch (_: Exception) {
        return getStdOut()
    }
}

/**
 * 解析 LOG_MAX_SIZE_MB，非法或缺失时默认 10MB，最小 1MB。
 */
private func getMaxSizeBytes(): Int64 {
    let mbStr = getVariable("LOG_MAX_SIZE_MB") ?? "10"
    var mb: Int64 = 10
    try {
        mb = Int64.parse(mbStr)
        if (mb < 1) {
            mb = 1
        }
    } catch (_: Exception) {
        mb = 10
    }
    return mb * 1024 * 1024
}