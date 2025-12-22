package lrr4cj.utils

import std.io.*
import std.env.*
import stdx.log.*
import stdx.logger.*
import std.fs.*
import std.env.getVariable


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
    setGlobalLogger(logger)

    let globalLogger = getGlobalLogger([("component", "logging")])
    globalLogger.info("Logging system initialized", ("level", logLevel.toString()), ("format", logFormat))

    // 同时输出到控制台确认日志系统工作
    let stdout = getStdOut()
    stdout.write("✅ Logging system initialized - Level: ${logLevel.toString()}, Format: ${logFormat}\n")
    stdout.flush()
}

public func getLogger(component: String): Logger {
    getGlobalLogger([("component", component)])
}

public func getLogger(attrs: Array<Attr>): Logger {
    getGlobalLogger(attrs)
}

private func getLogLevel(): LogLevel {
    let levelStr = getVariable("LOG_LEVEL") ?? "INFO"
    // 输出调试信息到标准错误，这样我们可以看到实际读取的值
    let stderr = getStdErr()
    stderr.write("DEBUG: Log level from env: '${levelStr}'\n")
    stderr.flush()
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
        } catch (e: Exception) {
            let stderr = getStdErr()
            stderr.write("Failed to create log file ${logFile}: ${e.toString()}")
            stderr.flush()
            return getStdOut()
        }
    }
    return getStdOut()
}