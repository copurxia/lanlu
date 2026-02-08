/**
 * 插件参数定义
 */
export interface PluginParameter {
  type: 'string' | 'int' | 'bool';
  name?: string;
  desc: string;
  default_value?: string;
  value?: any;
}

/**
 * 插件元数据
 */
export interface PluginInfo {
  name: string;
  type: 'metadata' | 'login' | 'download' | 'script';
  namespace: string;
  login_from?: string;
  author: string;
  version: string;
  description: string;
  parameters: PluginParameter[];
  oneshot_arg?: string;
  cooldown?: number;
  url_regex?: string;
  icon?: string;
  permissions?: string[];
  update_url?: string;  // 插件更新地址
  // Script plugins can optionally declare a default cron registration.
  // If omitted, backend may create a disabled scheduled task with a safe default cron expression.
  cron_expression?: string;
  cron_enabled?: boolean;
  cron_priority?: number;
  cron_timeout_seconds?: number;
}

/**
 * 插件执行结果
 */
export interface PluginResult {
  success: boolean;
  data?: any;
  error?: string;
}

/**
 * 插件输入（从 stdin 读取）
 */

export interface HostSelectOption {
  label: string;
  description?: string;
  cover?: string;
}

export interface HostSelectResult {
  index: number;
}
export interface PluginInput {
  action: 'plugin_info' | 'run';
  pluginType: string;
  pluginDir?: string;  // 插件工作目录，由系统传入
  archiveId?: string;
  archiveTitle?: string;
  existingTags?: string;
  thumbnailHash?: string;
  oneshotParam?: string;
  params?: Record<string, any>;
  loginCookies?: Array<{ name: string; value: string; domain?: string; path?: string }>;
  url?: string;
}

/**
 * 插件基础接口
 */
export abstract class BasePlugin {
  protected input: PluginInput | null = null;
  private rpcSeq = 0;
  private stdinLineReader: StdinLineReader | null = null;

  abstract getPluginInfo(): PluginInfo;

  private getLineReader(): StdinLineReader {
    if (!this.stdinLineReader) this.stdinLineReader = new StdinLineReader();
    return this.stdinLineReader;
  }

  /**
   * 从 stdin 读取输入（逐行读取，避免等待 EOF）
   */
  protected async readInput(): Promise<PluginInput> {
    const reader = Deno.stdin.readable.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      // 检查是否有完整的 JSON 行（以换行符结尾）
      const newlineIndex = buffer.indexOf('\n');
      if (newlineIndex !== -1) {
        const jsonLine = buffer.slice(0, newlineIndex).trim();
        reader.releaseLock();
        if (jsonLine) {
          return JSON.parse(jsonLine) as PluginInput;
        }
      }
    }

    // 如果没有换行符，尝试解析整个 buffer
    reader.releaseLock();
    const trimmed = buffer.trim();
    if (trimmed) {
      return JSON.parse(trimmed) as PluginInput;
    }

    throw new Error('No input received from stdin');
  }

  /**
   * Read a single NDJSON line from stdin (used for host RPC responses).
   */
  private async readLineFromStdin(): Promise<string> {
    // Important: keep a persistent buffer so we don't drop lines when a single read contains multiple NDJSON messages.
    return this.getLineReader().readLine();
  }

  /**
   * Call back into the host/backend via stdio NDJSON.
   * Host must support:
   *   {"type":"call","id":"...","method":"...","params":{...}}
   * and reply with:
   *   {"type":"call_result","id":"...","success":true,"data":...}
   */
  protected async callHost<T = unknown>(method: string, params: unknown = {}): Promise<T> {
    const id = `${Date.now()}_${++this.rpcSeq}`;
    console.log(JSON.stringify({ type: 'call', id, method, params }));

    while (true) {
      const line = await this.readLineFromStdin();
      if (!line) continue;
      let msg: any;
      try {
        msg = JSON.parse(line);
      } catch {
        continue;
      }
      if (msg?.type !== 'call_result' || msg?.id !== id) continue;
      if (msg?.success) return msg.data as T;
      throw new Error(String(msg?.error ?? 'host call failed'));
    }
  }


  protected async hostSelect(
    title: string,
    options: HostSelectOption[],
    options2?: { message?: string; defaultIndex?: number; timeoutSeconds?: number }
  ): Promise<number> {
    if (!Array.isArray(options) || options.length === 0) {
      throw new Error('hostSelect requires at least one option');
    }
    const res = await this.callHost<HostSelectResult>('ui.select', {
      title,
      message: options2?.message || '',
      options,
      defaultIndex: Number.isFinite(options2?.defaultIndex as number) ? Math.trunc(options2!.defaultIndex as number) : 0,
      timeoutSeconds: Number.isFinite(options2?.timeoutSeconds as number) ? Math.trunc(options2!.timeoutSeconds as number) : 90,
    });
    const idx = Number((res as any)?.index);
    if (!Number.isFinite(idx)) return 0;
    const n = Math.trunc(idx);
    if (n < 0 || n >= options.length) return 0;
    return n;
  }

  /**
   * 输出进度消息
   */
  protected reportProgress(progress: number, message: string): void {
    console.log(JSON.stringify({ type: 'progress', progress, message }));
  }

  /**
   * 输出流式数据
   */
  protected emitData(key: string, value: unknown): void {
    console.log(JSON.stringify({ type: 'data', key, value }));
  }

  protected async log(level: 'DEBUG' | 'INFO' | 'WARN' | 'ERROR', message: string, meta?: unknown): Promise<void> {
    // 输出到 stdout 作为 NDJSON 消息
    console.log(JSON.stringify({ type: 'log', level, message: meta ? `${message} ${this.safeJson(meta)}` : message }));
  }

  protected logDebug(message: string, meta?: unknown): Promise<void> {
    return this.log('DEBUG', message, meta);
  }
  protected logInfo(message: string, meta?: unknown): Promise<void> {
    return this.log('INFO', message, meta);
  }
  protected logWarn(message: string, meta?: unknown): Promise<void> {
    return this.log('WARN', message, meta);
  }
  protected logError(message: string, meta?: unknown): Promise<void> {
    return this.log('ERROR', message, meta);
  }

  /**
   * 处理命令 - 从 stdin 读取输入
   */
  async handleCommand(): Promise<void> {
    try {
      this.input = await this.readInput();

      switch (this.input.action) {
        case 'plugin_info':
          await this.outputPluginInfo();
          break;
        case 'run':
          await this.runPlugin(this.input);
          break;
        default:
          this.outputResult({ success: false, error: 'Invalid action' });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Failed to read input: ${errorMessage}` });
    }
  }

  /**
   * 输出插件信息JSON（作为 result 类型）
   */
  protected async outputPluginInfo(): Promise<void> {
    const info = this.getPluginInfo();
    console.log(JSON.stringify({ type: 'result', success: true, data: info }));
  }

  /**
   * 运行插件逻辑（由子类实现）
   */
  protected abstract runPlugin(input: PluginInput): Promise<void>;

  /**
   * 输出执行结果JSON（NDJSON 格式）
   */
  protected outputResult(result: PluginResult): void {
    console.log(JSON.stringify({ type: 'result', ...result }));
  }

  /**
   * 兼容旧插件：输出错误结果
   */
  protected outputError(message: string): void {
    this.outputResult({ success: false, error: message });
  }

  /**
   * 获取参数（从 input 中提取并进行类型转换）
   */
  protected getParams(): Record<string, any> {
    if (!this.input?.params) {
      return {};
    }
    return this.coerceParamsFromSchema(this.input.params);
  }

  private coerceParamsFromSchema(params: Record<string, unknown>): Record<string, unknown> {
    const info = this.getPluginInfo();
    const schema = info?.parameters || [];
    const out: Record<string, unknown> = { ...params };

    for (const def of schema) {
      const name = def?.name;
      if (!name) continue;
      if (!(name in out)) continue;

      const value = out[name];
      if (def.type === 'bool') {
        out[name] = this.coerceBool(value);
      } else if (def.type === 'int') {
        const coerced = this.coerceInt(value);
        if (coerced !== undefined) out[name] = coerced;
      } else if (def.type === 'string') {
        if (value === null || value === undefined) out[name] = '';
        else out[name] = String(value);
      }
    }

    return out;
  }

  private coerceBool(value: unknown): boolean {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') return value !== 0;
    if (typeof value === 'string') {
      const v = value.trim().toLowerCase();
      if (v === '' || v === '0' || v === 'false' || v === 'no' || v === 'n' || v === 'off') return false;
      if (v === '1' || v === 'true' || v === 'yes' || v === 'y' || v === 'on') return true;
      return v !== '0';
    }
    return Boolean(value);
  }

  private coerceInt(value: unknown): number | undefined {
    if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
    if (typeof value === 'string') {
      const v = value.trim();
      if (v === '') return 0;
      const n = Number.parseInt(v, 10);
      return Number.isNaN(n) ? undefined : n;
    }
    return undefined;
  }

  private safeJson(value: unknown): string {
    try {
      return JSON.stringify(value);
    } catch {
      return '"<unserializable>"';
    }
  }
}

class StdinLineReader {
  private reader: ReadableStreamDefaultReader<Uint8Array>;
  private decoder = new TextDecoder();
  private buffer = '';

  constructor() {
    this.reader = Deno.stdin.readable.getReader();
  }

  async readLine(): Promise<string> {
    while (true) {
      const idx = this.buffer.indexOf('\n');
      if (idx !== -1) {
        const line = this.buffer.slice(0, idx).replace(/\r$/, '').trim();
        this.buffer = this.buffer.slice(idx + 1);
        return line;
      }

      const { done, value } = await this.reader.read();
      if (done) {
        const remaining = this.buffer.replace(/\r$/, '').trim();
        this.buffer = '';
        return remaining;
      }

      this.buffer += this.decoder.decode(value, { stream: true });
    }
  }
}
