// Task types for the LANLU application

export interface Task {
  id: number;
  name: string;
  status: 'pending' | 'running' | 'waiting' | 'completed' | 'failed' | 'stopped';
  progress: number;
  message: string;
  phase?: string;
  waitingReason?: string;
  activeKey?: string;
  taskType: string;
  pluginNamespace: string;
  parameters: Record<string, any>;
  result: string;
  createdAt: string;
  startedAt: string;
  completedAt: string;
  // 新增字段
  priority: number;
  groupId: string;
  timeoutAt: string;
  triggerSource: string;
}

export interface TaskPageResult {
  tasks: Task[];
  total: number;
  /** Total tasks across all statuses (for "All" badge while filtered). */
  totalAll?: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

export interface TaskListResponse {
  success: boolean;
  data: TaskPageResult;
  error?: string;
}

export interface TaskResponse {
  success: boolean;
  data: Task;
  error?: string;
}
