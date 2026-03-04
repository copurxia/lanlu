'use client';

import { apiClient } from '../api';

export interface Plugin {
  id: number;
  name: string;
  namespace: string;
  login_from: string;
  version: string;
  plugin_type: string;  // API返回的是 plugin_type，不是 type
  author: string;
  description: string;
  tags: string;
  permissions: string[];  // 现在是权限字符串数组
  icon: string;         // 插件图标，Base64编码的图片数据
  enabled: boolean;
  installed: boolean;
  update_url: string;
  has_schema: boolean;
  parameters: any[];
  created_at: string;
  updated_at: string;
}

export interface PluginCheckUpdateResult {
  success: boolean;
  message?: string;
  namespace?: string;
  update_url?: string;
  has_update?: boolean;
  old_version?: string;
  new_version?: string;
  clear_parameters?: boolean;
  reason?: string;
  old_etag?: string;
  new_etag?: string;
}

export class PluginService {
  static async getAllPlugins(): Promise<Plugin[]> {
    try {

      const response = await apiClient.get('/api/admin/plugins');


      // API 返回直接的数组
      const plugins = Array.isArray(response.data) ? response.data : [];



      return plugins;
    } catch (error) {
      console.error('Failed to fetch plugins:', error);
      if (error && typeof error === 'object' && 'response' in error) {
        const axiosError = error as any;
        console.error('API响应错误:', axiosError.response?.status, axiosError.response?.data);
      } else if (error instanceof Error) {
        console.error('网络错误:', error.message);
      }
      throw error;
    }
  }

  static async togglePluginStatus(namespace: string, enabled: boolean): Promise<void> {
    try {
      await apiClient.put(`/api/admin/plugins/${namespace}/enabled`, { enabled });
    } catch (error) {
      console.error('Failed to toggle plugin status:', error);
      throw error;
    }
  }

  static async updatePluginConfig(namespace: string, config: object): Promise<void> {
    try {
      await apiClient.put(`/api/admin/plugins/${namespace}/config`, config);
    } catch (error) {
      console.error('Failed to update plugin config:', error);
      throw error;
    }
  }

  /**
   * 获取 Metadata 类型的插件列表
   */
  static async getMetadataPlugins(): Promise<Plugin[]> {
    try {
      const plugins = await this.getAllPlugins();
      return plugins.filter(p => p.plugin_type.toLowerCase() === 'metadata');
    } catch (error) {
      console.error('Failed to fetch metadata plugins:', error);
      throw error;
    }
  }

  /**
   * 删除插件
   */
  static async deletePlugin(namespace: string): Promise<void> {
    try {
      await apiClient.delete(`/api/admin/plugins/${namespace}`);
    } catch (error) {
      console.error('Failed to delete plugin:', error);
      throw error;
    }
  }

  /**
   * 安装插件（类型从插件元数据自动获取）
   */
  static async installPlugin(url: string): Promise<{
    success: boolean;
    message?: string;
    filename?: string;
    plugin_type?: string;
  }> {
    try {
      const response = await apiClient.post('/api/admin/plugins/install', { url });
      return response.data;
    } catch (error) {
      console.error('Failed to install plugin:', error);
      throw error;
    }
  }

  /**
   * 更新插件（使用插件声明的 update_url）
   */
  static async updatePlugin(
    namespace: string,
    opts?: { force?: boolean }
  ): Promise<{
    success: boolean;
    message?: string;
  }> {
    try {
      const force = !!opts?.force;
      const response = await apiClient.post(
        `/api/admin/plugins/${namespace}/update`,
        force ? { force: 'true' } : undefined
      );
      return response.data;
    } catch (error) {
      console.error('Failed to update plugin:', error);
      throw error;
    }
  }

  /**
   * 检查插件更新（使用插件声明的 update_url；优先走 ETag 条件请求，force 可跳过）
   */
  static async checkUpdate(
    namespace: string,
    opts?: { force?: boolean }
  ): Promise<PluginCheckUpdateResult> {
    try {
      const force = !!opts?.force;
      const response = await apiClient.post(
        `/api/admin/plugins/${namespace}/check_update`,
        force ? { force: 'true' } : undefined
      );
      return response.data;
    } catch (error) {
      console.error('Failed to check plugin update:', error);
      throw error;
    }
  }
}
