import { apiClient } from '@/lib/api';
import { isSuccessResponse, parseApiPayload } from '@/lib/utils/api-utils';

export interface SystemSetting {
  id: number;
  key: string;
  value: string;
  valueType: string;
  category: string;
  description: Record<string, string>;
  isEncrypted: boolean;
}

export interface SystemSettingsApi {
  getAllSettings(): Promise<SystemSetting[]>;
  updateSetting(key: string, value: string): Promise<boolean>;
  updateSettings(settings: Record<string, string>): Promise<boolean>;
  getCategories(): Promise<string[]>;
  reloadCache(): Promise<boolean>;
}

type SystemSettingsResponse = {
  data?: unknown;
  message?: string;
  success?: unknown;
};

export const SystemSettingsApi: SystemSettingsApi = {
  async getAllSettings() {
    const response = await apiClient.get('/api/admin/system/settings');
    const data = parseApiPayload<SystemSettingsResponse>(response.data, {});
    if (isSuccessResponse(data.success)) {
      return Array.isArray(data.data) ? (data.data as SystemSetting[]) : [];
    }
    throw new Error(data.message || '获取设置失败');
  },

  async updateSetting(key: string, value: string) {
    const response = await apiClient.put('/api/admin/system/settings', { key, value });
    const data = parseApiPayload<SystemSettingsResponse>(response.data, {});
    return isSuccessResponse(data.success);
  },

  async updateSettings(settings: Record<string, string>) {
    const response = await apiClient.put('/api/admin/system/settings/batch', { settings });
    const data = parseApiPayload<SystemSettingsResponse>(response.data, {});
    return isSuccessResponse(data.success);
  },

  async getCategories() {
    const response = await apiClient.get('/api/admin/system/settings/categories');
    const data = parseApiPayload<SystemSettingsResponse>(response.data, {});
    if (isSuccessResponse(data.success)) {
      return Array.isArray(data.data) ? (data.data as string[]) : [];
    }
    throw new Error(data.message || '获取分类失败');
  },

  async reloadCache() {
    const response = await apiClient.post('/api/admin/system/settings/reload');
    const data = parseApiPayload<SystemSettingsResponse>(response.data, {});
    return isSuccessResponse(data.success);
  },
};
