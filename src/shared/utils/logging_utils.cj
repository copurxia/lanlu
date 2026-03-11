package lanlu.shared.utils

import std.io.*
import stdx.log.*
import stdx.logger.*
import std.sync.*
import std.fs.*
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
    let logFile = getVariable("LOG_FILE") ?? "./data/logs/system.log"
    if (logFile.size > 0) {
        try {
            let file = File(logFile, OpenMode.Append)
            // 直接使用文件，不使用缓冲流，确保日志立即写入
            return file
        } catch (_: Exception) {
            return getStdOut()
        }
    }
    return getStdOut()
}
