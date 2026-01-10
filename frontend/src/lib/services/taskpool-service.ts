import { Task, TaskPageResult } from '@/types/task';
import { api } from '@/lib/api';

/**
 * TaskPool Service - 使用新的 TaskPool API
 */
export class TaskPoolService {
  private static BASE_URL = '/api/taskpool';

  /**
   * Get tasks with pagination
   */
  static async getTasks(page: number = 1, pageSize: number = 10): Promise<TaskPageResult> {
    try {
      const response = await api.get(`${this.BASE_URL}/tasks?page=${page}&pageSize=${pageSize}`);

      if (response.success) {
        let data = response.data;

        // 如果response.data是字符串，需要解析为JSON
        if (typeof response.data === 'string') {
          try {
            data = JSON.parse(response.data);
          } catch (parseError) {
            console.error('Failed to parse response.data as JSON:', parseError);
            throw new Error('Invalid JSON response from server');
          }
        }

        // 转换后端的下划线命名为前端的驼峰命名
        const tasks = Array.isArray(data.tasks)
          ? data.tasks.map((task: any) => this.normalizeTask(task))
          : [];

        const result = {
          tasks,
          total: typeof data.total === 'number' ? data.total : 0,
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
        return this.normalizeTask(response.data);
      } else {
        throw new Error(response.error || 'Failed to fetch task');
      }
    } catch (error) {
      console.error('Error fetching task:', error);
      throw error;
    }
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
   * Get tasks by group ID
   */
  static async getTasksByGroup(groupId: string): Promise<Task[]> {
    try {
      const response = await api.get(`${this.BASE_URL}/group/${groupId}`);

      if (response.success) {
        return Array.isArray(response.data)
          ? response.data.map((task: any) => this.normalizeTask(task))
          : [];
      } else {
        throw new Error(response.error || 'Failed to fetch tasks by group');
      }
    } catch (error) {
      console.error('Error fetching tasks by group:', error);
      return [];
    }
  }

  /**
   * Cancel all tasks in a group
   */
  static async cancelTasksByGroup(groupId: string): Promise<{ success: boolean; cancelled_count: number }> {
    try {
      const response = await api.post(`${this.BASE_URL}/group/${groupId}/cancel`);

      if (response.success) {
        return {
          success: true,
          cancelled_count: response.data?.cancelled_count || 0
        };
      } else {
        throw new Error(response.error || 'Failed to cancel tasks by group');
      }
    } catch (error) {
      console.error('Error cancelling tasks by group:', error);
      return { success: false, cancelled_count: 0 };
    }
  }

  /**
   * Get task metrics
   */
  static async getMetrics(): Promise<any> {
    try {
      const response = await api.get(`${this.BASE_URL}/metrics`);

      if (response.success) {
        return response.data;
      } else {
        throw new Error(response.error || 'Failed to fetch metrics');
      }
    } catch (error) {
      console.error('Error fetching metrics:', error);
      return null;
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
      case 'upload_process':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200';
      case 'scan_all_categories':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      case 'scan_single_category':
        return 'bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200';
      case 'scan_archive':
        return 'bg-cyan-100 text-cyan-800 dark:bg-cyan-900 dark:text-cyan-200';
      case 'generate_thumbnail':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200';
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
      case 'upload_process':
        return '文件上传';
      case 'scan_all_categories':
        return '扫描所有分类';
      case 'scan_single_category':
        return '扫描分类';
      case 'scan_archive':
        return '档案扫描';
      case 'generate_thumbnail':
        return '生成缩略图';
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
        return '上传';
      case 'upload_process':
        return '上传处理';
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
}
