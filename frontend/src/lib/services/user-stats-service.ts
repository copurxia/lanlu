// 用户统计服务 - 获取用户阅读统计、趋势等数据
import { apiClient } from '../api';
import { Archive } from '@/types/archive';

export interface UserStats {
  favoriteCount: number;
  readCount: number;
  totalPagesRead: number;
  totalArchives: number;
}

export interface ReadingTrendItem {
  date: string;
  count: number;
}

export interface RecentActivity {
  recentRead: Archive[];
  recentFavorites: Archive[];
}

export class UserStatsService {
  // 获取用户统计数据
  static async getStats(): Promise<UserStats> {
    try {
      const response = await apiClient.get('/api/user/stats');
      if (response.data.success === 1 && response.data.data) {
        return response.data.data;
      }
      return {
        favoriteCount: 0,
        readCount: 0,
        totalPagesRead: 0,
        totalArchives: 0
      };
    } catch (error) {
      console.error('获取用户统计失败:', error);
      return {
        favoriteCount: 0,
        readCount: 0,
        totalPagesRead: 0,
        totalArchives: 0
      };
    }
  }

  // 获取阅读趋势
  static async getReadingTrend(days: number = 7): Promise<ReadingTrendItem[]> {
    try {
      const response = await apiClient.get('/api/user/reading-trend', {
        params: { days }
      });
      if (response.data.success === 1 && response.data.data) {
        return response.data.data;
      }
      return [];
    } catch (error) {
      console.error('获取阅读趋势失败:', error);
      return [];
    }
  }

  // 获取最近活动
  static async getRecentActivity(limit: number = 5): Promise<RecentActivity> {
    try {
      const response = await apiClient.get('/api/user/recent-activity', {
        params: { limit }
      });
      if (response.data.success === 1 && response.data.data) {
        return response.data.data;
      }
      return {
        recentRead: [],
        recentFavorites: []
      };
    } catch (error) {
      console.error('获取最近活动失败:', error);
      return {
        recentRead: [],
        recentFavorites: []
      };
    }
  }
}
