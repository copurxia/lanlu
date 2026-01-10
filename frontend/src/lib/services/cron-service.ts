import { api } from '@/lib/api';

/**
 * 定时任务类型
 */
export interface ScheduledTask {
  id: number;
  name: string;
  cronExpression: string;
  taskType: string;
  taskParameters: string;
  enabled: boolean;
  priority: number;
  timeoutSeconds: number;
  lastRunAt: string;
  lastRunSuccess: boolean;
  lastRunError: string;
  nextRunAt: string;
  runCount: number;
  createdAt: string;
  updatedAt: string;
}

/**
 * 定时任务分页结果
 */
export interface ScheduledTaskPageResult {
  tasks: ScheduledTask[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

/**
 * CronService 状态
 */
export interface CronServiceStatus {
  running: boolean;
  totalTasks: number;
  enabledTasks: number;
}

/**
 * Cron 表达式验证结果
 */
export interface CronValidationResult {
  valid: boolean;
  error: string;
  nextRuns: string[];
}

/**
 * 创建/更新定时任务的参数
 */
export interface ScheduledTaskInput {
  name: string;
  cronExpression: string;
  taskType: string;
  taskParameters?: string;
  enabled?: boolean;
  priority?: number;
  timeoutSeconds?: number;
}

/**
 * Cron Service - 定时任务管理 API
 */
export class CronService {
  private static BASE_URL = '/api/cron';

  /**
   * 获取 CronService 状态
   */
  static async getStatus(): Promise<CronServiceStatus> {
    try {
      const response = await api.get(`${this.BASE_URL}/status`);
      if (response.success) {
        let data = response.data;
        if (typeof data === 'string') {
          data = JSON.parse(data);
        }
        return {
          running: data.running ?? false,
          totalTasks: data.totalTasks ?? 0,
          enabledTasks: data.enabledTasks ?? 0,
        };
      }
      throw new Error(response.error || 'Failed to get cron service status');
    } catch (error) {
      console.error('Error getting cron service status:', error);
      return { running: false, totalTasks: 0, enabledTasks: 0 };
    }
  }

  /**
   * 启动 CronService
   */
  static async start(): Promise<boolean> {
    try {
      const response = await api.post(`${this.BASE_URL}/start`);
      return response.success === true;
    } catch (error) {
      console.error('Error starting cron service:', error);
      return false;
    }
  }

  /**
   * 停止 CronService
   */
  static async stop(): Promise<boolean> {
    try {
      const response = await api.post(`${this.BASE_URL}/stop`);
      return response.success === true;
    } catch (error) {
      console.error('Error stopping cron service:', error);
      return false;
    }
  }

  /**
   * 验证 Cron 表达式
   */
  static async validateExpression(expression: string): Promise<CronValidationResult> {
    try {
      const response = await api.post(`${this.BASE_URL}/validate`, { expression });
      if (response.success) {
        let data = response.data;
        if (typeof data === 'string') {
          data = JSON.parse(data);
        }
        return {
          valid: data.valid ?? false,
          error: data.error ?? '',
          nextRuns: data.nextRuns ?? [],
        };
      }
      return { valid: false, error: response.error || 'Validation failed', nextRuns: [] };
    } catch (error) {
      console.error('Error validating cron expression:', error);
      return { valid: false, error: 'Validation request failed', nextRuns: [] };
    }
  }

  /**
   * 获取定时任务列表（分页）
   */
  static async getTasks(page: number = 1, pageSize: number = 10): Promise<ScheduledTaskPageResult> {
    try {
      const response = await api.get(`${this.BASE_URL}/tasks?page=${page}&pageSize=${pageSize}`);
      if (response.success) {
        let data = response.data;
        if (typeof data === 'string') {
          data = JSON.parse(data);
        }
        const tasks = Array.isArray(data.tasks)
          ? data.tasks.map((task: any) => this.normalizeTask(task))
          : [];
        return {
          tasks,
          total: data.total ?? 0,
          page: data.page ?? page,
          pageSize: data.pageSize ?? pageSize,
          totalPages: data.totalPages ?? 0,
        };
      }
      throw new Error(response.error || 'Failed to fetch scheduled tasks');
    } catch (error) {
      console.error('Error fetching scheduled tasks:', error);
      return { tasks: [], total: 0, page, pageSize, totalPages: 0 };
    }
  }

  /**
   * 获取单个定时任务
   */
  static async getTask(id: number): Promise<ScheduledTask | null> {
    try {
      const response = await api.get(`${this.BASE_URL}/tasks/${id}`);
      if (response.success) {
        let data = response.data;
        if (typeof data === 'string') {
          data = JSON.parse(data);
        }
        return this.normalizeTask(data);
      }
      return null;
    } catch (error) {
      console.error('Error fetching scheduled task:', error);
      return null;
    }
  }

  /**
   * 创建定时任务
   */
  static async createTask(input: ScheduledTaskInput): Promise<{ success: boolean; task?: ScheduledTask; error?: string }> {
    try {
      const response = await api.post(`${this.BASE_URL}/tasks`, input);
      if (response.success) {
        let data = response.data;
        if (typeof data === 'string') {
          data = JSON.parse(data);
        }
        return {
          success: true,
          task: data.task ? this.normalizeTask(data.task) : undefined,
        };
      }
      return { success: false, error: response.error || 'Failed to create task' };
    } catch (error: any) {
      console.error('Error creating scheduled task:', error);
      return { success: false, error: error?.message || 'Failed to create task' };
    }
  }

  /**
   * 更新定时任务
   */
  static async updateTask(id: number, input: Partial<ScheduledTaskInput>): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await api.put(`${this.BASE_URL}/tasks/${id}`, input);
      return { success: response.success === true, error: response.error };
    } catch (error: any) {
      console.error('Error updating scheduled task:', error);
      return { success: false, error: error?.message || 'Failed to update task' };
    }
  }

  /**
   * 删除定时任务
   */
  static async deleteTask(id: number): Promise<boolean> {
    try {
      const response = await api.delete(`${this.BASE_URL}/tasks/${id}`);
      return response.success === true;
    } catch (error) {
      console.error('Error deleting scheduled task:', error);
      return false;
    }
  }

  /**
   * 手动触发定时任务
   */
  static async triggerTask(id: number): Promise<boolean> {
    try {
      const response = await api.post(`${this.BASE_URL}/tasks/${id}/trigger`);
      return response.success === true;
    } catch (error) {
      console.error('Error triggering scheduled task:', error);
      return false;
    }
  }

  /**
   * 启用定时任务
   */
  static async enableTask(id: number): Promise<boolean> {
    try {
      const response = await api.post(`${this.BASE_URL}/tasks/${id}/enable`);
      return response.success === true;
    } catch (error) {
      console.error('Error enabling scheduled task:', error);
      return false;
    }
  }

  /**
   * 禁用定时任务
   */
  static async disableTask(id: number): Promise<boolean> {
    try {
      const response = await api.post(`${this.BASE_URL}/tasks/${id}/disable`);
      return response.success === true;
    } catch (error) {
      console.error('Error disabling scheduled task:', error);
      return false;
    }
  }

  /**
   * 标准化任务对象
   */
  private static normalizeTask(task: any): ScheduledTask {
    // 确保 taskParameters 是字符串
    let taskParams = task.task_parameters ?? task.taskParameters ?? '';
    if (typeof taskParams === 'object' && taskParams !== null) {
      taskParams = JSON.stringify(taskParams);
    }

    return {
      id: task.id ?? 0,
      name: task.name ?? '',
      cronExpression: task.cron_expression ?? task.cronExpression ?? '',
      taskType: task.task_type ?? task.taskType ?? '',
      taskParameters: taskParams,
      enabled: task.enabled ?? false,
      priority: task.priority ?? 50,
      timeoutSeconds: task.timeout_seconds ?? task.timeoutSeconds ?? 3600,
      lastRunAt: task.last_run_at ?? task.lastRunAt ?? '',
      lastRunSuccess: task.last_run_success ?? task.lastRunSuccess ?? false,
      lastRunError: task.last_run_error ?? task.lastRunError ?? '',
      nextRunAt: task.next_run_at ?? task.nextRunAt ?? '',
      runCount: task.run_count ?? task.runCount ?? 0,
      createdAt: task.created_at ?? task.createdAt ?? '',
      updatedAt: task.updated_at ?? task.updatedAt ?? '',
    };
  }

  /**
   * 获取任务类型标签
   */
  static getTaskTypeLabel(taskType: string): string {
    switch (taskType) {
      case 'scan_all_categories':
        return '扫描所有分类';
      case 'scan_single_category':
        return '扫描分类';
      case 'check_database':
        return '数据库检查';
      case 'scan_plugins':
        return '插件扫描';
      case 'generate_thumbnail':
        return '生成缩略图';
      default:
        return taskType;
    }
  }

  /**
   * 获取任务类型颜色
   */
  static getTaskTypeColor(taskType: string): string {
    switch (taskType) {
      case 'scan_all_categories':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      case 'scan_single_category':
        return 'bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200';
      case 'scan_archive':
        return 'bg-cyan-100 text-cyan-800 dark:bg-cyan-900 dark:text-cyan-200';
      case 'check_database':
        return 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200';
      case 'scan_plugins':
        return 'bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-200';
      case 'generate_thumbnail':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200';
      default:
        return 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200';
    }
  }

  /**
   * 常用 Cron 表达式预设
   */
  static readonly CRON_PRESETS = [
    { label: '每小时', value: '0 * * * *' },
    { label: '每6小时', value: '0 */6 * * *' },
    { label: '每12小时', value: '0 */12 * * *' },
    { label: '每天凌晨1点', value: '0 1 * * *' },
    { label: '每天凌晨2点', value: '0 2 * * *' },
    { label: '每天凌晨3点', value: '0 3 * * *' },
    { label: '每周一凌晨2点', value: '0 2 * * 1' },
    { label: '每月1日凌晨2点', value: '0 2 1 * *' },
  ];

  /**
   * 可用的任务类型
   */
  static readonly TASK_TYPES = [
    { value: 'scan_all_categories', label: '扫描所有分类', description: '扫描所有启用的分类，发现新文件' },
    { value: 'scan_single_category', label: '扫描单个分类', description: '扫描指定分类的目录，发现新文件' },
    { value: 'check_database', label: '数据库检查', description: '检查数据库一致性，清理无效记录' },
    { value: 'scan_plugins', label: '插件扫描', description: '扫描并加载插件' },
  ];
}
