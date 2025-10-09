import { apiClient } from './api';
import { Archive, SearchResponse, SearchParams, RandomParams, ArchiveMetadata } from '@/types/archive';

export class ArchiveService {
  static async search(params: SearchParams): Promise<SearchResponse> {
    const response = await apiClient.get('/api/search', { params });
    return response.data;
  }

  static async getRandom(params: RandomParams = {}): Promise<Archive[]> {
    const response = await apiClient.get('/api/search/random', { 
      params: {
        count: params.count || 5,
        filter: params.filter,
        category: params.category,
        newonly: params.newonly,
        untaggedonly: params.untaggedonly
      }
    });
    return response.data.data || [];
  }

  static async getMetadata(id: string): Promise<ArchiveMetadata> {
    const response = await apiClient.get(`/api/archives/${id}/metadata`);
    return response.data;
  }

  static async getFiles(id: string): Promise<string[]> {
    const response = await apiClient.get(`/api/archives/${id}/files`);
    return response.data.pages || [];
  }

  static async getArchive(id: string): Promise<any> {
    const response = await apiClient.get(`/api/archives/${id}`);
    return response.data;
  }

  static getThumbnailUrl(id: string, page: number = 1): string {
    // 使用相对路径，因为前端和后端部署在一起
    return `/api/archives/${id}/thumbnail?page=${page}`;
  }

  static getPageUrl(id: string, path: string): string {
    // 使用相对路径，因为前端和后端部署在一起
    // 如果path被编码了，需要先解码再重新编码
    try {
      // 尝试解码path，如果已经是编码状态
      const decodedPath = decodeURIComponent(path);
      return `/api/archives/${id}/page?path=${decodedPath}`;
    } catch (e) {
      // 如果解码失败，说明path已经是正确格式
      return `/api/archives/${id}/page?path=${path}`;
    }
  }

  static getDownloadUrl(id: string): string {
    return `/api/archives/${id}/download`;
  }
}