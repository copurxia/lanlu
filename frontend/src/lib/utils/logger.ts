/**
 * 日志管理工具
 * 统一管理应用程序中的日志输出
 */

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export interface LogEntry {
  level: LogLevel;
  message: string;
  error?: Error | any;
  timestamp: string;
  context?: Record<string, any>;
}

/**
 * 日志记录器类
 */
class Logger {
  private static instance: Logger;
  private isEnabled: boolean;
  private minLevel: LogLevel;

  private constructor() {
    // 在开发环境中默认启用，在生产环境中默认禁用
    this.isEnabled = process.env.NODE_ENV === 'development';
    this.minLevel = 'debug';
  }

  public static getInstance(): Logger {
    if (!Logger.instance) {
      Logger.instance = new Logger();
    }
    return Logger.instance;
  }

  /**
   * 启用或禁用日志
   */
  public setEnabled(enabled: boolean): void {
    this.isEnabled = enabled;
  }

  /**
   * 设置最低日志级别
   */
  public setMinLevel(level: LogLevel): void {
    this.minLevel = level;
  }

  /**
   * 格式化日志消息
   */
  private formatMessage(level: LogLevel, message: string, error?: Error | any, context?: Record<string, any>): string {
    const timestamp = new Date().toISOString();
    const contextStr = context ? ` ${JSON.stringify(context)}` : '';
    const errorStr = error ? `\n${error instanceof Error ? error.stack : error}` : '';

    return `[${timestamp}] [${level.toUpperCase()}] ${message}${contextStr}${errorStr}`;
  }

  /**
   * 检查是否应该输出日志
   */
  private shouldLog(level: LogLevel): boolean {
    if (!this.isEnabled) return false;

    const levels: Record<LogLevel, number> = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3,
    };

    return levels[level] >= levels[this.minLevel];
  }

  /**
   * 输出日志到控制台
   */
  private consoleLog(level: LogLevel, message: string, error?: Error | any, context?: Record<string, any>): void {
    if (!this.shouldLog(level)) return;

    const formattedMessage = this.formatMessage(level, message, error, context);

    switch (level) {
      case 'error':
        console.error(formattedMessage);
        break;
      case 'warn':
        console.warn(formattedMessage);
        break;
      case 'info':
        console.info(formattedMessage);
        break;
      case 'debug':
        console.debug(formattedMessage);
        break;
    }
  }

  /**
   * Debug 级别日志
   */
  public debug(message: string, context?: Record<string, any>): void {
    this.consoleLog('debug', message, undefined, context);
  }

  /**
   * Info 级别日志
   */
  public info(message: string, context?: Record<string, any>): void {
    this.consoleLog('info', message, undefined, context);
  }

  /**
   * Warn 级别日志
   */
  public warn(message: string, error?: Error | any, context?: Record<string, any>): void {
    this.consoleLog('warn', message, error, context);
  }

  /**
   * Error 级别日志
   */
  public error(message: string, error?: Error | any, context?: Record<string, any>): void {
    this.consoleLog('error', message, error, context);
  }

  /**
   * 记录 API 调用错误
   */
  public apiError(endpoint: string, error: Error | any, context?: Record<string, any>): void {
    this.error(`API Error: ${endpoint}`, error, { endpoint, ...context });
  }

  /**
   * 记录操作失败
   */
  public operationFailed(operation: string, error: Error | any, context?: Record<string, any>): void {
    this.error(`Operation failed: ${operation}`, error, { operation, ...context });
  }

  /**
   * 记录用户操作
   */
  public userAction(action: string, context?: Record<string, any>): void {
    this.info(`User action: ${action}`, context);
  }

  /**
   * 记录应用程序事件
   */
  public appEvent(event: string, context?: Record<string, any>): void {
    this.info(`App event: ${event}`, context);
  }
}

// 导出单例实例
export const logger = Logger.getInstance();

// 导出便捷方法
export const logDebug = (message: string, context?: Record<string, any>) => logger.debug(message, context);
export const logInfo = (message: string, context?: Record<string, any>) => logger.info(message, context);
export const logWarn = (message: string, error?: Error | any, context?: Record<string, any>) => logger.warn(message, error, context);
export const logError = (message: string, error?: Error | any, context?: Record<string, any>) => logger.error(message, error, context);
