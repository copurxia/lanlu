import {apiClient, buildApiUrl} from './client';
import type {ApiEnvelope} from '../types/api';
import EventSource from 'react-native-sse';
import {getStoredToken} from '../storage/token';
import {getActiveServer} from '../storage/servers';

// ─── Admin Types ───────────────────────────────────────────────────────────

export type AdminTag = {
  id: number;
  namespace: string;
  name: string;
  translations?: Record<string, {text?: string; intro?: string}>;
  links?: string;
  iconAssetId?: number;
  backgroundAssetId?: number;
  created_at?: string;
  updated_at?: string;
};

export type AdminUser = {
  id: number;
  username: string;
  isAdmin: boolean;
  createdAt?: string;
};

export type SystemSetting = {
  id: number;
  key: string;
  value: string;
  valueType: string;
  category: string;
  description?: Record<string, string>;
  isEncrypted?: boolean;
};

export type CronStatus = {
  running: boolean;
  totalTasks: number;
  enabledTasks: number;
};

export type ScheduledTask = {
  id: number;
  name: string;
  cronExpression: string;
  taskType: string;
  taskParameters?: string;
  enabled: boolean;
  priority?: number;
  timeoutSeconds?: number;
  lastRunAt?: string;
  lastRunSuccess?: boolean;
  lastRunError?: string;
  nextRunAt?: string;
  runCount?: number;
  createdAt?: string;
  updatedAt?: string;
};

export type TaskPoolTask = {
  id: number;
  name: string;
  status: string;
  progress?: number;
  message?: string;
  phase?: string;
  taskType?: string;
  createdAt?: string;
  startedAt?: string;
  completedAt?: string;
};

export type Plugin = {
  id: number;
  name: string;
  namespace: string;
  version?: string;
  plugin_type: string;
  author?: string;
  description?: string;
  enabled: boolean;
  installed: boolean;
  update_url?: string;
  has_schema?: boolean;
  icon?: string;
  created_at?: string;
  updated_at?: string;
};

export type TagCloudItem = {
  tag: string;
  display: string;
  count: number;
};

// ─── Categories ────────────────────────────────────────────────────────────

export async function createCategory(params: {
  name: string;
  scan_path?: string;
  description?: string;
  icon?: string;
  sort_order?: number;
  enabled?: boolean;
  plugins?: string[];
}): Promise<ApiEnvelope<unknown>> {
  const response = await apiClient.post<ApiEnvelope<unknown>>('/api/categories', params);
  return response.data;
}

export async function updateCategory(
  catid: string,
  params: {
    name?: string;
    scan_path?: string;
    description?: string;
    icon?: string;
    sort_order?: number;
    enabled?: boolean;
    plugins?: string[];
  },
): Promise<ApiEnvelope<unknown>> {
  const response = await apiClient.put<ApiEnvelope<unknown>>(`/api/categories/${catid}`, params);
  return response.data;
}

export async function deleteCategory(catid: string): Promise<void> {
  await apiClient.delete(`/api/categories/${catid}`);
}

export async function scanCategory(catid: string): Promise<void> {
  await apiClient.post(`/api/categories/${catid}/scan`, {});
}

export async function scanMediaLibrary(): Promise<void> {
  await apiClient.post('/api/categories/scan', {});
}

// ─── Admin Tags ────────────────────────────────────────────────────────────

export async function adminListTags(params?: {
  q?: string;
  limit?: number;
  offset?: number;
  namespace?: string;
}): Promise<ApiEnvelope<{items?: AdminTag[]; total?: number}>> {
  const response = await apiClient.get<ApiEnvelope<{items?: AdminTag[]; total?: number}>>('/api/tags', {
    params: {
      q: params?.q || undefined,
      limit: params?.limit || 50,
      offset: params?.offset || 0,
      namespace: params?.namespace || undefined,
    },
  });
  return response.data;
}

export async function adminCreateTag(params: {
  namespace?: string;
  name: string;
  translations?: Record<string, {text?: string; intro?: string}>;
}): Promise<ApiEnvelope<{tag: AdminTag}>> {
  const response = await apiClient.post<ApiEnvelope<{tag: AdminTag}>>('/api/admin/tags', params);
  return response.data;
}

export async function adminUpdateTag(
  id: number,
  params: Partial<{
    namespace: string;
    name: string;
    translations: Record<string, {text?: string; intro?: string}>;
  }>,
): Promise<ApiEnvelope<{tag: AdminTag}>> {
  const response = await apiClient.put<ApiEnvelope<{tag: AdminTag}>>(`/api/admin/tags/${id}`, params);
  return response.data;
}

export async function adminDeleteTag(id: number): Promise<void> {
  await apiClient.delete(`/api/admin/tags/${id}`);
}

export async function listTagNamespaces(): Promise<ApiEnvelope<{namespaces: string[]}>> {
  const response = await apiClient.get<ApiEnvelope<{namespaces: string[]}>>('/api/tags/namespaces');
  return response.data;
}

// ─── Smart Filters ─────────────────────────────────────────────────────────

export type SmartFilterItem = {
  id: number;
  name: string;
  translations?: Record<string, {text?: string; intro?: string}>;
  icon?: string;
  query?: string;
  sort_by?: string;
  sort_order?: string;
  date_from?: string;
  date_to?: string;
  newonly?: boolean;
  untaggedonly?: boolean;
  enabled?: boolean;
  sort_order_num?: number;
};

export async function adminListSmartFilters(): Promise<ApiEnvelope<{items: SmartFilterItem[]}>> {
  const response = await apiClient.get<ApiEnvelope<{items: SmartFilterItem[]}>>('/api/admin/smart_filters');
  return response.data;
}

export async function adminCreateSmartFilter(
  params: Partial<SmartFilterItem>,
): Promise<ApiEnvelope<{item: SmartFilterItem}>> {
  const response = await apiClient.post<ApiEnvelope<{item: SmartFilterItem}>>('/api/admin/smart_filters', params);
  return response.data;
}

export async function adminUpdateSmartFilter(
  id: number,
  params: Partial<SmartFilterItem>,
): Promise<ApiEnvelope<{item: SmartFilterItem}>> {
  const response = await apiClient.put<ApiEnvelope<{item: SmartFilterItem}>>(`/api/admin/smart_filters/${id}`, params);
  return response.data;
}

export async function adminDeleteSmartFilter(id: number): Promise<void> {
  await apiClient.delete(`/api/admin/smart_filters/${id}`);
}

export async function adminToggleSmartFilter(id: number): Promise<ApiEnvelope<{item: SmartFilterItem}>> {
  const response = await apiClient.post<ApiEnvelope<{item: SmartFilterItem}>>(`/api/admin/smart_filters/${id}/toggle`);
  return response.data;
}

export async function adminReorderSmartFilters(
  orders: {id: number; sort_order_num: number}[],
): Promise<void> {
  await apiClient.post('/api/admin/smart_filters/reorder', {orders});
}

// ─── Admin Users ───────────────────────────────────────────────────────────

export async function adminListUsers(): Promise<ApiEnvelope<{users: AdminUser[]}>> {
  const response = await apiClient.get<ApiEnvelope<{users: AdminUser[]}>>('/api/auth/admin/users');
  return response.data;
}

export async function adminCreateUser(params: {
  username: string;
  isAdmin?: boolean;
}): Promise<ApiEnvelope<{user: AdminUser; generatedPassword?: string}>> {
  const response = await apiClient.post<ApiEnvelope<{user: AdminUser; generatedPassword?: string}>>('/api/auth/admin/users', params);
  return response.data;
}

export async function adminToggleUserRole(
  userId: number,
  isAdmin: boolean,
): Promise<void> {
  await apiClient.put(`/api/auth/admin/users/${userId}/role`, {isAdmin});
}

export async function adminDeleteUser(userId: number): Promise<void> {
  await apiClient.delete(`/api/auth/admin/users/${userId}`);
}

export async function adminResetUserPassword(
  userId: number,
  newPassword: string,
): Promise<void> {
  await apiClient.post(`/api/auth/admin/users/${userId}/reset-password`, {newPassword});
}

// ─── System Settings ───────────────────────────────────────────────────────

export async function adminListSystemSettings(): Promise<ApiEnvelope<{settings: SystemSetting[]}>> {
  const response = await apiClient.get('/api/admin/system/settings');
  const arr = response.data?.data;
  return {code: 0, data: {settings: Array.isArray(arr) ? arr : []}, message: ''};
}

export async function adminUpdateSystemSetting(
  key: string,
  value: string,
): Promise<void> {
  await apiClient.put('/api/admin/system/settings', {key, value});
}

export async function adminUpdateSystemSettings(
  settings: Record<string, string>,
): Promise<void> {
  await apiClient.put('/api/admin/system/settings/batch', {settings});
}

export async function adminReloadSystemCache(): Promise<void> {
  await apiClient.post('/api/admin/system/settings/reload');
}

// ─── Task Pool ─────────────────────────────────────────────────────────────

export async function adminListTasks(params?: {
  page?: number;
  pageSize?: number;
  status?: string;
}): Promise<{tasks: TaskPoolTask[]; total: number; page: number; pageSize: number; totalPages?: number}> {
  const qs = new URLSearchParams();
  if (params?.page) qs.set('page', String(params.page));
  if (params?.pageSize) qs.set('pageSize', String(params.pageSize));
  if (params?.status) qs.set('status', params.status);

  let authToken: string | null = null;
  try {
    const server = await getActiveServer();
    authToken = await getStoredToken(server?.id);
  } catch {}

  const url = await buildApiUrl(`/api/admin/taskpool/tasks?${qs.toString()}`);

  return new Promise((resolve, reject) => {
    const es = new EventSource<'snapshot' | 'tasks' | 'ping'>(url, {
      timeout: 15000,
      headers: authToken ? {Authorization: `Bearer ${authToken}`} : undefined,
    });
    const timeoutId = setTimeout(() => {
      es.close();
      reject(new Error('Task list request timed out'));
    }, 15000);

    function onPayload(raw: string) {
      try {
        const parsed = JSON.parse(raw);
        const pageData = parsed?.data || parsed;
        if (pageData?.tasks) {
          clearTimeout(timeoutId);
          es.close();
          resolve({
            tasks: pageData.tasks || [],
            total: pageData.total || 0,
            page: pageData.page || 1,
            pageSize: pageData.pageSize || 20,
            totalPages: pageData.totalPages || 1,
          });
        }
      } catch {}
    }

    es.addEventListener('snapshot', (event: any) => onPayload(event.data ?? ''));
    es.addEventListener('tasks', (event: any) => onPayload(event.data ?? ''));
    es.addEventListener('ping', () => {});

    es.addEventListener('error', () => {
      clearTimeout(timeoutId);
      es.close();
      reject(new Error('SSE connection failed'));
    });
  });
}

export async function adminCancelTask(taskId: number): Promise<void> {
  await apiClient.post(`/api/admin/taskpool/${taskId}/cancel`);
}

export async function adminRetryTask(taskId: number): Promise<void> {
  await apiClient.post(`/api/admin/taskpool/${taskId}/retry`);
}

// ─── Cron ──────────────────────────────────────────────────────────────────

export async function getCronStatus(): Promise<CronStatus> {
  const response = await apiClient.get('/api/admin/cron/status');
  const raw = response.data?.data ?? response.data;
  return {
    running: Boolean(raw?.running ?? false),
    totalTasks: Number(raw?.totalTasks ?? 0),
    enabledTasks: Number(raw?.enabledTasks ?? 0),
  };
}

export async function startCron(): Promise<void> {
  await apiClient.post('/api/admin/cron/start');
}

export async function stopCron(): Promise<void> {
  await apiClient.post('/api/admin/cron/stop');
}

export async function listCronTasks(params?: {
  page?: number;
  pageSize?: number;
}): Promise<{tasks: ScheduledTask[]; total: number; page: number; pageSize: number; totalPages: number}> {
  const response = await apiClient.get('/api/admin/cron/tasks', {params});
  const raw = response.data?.data ?? response.data;
  return {
    tasks: Array.isArray(raw?.tasks) ? raw.tasks : [],
    total: Number(raw?.total ?? 0),
    page: Number(raw?.page ?? params?.page ?? 1),
    pageSize: Number(raw?.pageSize ?? params?.pageSize ?? 10),
    totalPages: Number(raw?.totalPages ?? 1),
  };
}

export async function createCronTask(params: {
  name: string;
  cronExpression: string;
  taskType: string;
  taskParameters?: string;
  enabled?: boolean;
  priority?: number;
  timeoutSeconds?: number;
}): Promise<ApiEnvelope<unknown>> {
  const response = await apiClient.post('/api/admin/cron/tasks', params);
  return response.data;
}

export async function updateCronTask(
  id: number,
  params: Partial<{
    name: string;
    cronExpression: string;
    taskType: string;
    taskParameters: string;
    enabled: boolean;
    priority: number;
    timeoutSeconds: number;
  }>,
): Promise<ApiEnvelope<unknown>> {
  const response = await apiClient.put(`/api/admin/cron/tasks/${id}`, params);
  return response.data;
}

export async function deleteCronTask(id: number): Promise<void> {
  await apiClient.delete(`/api/admin/cron/tasks/${id}`);
}

export async function triggerCronTask(id: number): Promise<void> {
  await apiClient.post(`/api/admin/cron/tasks/${id}/trigger`);
}

export async function enableCronTask(id: number): Promise<void> {
  await apiClient.post(`/api/admin/cron/tasks/${id}/enable`);
}

export async function disableCronTask(id: number): Promise<void> {
  await apiClient.post(`/api/admin/cron/tasks/${id}/disable`);
}

// ─── Plugins ───────────────────────────────────────────────────────────────

export async function adminListPlugins(): Promise<ApiEnvelope<{plugins: Plugin[]}>> {
  const response = await apiClient.get('/api/admin/plugins');
  const arr = response.data?.data || response.data;
  return {code: 0, data: {plugins: Array.isArray(arr) ? arr : []}, message: ''};
}

export async function adminTogglePlugin(namespace: string, enabled: boolean): Promise<void> {
  await apiClient.put(`/api/admin/plugins/${namespace}/enabled`, {enabled});
}

export async function adminDeletePlugin(namespace: string): Promise<void> {
  await apiClient.delete(`/api/admin/plugins/${namespace}`);
}

export async function adminInstallPlugin(url: string): Promise<ApiEnvelope<unknown>> {
  const response = await apiClient.post('/api/admin/plugins/install', {url});
  return response.data;
}

export async function adminUpdatePlugin(namespace: string, force?: boolean): Promise<ApiEnvelope<unknown>> {
  const response = await apiClient.post(`/api/admin/plugins/${namespace}/update`, force ? {force: 'true'} : {});
  return response.data;
}

export async function adminCheckPluginUpdate(namespace: string, force?: boolean): Promise<ApiEnvelope<unknown>> {
  const response = await apiClient.post(`/api/admin/plugins/${namespace}/check_update`, force ? {force: 'true'} : {});
  return response.data;
}

// ─── Plugin Config ──────────────────────────────────────────────────────────

export type PluginParameter = {
  type: 'string' | 'int' | 'bool' | 'array';
  name?: string;
  desc: string;
  default_value?: unknown;
  value?: unknown;
};

export async function adminGetPluginConfig(
  namespace: string,
): Promise<ApiEnvelope<{has_schema: boolean; parameters?: string | PluginParameter[]; message?: string}>> {
  const response = await apiClient.get(`/api/admin/plugins/${namespace}/config`);
  return response.data;
}

export async function adminUpdatePluginConfig(
  namespace: string,
  parameters: PluginParameter[],
): Promise<ApiEnvelope<unknown>> {
  const response = await apiClient.put(`/api/admin/plugins/${namespace}/config`, {
    parameters: JSON.stringify(parameters),
  });
  return response.data;
}

// ─── Stats ─────────────────────────────────────────────────────────────────

export async function getTagCloud(lang?: string, limit = 50): Promise<ApiEnvelope<{items: TagCloudItem[]; total: number}>> {
  const response = await apiClient.get('/api/tags/cloud', {
    params: {lang: lang || undefined, limit},
  });
  return response.data;
}
