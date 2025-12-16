// 收藏功能服务 - 用户级别的档案收藏管理
import { apiClient } from './api';
import { Archive } from '@/types/archive';

export interface FavoriteArchivesResponse {
  operation: string;
  data: Archive[];
  recordsTotal: number;
  recordsFiltered: number;
  success: number;
}

export class FavoriteService {
  // 添加收藏
  static async addFavorite(arcid: string): Promise<boolean> {
    try {
      const response = await apiClient.put(`/api/archives/${arcid}/favorite`);
      return response.data.success === 1;
    } catch (error) {
      console.error('添加收藏失败:', error);
      return false;
    }
  }

  // 取消收藏
  static async removeFavorite(arcid: string): Promise<boolean> {
    try {
      const response = await apiClient.delete(`/api/archives/${arcid}/favorite`);
      return response.data.success === 1;
    } catch (error) {
      console.error('取消收藏失败:', error);
      return false;
    }
  }

  // 切换收藏状态（需要传入当前状态）
  static async toggleFavorite(arcid: string, currentIsFavorite: boolean): Promise<boolean> {
    try {
      // 根据当前状态切换
      if (currentIsFavorite) {
        return await this.removeFavorite(arcid);
      } else {
        return await this.addFavorite(arcid);
      }
    } catch (error) {
      console.error('切换收藏状态失败:', error);
      return false;
    }
  }

  // 获取收藏列表（arcid 列表）
  static async getFavorites(): Promise<string[]> {
    try {
      const response = await apiClient.get('/api/favorites');
      return response.data.favorites || [];
    } catch (error) {
      console.error('获取收藏列表失败:', error);
      return [];
    }
  }

  // 获取收藏的档案详情列表（带分页）
  static async getFavoriteArchives(start: number = 0, count: number = 100): Promise<FavoriteArchivesResponse> {
    try {
      const response = await apiClient.get('/api/favorites/archives', {
        params: { start, count }
      });
      return {
        operation: response.data.operation || 'get_favorite_archives',
        data: response.data.data || [],
        recordsTotal: response.data.recordsTotal || 0,
        recordsFiltered: response.data.recordsFiltered || 0,
        success: response.data.success || 0
      };
    } catch (error) {
      console.error('获取收藏档案详情失败:', error);
      return {
        operation: 'get_favorite_archives',
        data: [],
        recordsTotal: 0,
        recordsFiltered: 0,
        success: 0
      };
    }
  }
}