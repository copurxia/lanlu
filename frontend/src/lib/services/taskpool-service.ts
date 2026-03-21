import { Task, TaskPageResult } from '@/types/task';
import { api, getApiUrl } from '@/lib/api';
import { buildQueryParams, parseApiPayload } from '@/lib/utils/api-utils';

export type TaskStreamPayload = {
  task: Task;
  event?: string;
  log?: string;
  logTail?: string;
  logDelta?: string;
  logBytes?: number;
  mode?: 'snapshot' | 'delta' | string;
  version?: number;
};

type TaskStreamHandlers = {
  onTask?: (task: Task, payload: TaskStreamPayload) => void;
  onDone?: (task: Task, payload: TaskStreamPayload) => void;
  onError?: (error: Error) => void;
  onOpen?: () => void;
};

type WaitTaskOptions = {
  timeoutMs?: number;
  onUpdate?: (task: Task, meta: { transport: 'sse'; log?: string; payload?: TaskStreamPayload }) => void;
};

/**
 * TaskPool Service - 使用新的 TaskPool API
 */
export class TaskPoolService {
  private static BASE_URL = '/api/admin/taskpool';

  /**
   * Get tasks with pagination
   */
  static async getTasks(page: number = 1, pageSize: number = 10, status?: string): Promise<TaskPageResult> {
    try {
      const qs = buildQueryParams({
        page: String(page),
        pageSize: String(pageSize),
      });
      if (status && status !== 'all') qs.set('status', status);

      const response = await api.get(`${this.BASE_URL}/tasks?${qs.toString()}`);

      if (response.success) {
        const data = parseApiPayload<any>(response.data, {});

        // 转换后端的下划线命名为前端的驼峰命名
        const tasks = Array.isArray(data.tasks)
          ? data.tasks.map((task: any) => this.normalizeTask(task))
          : [];

        const result = {
          tasks,
          total: typeof data.total === 'number' ? data.total : 0,
          totalAll: typeof data.totalAll === 'number' ? data.totalAll : undefined,
          page: typeof data.page === 'number' ? data.page : page,
          pageSize: typeof data.pageSize === 'number' ? data.pageSize : pageSize,
          totalPages: typeof data.totalPages === 'number' ? data.totalPages : 0
        };

        return result;
      } else {
        throw new Error(response.error || 'Failed to fetch tasks');
      }
    } catch (error) {
      console.error('Error fetching tasks:', error);
      // 返回空的默认结果
      return {
        tasks: [],
        total: 0,
        page,
        pageSize,
        totalPages: 0
      };
    }
  }

  /**
   * 标准化任务对象，将后端的下划线命名转换为前端的驼峰命名
   */
  private static normalizeTask(task: any): Task {
    return {
      id: task.id,
      name: task.name,
      status: task.status,
      progress: task.progress,
      message: task.message,
      taskType: task.task_type || task.taskType,
      pluginNamespace: task.plugin_namespace || task.pluginNamespace || '',
      parameters: this.parseTaskParameters(task.parameters),
      result: task.result || '',
      createdAt: task.created_at || task.createdAt || '',
      startedAt: task.started_at || task.startedAt || '',
      completedAt: task.completed_at || task.completedAt || '',
      priority: task.priority || 50,
      groupId: task.group_id || task.groupId || '',
      timeoutAt: task.timeout_at || task.timeoutAt || '',
      triggerSource: task.trigger_source || task.triggerSource || ''
    };
  }

  /**
   * Get task by ID
   */
  static async getTaskById(id: number): Promise<Task> {
    try {
      const response = await api.get(`${this.BASE_URL}/${id}`);

      if (response.success) {
        return this.normalizeTask(parseApiPayload<any>(response.data, {}));
      } else {
        throw new Error(response.error || 'Failed to fetch task');
      }
    } catch (error) {
      console.error('Error fetching task:', error);
      throw error;
    }
  }

  /**
   * Subscribe task updates from SSE endpoint.
   */
  static subscribeTask(taskId: number, handlers: TaskStreamHandlers = {}): () => void {
    if (typeof window === 'undefined' || typeof EventSource === 'undefined') {
      handlers.onError?.(new Error('EventSource is not available'));
      return () => {};
    }

    const streamPath = `${this.BASE_URL}/${taskId}/stream`;
    const streamUrl = getApiUrl(streamPath) || streamPath;
    const source = new EventSource(streamUrl, { withCredentials: true });
    let closed = false;

    const onPayload = (event: MessageEvent, forceDone: boolean = false) => {
      const parsed = this.parseTaskStreamPayload(event.data);
      if (!parsed) return;

      const payload = { ...parsed, event: event.type };
      handlers.onTask?.(parsed.task, payload);
      if (forceDone || this.isTerminalStatus(parsed.task.status)) {
        handlers.onDone?.(parsed.task, payload);
        closed = true;
        source.close();
      }
    };

    source.onopen = () => {
      if (closed) return;
      handlers.onOpen?.();
    };

    source.addEventListener('snapshot', (event) => {
      if (closed) return;
      onPayload(event as MessageEvent, false);
    });
    source.addEventListener('task', (event) => {
      if (closed) return;
      onPayload(event as MessageEvent, false);
    });
    source.addEventListener('done', (event) => {
      if (closed) return;
      onPayload(event as MessageEvent, true);
    });
    // Keep event source alive; no-op by design.
    source.addEventListener('ping', () => {});

    source.onerror = () => {
      if (closed) return;
      handlers.onError?.(new Error(`Task stream disconnected: ${taskId}`));
    };

    return () => {
      closed = true;
      source.close();
    };
  }

  /**
   * Wait task to reach terminal status using SSE only.
   */
  static async waitForTaskTerminal(taskId: number, options: WaitTaskOptions = {}): Promise<Task> {
    const timeoutMs = options.timeoutMs ?? 10 * 60 * 1000;

    if (typeof window === 'undefined' || typeof EventSource === 'undefined') {
      throw new Error('EventSource is not available');
    }

    return await new Promise<Task>((resolve, reject) => {
      let settled = false;
      let resolvingTerminal = false;
      let unsubscribe: () => void = () => {};
      let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
      let lastLog: string | undefined;
      let lastPayload: TaskStreamPayload | undefined;

      const finish = (task: Task) => {
        if (settled) return;
        settled = true;
        if (timeoutHandle) clearTimeout(timeoutHandle);
        unsubscribe();
        resolve(task);
      };

      const loadLatestTerminalTask = async (fallbackTask: Task): Promise<Task> => {
        try {
          const latestTask = await this.getTaskById(taskId);
          if (this.isTerminalStatus(latestTask.status)) {
            return latestTask;
          }
        } catch (error) {
          console.warn(`Failed to hydrate terminal task ${taskId}:`, error);
        }
        return fallbackTask;
      };

      const finishWithLatestTask = async (fallbackTask: Task) => {
        if (settled || resolvingTerminal) return;
        resolvingTerminal = true;
        const latestTask = await loadLatestTerminalTask(fallbackTask);
        options.onUpdate?.(latestTask, { transport: 'sse', log: lastLog, payload: lastPayload });
        finish(latestTask);
      };

      const recoverFromDisconnect = async () => {
        if (settled || resolvingTerminal) return;
        const latestTask = await loadLatestTerminalTask({
          id: taskId,
          name: '',
          status: 'running',
          progress: 0,
          message: '',
          taskType: '',
          pluginNamespace: '',
          parameters: {},
          result: '',
          createdAt: '',
          startedAt: '',
          completedAt: '',
          priority: 50,
          groupId: '',
          timeoutAt: '',
          triggerSource: ''
        });

        if (this.isTerminalStatus(latestTask.status)) {
          await finishWithLatestTask(latestTask);
        }
      };

      unsubscribe = this.subscribeTask(taskId, {
        onTask: (task, payload) => {
          lastPayload = payload;
          lastLog = payload.logDelta ?? payload.logTail ?? payload.log;
          options.onUpdate?.(task, { transport: 'sse', log: lastLog, payload });
          if (this.isTerminalStatus(task.status)) {
            void finishWithLatestTask(task);
          }
        },
        onDone: (task, payload) => {
          lastPayload = payload;
          lastLog = payload.logDelta ?? payload.logTail ?? payload.log;
          void finishWithLatestTask(task);
        },
        onError: () => {
          void recoverFromDisconnect();
        },
      });

      timeoutHandle = setTimeout(() => {
        if (settled) return;
        settled = true;
        unsubscribe();
        reject(new Error(`Task ${taskId} timeout`));
      }, timeoutMs);
    });
  }

  /**
   * Cancel a task
   */
  static async cancelTask(id: number): Promise<boolean> {
    try {
      const response = await api.post(`${this.BASE_URL}/${id}/cancel`);

      if (response.success) {
        return true;
      } else {
        throw new Error(response.error || 'Failed to cancel task');
      }
    } catch (error) {
      console.error('Error cancelling task:', error);
      return false;
    }
  }

  /**
   * Retry a failed task
   */
  static async retryTask(id: number): Promise<{ success: boolean; new_task_id?: number }> {
    try {
      const response = await api.post(`${this.BASE_URL}/${id}/retry`);

      if (response.success) {
        return {
          success: true,
          new_task_id: response.data?.new_task_id
        };
      } else {
        throw new Error(response.error || 'Failed to retry task');
      }
    } catch (error) {
      console.error('Error retrying task:', error);
      return { success: false };
    }
  }

  /**
   * Respond to a running task rpc select request.
   */
  static async respondRpcSelect(taskId: number, requestId: string, selectedIndex: number): Promise<boolean> {
    try {
      const response = await api.post(`${this.BASE_URL}/${taskId}/rpc/select`, {
        request_id: requestId,
        selected_index: selectedIndex,
      });
      return !!response.success;
    } catch (error) {
      console.error('Error responding rpc select:', error);
      return false;
    }
  }

  static async abortRpcSelect(taskId: number, requestId: string): Promise<boolean> {
    try {
      const response = await api.post(`${this.BASE_URL}/${taskId}/rpc/select`, {
        request_id: requestId,
        abort: 1,
      });
      return !!response.success;
    } catch (error) {
      console.error('Error aborting rpc select:', error);
      return false;
    }
  }

  /**
   * Get task status color for UI display
   */
  static getStatusColor(status: string): string {
    if (!status) {
      return 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200';
    }
    switch (status.toLowerCase()) {
      case 'pending':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200';
      case 'running':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      case 'completed':
        return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200';
      case 'failed':
        return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
      case 'stopped':
        return 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200';
      default:
        return 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200';
    }
  }

  /**
   * Get task type color for UI display
   */
  static getTaskTypeColor(taskType: string): string {
    if (!taskType) {
      return 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200';
    }
    switch (taskType.toLowerCase()) {
      case 'upload':
      case 'asset_upload':
      case 'upload_process':
      case 'asset_upload_process':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200';
      case 'archive_asset_consume':
        return 'bg-violet-100 text-violet-800 dark:bg-violet-900 dark:text-violet-200';
      case 'tag_asset_consume':
      case 'avatar_asset_consume':
      case 'plugin_asset_consume':
        return 'bg-rose-100 text-rose-800 dark:bg-rose-900 dark:text-rose-200';
      case 'scan_all_categories':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      case 'scan_single_category':
        return 'bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200';
      case 'scan_archive':
        return 'bg-cyan-100 text-cyan-800 dark:bg-cyan-900 dark:text-cyan-200';
      case 'generate_thumbnail':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200';
      case 'generate_category_cover':
        return 'bg-fuchsia-100 text-fuchsia-800 dark:bg-fuchsia-900 dark:text-fuchsia-200';
      case 'check_database':
        return 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200';
      case 'scan_plugins':
        return 'bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-200';
      default:
        return 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200';
    }
  }

  /**
   * Get task type label for display
   */
  static getTaskTypeLabel(taskType: string): string {
    if (!taskType) {
      return '未知任务';
    }
    switch (taskType.toLowerCase()) {
      case 'upload':
      case 'asset_upload':
      case 'upload_process':
      case 'asset_upload_process':
        return '资源上传';
      case 'archive_asset_consume':
        return '档案资产消费';
      case 'tag_asset_consume':
        return '标签资产消费';
      case 'avatar_asset_consume':
        return '头像资产消费';
      case 'plugin_asset_consume':
        return '插件资产消费';
      case 'scan_all_categories':
        return '扫描所有分类';
      case 'scan_single_category':
        return '扫描分类';
      case 'scan_archive':
        return '档案扫描';
      case 'generate_thumbnail':
        return '生成缩略图';
      case 'generate_category_cover':
        return '生成分类封面';
      case 'check_database':
        return '数据库检查';
      case 'scan_plugins':
        return '插件扫描';
      default:
        return taskType;
    }
  }

  /**
   * Get task status label for display
   */
  static getStatusLabel(status: string, t?: (key: string) => string): string {
    if (!status) {
      return t ? t('settings.taskManagement.unknown') : '未知';
    }
    
    if (t) {
      switch (status.toLowerCase()) {
        case 'pending':
          return t('settings.taskManagement.pending');
        case 'running':
          return t('settings.taskManagement.running');
        case 'completed':
          return t('settings.taskManagement.completed');
        case 'failed':
          return t('settings.taskManagement.failed');
        case 'stopped':
          return t('settings.taskManagement.stopped');
        default:
          return status;
      }
    } else {
      switch (status.toLowerCase()) {
        case 'pending':
          return '待执行';
        case 'running':
          return '执行中';
        case 'completed':
          return '已完成';
        case 'failed':
          return '失败';
        case 'stopped':
          return '已停止';
        default:
          return status;
      }
    }
  }

  /**
   * Format task duration
   */
  static formatTaskDuration(startTime: string, endTime: string): string {
    if (!startTime || !endTime) return '-';

    const start = new Date(startTime);
    const end = new Date(endTime);
    const duration = end.getTime() - start.getTime();

    if (duration < 1000) return `${duration}ms`;
    if (duration < 60000) return `${(duration / 1000).toFixed(1)}s`;
    if (duration < 3600000) return `${(duration / 60000).toFixed(1)}min`;

    return `${(duration / 3600000).toFixed(1)}h`;
  }

  /**
   * Parse task parameters JSON
   */
  static parseTaskParameters(parameters: string | Record<string, any>): Record<string, any> {
    try {
      // 如果是字符串，尝试解析为JSON
      if (typeof parameters === 'string') {
        if (parameters.trim() === '') return {};
        return JSON.parse(parameters);
      }

      // 如果已经是对象，直接返回
      if (parameters && typeof parameters === 'object') {
        return parameters;
      }

      return {};
    } catch (error) {
      console.warn('Failed to parse task parameters:', error);
      return {};
    }
  }

  /**
   * Format file size
   */
  static formatFileSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  /**
   * Get priority label
   */
  static getPriorityLabel(priority: number): string {
    if (priority <= 10) return '最高';
    if (priority <= 20) return '高';
    if (priority <= 30) return '中';
    if (priority <= 40) return '低';
    return '最低';
  }

  /**
   * Get priority color
   */
  static getPriorityColor(priority: number): string {
    if (priority <= 10) return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
    if (priority <= 20) return 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200';
    if (priority <= 30) return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200';
    if (priority <= 40) return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
    return 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200';
  }

  /**
   * Get trigger source label for display
   */
  static getTriggerSourceLabel(source: string): string {
    if (!source) return '未知';
    switch (source.toLowerCase()) {
      case 'manual':
        return '手动';
      case 'upload':
      case 'asset_upload':
        return '上传';
      case 'upload_process':
      case 'asset_upload_process':
        return '上传处理';
      case 'archive_asset_consume':
        return '档案资产消费';
      case 'tag_asset_consume':
        return '标签资产消费';
      case 'avatar_asset_consume':
        return '头像资产消费';
      case 'scan_all_categories':
        return '扫描所有分类';
      case 'scan_single_category':
        return '扫描分类';
      case 'scan_archive':
        return '扫描档案';
      case 'check_database':
        return '数据库检查';
      case 'generate_thumbnail':
        return '生成缩略图';
      default:
        return source;
    }
  }

  private static parseTaskStreamPayload(raw: unknown): TaskStreamPayload | null {
    if (typeof raw !== 'string' || raw.trim() === '') return null;

    try {
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object') return null;

      const taskCandidate = (parsed as any).task ?? parsed;
      if (!taskCandidate || typeof taskCandidate !== 'object') return null;

      const task = this.normalizeTask(taskCandidate);
      const stream = (parsed as any).stream;
      const log = typeof (parsed as any).log === 'string' ? (parsed as any).log : undefined;
      const logTail =
        typeof stream?.log_tail === 'string'
          ? stream.log_tail
          : typeof (parsed as any).log_tail === 'string'
            ? (parsed as any).log_tail
            : undefined;
      const logDelta =
        typeof stream?.log_delta === 'string'
          ? stream.log_delta
          : typeof (parsed as any).log_delta === 'string'
            ? (parsed as any).log_delta
            : undefined;
      const logBytes =
        typeof stream?.log_bytes === 'number'
          ? stream.log_bytes
          : typeof (parsed as any).log_bytes === 'number'
            ? (parsed as any).log_bytes
            : undefined;
      const mode =
        typeof stream?.mode === 'string'
          ? stream.mode
          : typeof (parsed as any).mode === 'string'
            ? (parsed as any).mode
            : undefined;
      const version = typeof (parsed as any).v === 'number' ? (parsed as any).v : undefined;

      return { task, log, logTail, logDelta, logBytes, mode, version };
    } catch {
      return null;
    }
  }

  private static isTerminalStatus(status: string): boolean {
    return status === 'completed' || status === 'failed' || status === 'stopped';
  }
}
