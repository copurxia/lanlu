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
  getSettingsByCategory(category: string): Promise<SystemSetting[]>;
  updateSetting(key: string, value: string): Promise<boolean>;
  updateSettings(settings: Record<string, string>): Promise<boolean>;
  getCategories(): Promise<string[]>;
  reloadCache(): Promise<boolean>;
}

export const SystemSettingsApi: SystemSettingsApi = {
  async getAllSettings() {
    const response = await fetch('/api/system/settings');
    const data = await response.json();
    if (data.success) {
      return data.data;
    }
    throw new Error(data.message || '获取设置失败');
  },

  async getSettingsByCategory(category: string) {
    const response = await fetch(`/api/system/settings/category/${category}`);
    const data = await response.json();
    if (data.success) {
      return data.data;
    }
    throw new Error(data.message || '获取设置失败');
  },

  async updateSetting(key: string, value: string) {
    const response = await fetch('/api/system/settings', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ key, value }),
    });
    const data = await response.json();
    return data.success;
  },

  async updateSettings(settings: Record<string, string>) {
    const response = await fetch('/api/system/settings/batch', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ settings }),
    });
    const data = await response.json();
    return data.success;
  },

  async getCategories() {
    const response = await fetch('/api/system/settings/categories');
    const data = await response.json();
    if (data.success) {
      return data.data;
    }
    throw new Error(data.message || '获取分类失败');
  },

  async reloadCache() {
    const response = await fetch('/api/system/settings/reload', {
      method: 'POST',
    });
    const data = await response.json();
    return data.success;
  },
};
