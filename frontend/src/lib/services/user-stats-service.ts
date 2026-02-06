// 用户统计服务 - 统计数据来自 /api/user/stats，趋势来自 /api/user/trend，最近活动由 /api/search 计算
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

function normalizeSearchArchives(payload: any): Archive[] {
  const list = payload?.data;
  return Array.isArray(list) ? (list as Archive[]) : [];
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
        totalArchives: 0,
      };
    } catch (error) {
      console.error('获取用户统计失败:', error);
      return {
        favoriteCount: 0,
        readCount: 0,
        totalPagesRead: 0,
        totalArchives: 0,
      };
    }
  }

  // 由 /api/user/trend 返回阅读趋势（服务端聚合）
  static async getReadingTrend(days: number = 7): Promise<ReadingTrendItem[]> {
    try {
      const safeDays = Math.max(1, Math.min(365, Math.trunc(days || 7)));
      const response = await apiClient.get('/api/user/trend', {
        params: { days: safeDays }
      });
      if (response.data.success === 1 && Array.isArray(response.data.data)) {
        return response.data.data as ReadingTrendItem[];
      }
      return [];
    } catch (error) {
      console.error('获取阅读趋势失败:', error);
      return [];
    }
  }

  // 由 /api/search 计算最近阅读和最近收藏
  static async getRecentActivity(limit: number = 5): Promise<RecentActivity> {
    try {
      const safeLimit = Math.max(1, Math.min(50, Math.trunc(limit || 5)));

      const [recentReadResp, favoritesResp] = await Promise.all([
        apiClient.get('/api/search', {
          params: {
            sortby: 'lastread',
            order: 'desc',
            page: 1,
            pageSize: safeLimit,
          },
        }),
        apiClient.get('/api/search', {
          params: {
            favoriteonly: true,
            page: 1,
            pageSize: Math.max(safeLimit * 4, 50),
          },
        }),
      ]);

      const recentRead = normalizeSearchArchives(recentReadResp.data).slice(0, safeLimit);

      const recentFavorites = normalizeSearchArchives(favoritesResp.data)
        .slice()
        .sort((a, b) => Number(b.favoritetime || 0) - Number(a.favoritetime || 0))
        .slice(0, safeLimit);

      return { recentRead, recentFavorites };
    } catch (error) {
      console.error('获取最近活动失败:', error);
      return { recentRead: [], recentFavorites: [] };
    }
  }
}
