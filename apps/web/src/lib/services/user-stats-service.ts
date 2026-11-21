// 用户统计服务 - 统计数据来自 /api/user/stats，趋势来自 /api/user/trend，最近活动由 /api/search 计算
import { apiClient } from '../api';
import { ArchiveService } from './archive-service';
import { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

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

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object';
}

function isSuccessfulPayload(payload: unknown): payload is { code?: number; data?: unknown } {
  if (!isRecord(payload)) return false;
  if (payload.code === 200) return true;
  return false;
}

function toNumber(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return 0;
}

function normalizeUserStats(payload: unknown): UserStats {
  if (!isRecord(payload)) {
    return {
      favoriteCount: 0,
      readCount: 0,
      totalPagesRead: 0,
      totalArchives: 0,
    };
  }

  return {
    favoriteCount: toNumber(payload.favoriteCount),
    readCount: toNumber(payload.readCount),
    totalPagesRead: toNumber(payload.totalPagesRead),
    totalArchives: toNumber(payload.totalArchives),
  };
}

function normalizeReadingTrend(payload: unknown): ReadingTrendItem[] {
  if (!Array.isArray(payload)) {
    return [];
  }

  return payload
    .filter(isRecord)
    .map((item) => ({
      date: typeof item.date === 'string' ? item.date : '',
      count: toNumber(item.count),
    }));
}

function isArchiveItem(item: Archive | Tankoubon): item is Archive {
  return 'arcid' in item;
}

export class UserStatsService {
  // 获取用户统计数据
  static async getStats(): Promise<UserStats> {
    try {
      const response = await apiClient.get('/api/user/stats');
      if (isSuccessfulPayload(response.data) && response.data?.data) {
        return normalizeUserStats(response.data.data);
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
      if (isSuccessfulPayload(response.data)) {
        return normalizeReadingTrend(response.data.data);
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

      const [recentReadResp, favoritesResp] = await Promise.allSettled([
        ArchiveService.search({
          sortby: 'lastread',
          order: 'desc',
          page: 1,
          pageSize: safeLimit,
        }),
        ArchiveService.search({
          favoriteonly: true,
          page: 1,
          pageSize: Math.max(safeLimit * 4, 50),
        }),
      ]);

      const recentRead = recentReadResp.status === 'fulfilled'
        ? recentReadResp.value.data.filter(isArchiveItem).slice(0, safeLimit)
        : [];

      const recentFavoritesRaw = favoritesResp.status === 'fulfilled'
        ? favoritesResp.value.data.filter(isArchiveItem)
        : [];
      const recentFavorites = recentFavoritesRaw
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
