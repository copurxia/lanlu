import { apiClient } from '@/lib/api';
import type { Tankoubon, TankoubonCreateRequest, TankoubonUpdateRequest, TankoubonResponse } from '@/types/tankoubon';

export class TankoubonService {
  private static baseUrl = '/api/tankoubons';

  private static normalizeResult(data: TankoubonResponse): Tankoubon[] {
    if (!data) return [];
    const result = (data as any).result;
    if (!result) return [];
    return Array.isArray(result) ? result : [result];
  }

  /**
   * Get all tankoubons
   */
  static async getAllTankoubons(options?: { signal?: AbortSignal }): Promise<Tankoubon[]> {
    const response = await apiClient.get<TankoubonResponse>(this.baseUrl, { signal: options?.signal });
    return this.normalizeResult(response.data);
  }

  /**
   * Get tankoubon by ID
   */
  static async getTankoubonById(id: string): Promise<Tankoubon & { total?: number }> {
    const response = await apiClient.get<TankoubonResponse & { total?: number }>(`${this.baseUrl}/${id}`);
    const items = this.normalizeResult(response.data);
    if (items.length === 0) throw new Error('Failed to fetch tankoubon');
    const tankoubon = items[0];
    // Attach the total (archive count) from the API response
    return {
      ...tankoubon,
      archive_count: response.data.total
    };
  }

  /**
   * Create a new tankoubon
   */
  static async createTankoubon(data: TankoubonCreateRequest): Promise<{ success: boolean; tankoubon_id?: string }> {
    const response = await apiClient.put<{ success: boolean; tankoubon_id?: string }>(
      `${this.baseUrl}?name=${encodeURIComponent(data.name)}`,
      undefined
    );
    return response.data;
  }

  /**
   * Update tankoubon metadata
   */
  static async updateTankoubon(id: string, data: TankoubonUpdateRequest): Promise<void> {
    await apiClient.put(`${this.baseUrl}/${id}`, data);
  }

  /**
   * Delete tankoubon
   */
  static async deleteTankoubon(id: string): Promise<void> {
    await apiClient.delete(`${this.baseUrl}/${id}`);
  }

  /**
   * Add archive to tankoubon
   */
  static async addArchiveToTankoubon(tankoubonId: string, archiveId: string): Promise<{ success: boolean; message?: string; error?: string }> {
    const response = await apiClient.put<{ success: number; operation: string; successMessage?: string; error?: string }>(
      `${this.baseUrl}/${tankoubonId}/${archiveId}`,
      undefined
    );
    return {
      success: response.data.success === 1,
      message: response.data.successMessage,
      error: response.data.error
    };
  }

  /**
   * Remove archive from tankoubon
   */
  static async removeArchiveFromTankoubon(tankoubonId: string, archiveId: string): Promise<void> {
    await apiClient.delete(`${this.baseUrl}/${tankoubonId}/${archiveId}`);
  }

  /**
   * 批量获取多个 tankoubon 的详细信息（包含 archives）
   */
  static async getTankoubonsWithArchives(ids: string[]): Promise<Tankoubon[]> {
    const promises = ids.map(id => this.getTankoubonById(id));
    const results = await Promise.allSettled(promises);
    return results
      .filter((result): result is PromiseFulfilledResult<Tankoubon> =>
        result.status === 'fulfilled'
      )
      .map(result => result.value);
  }

  /**
   * 获取某个归档所属的合集列表（包含 archives）
   */
  static async getTankoubonsForArchive(archiveId: string): Promise<Tankoubon[]> {
    const response = await apiClient.get<TankoubonResponse>(`/api/archives/${archiveId}/tankoubons`);
    return this.normalizeResult(response.data);
  }

  /**
   * 直接通过搜索接口获取收藏的合集列表（包含 archives）
   */
  static async getFavoriteTankoubons(params?: {
    start?: number;
    count?: number;
  }): Promise<{ data: Tankoubon[] }> {
    const response = await apiClient.get('/api/search', {
      params: {
        favorite_tankoubons_only: true,
        groupby_tanks: true,
        start: params?.start ?? 0,
        count: params?.count ?? 1000
      }
    });

    return {
      data: response.data.data as unknown as Tankoubon[]
    };
  }


}
