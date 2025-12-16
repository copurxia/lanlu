// 阅读记录服务 - 用户级别的阅读历史管理
import { apiClient } from './api';
import { Archive } from '@/types/archive';

export interface ReadingHistoryResponse {
  operation: string;
  data: Archive[];
  recordsTotal: number;
  recordsFiltered: number;
  success: number;
}

export class ReadingHistoryService {
  // 获取已读的档案详情列表（带分页）
  static async getReadArchives(start: number = 0, count: number = 100): Promise<ReadingHistoryResponse> {
    try {
      const response = await apiClient.get('/api/read_archives', {
        params: { start, count }
      });
      return {
        operation: response.data.operation || 'get_read_archives',
        data: response.data.data || [],
        recordsTotal: response.data.recordsTotal || 0,
        recordsFiltered: response.data.recordsFiltered || 0,
        success: response.data.success || 0
      };
    } catch (error) {
      console.error('获取阅读记录失败:', error);
      return {
        operation: 'get_read_archives',
        data: [],
        recordsTotal: 0,
        recordsFiltered: 0,
        success: 0
      };
    }
  }
}
