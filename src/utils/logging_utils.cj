package lrr4cj.utils

import std.io.*
import std.env.*
import stdx.log.*
import stdx.logger.*
import std.fs.*
import dotenv.Dotenv

public func initializeLogging(): Unit {
    // 确保先加载 .env 文件
    Dotenv.config()

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
}

public func getLogger(component: String): Logger {
    getGlobalLogger([("component", component)])
}

public func getLogger(attrs: Array<Attr>): Logger {
    getGlobalLogger(attrs)
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
    let logFile = getVariable("LOG_FILE") ?? ""
    if (logFile.size > 0) {
        try {
            let file = File(logFile, Append)
            return BufferedOutputStream<OutputStream>(file)
        } catch (e: Exception) {
            let stderr = getStdErr()
            stderr.write("Failed to create log file ${logFile}: ${e.toString()}".toArray())
            stderr.flush()
            return getStdOut()
        }
    }
    return getStdOut()
}