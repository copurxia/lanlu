import { apiClient } from '@/lib/api';
import type { Tankoubon, TankoubonCreateRequest, TankoubonMetadata, TankoubonResponse, TankoubonUpdateRequest } from '@/types/tankoubon';
import type { MetadataObject } from '@/types/archive';
import type { Task } from '@/types/task';
import { TaskPoolService } from './taskpool-service';
import { normalizeArchiveAssets } from '@/lib/utils/archive-assets';
import { normalizeTankoubonMetadata } from '@/lib/utils/metadata';

type TankoubonUpdateResponse = {
  success?: number | boolean | string;
  archives_task_id?: number | string;
  archives_task_error?: string;
};

export class TankoubonService {
  private static baseUrl = '/api/tankoubons';

  private static normalizeResult(data: TankoubonResponse): Tankoubon[] {
    if (!data) return [];
    const result = (data as any).result;
    if (!result) return [];
    const list = Array.isArray(result) ? result : [result];
    return list.map((item) => ({
      ...item,
      assets: normalizeArchiveAssets((item as any)?.assets),
    }));
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


  static async getMetadata(id: string, options?: { includePages?: boolean }): Promise<TankoubonMetadata> {
    const params: Record<string, string> = {};
    if (options?.includePages) {
      params.include_pages = '1';
    }
    const response = await apiClient.get<TankoubonMetadata>(`${this.baseUrl}/${id}/metadata`, { params });
    return normalizeTankoubonMetadata(response.data);
  }

  static async updateMetadata(id: string, metadata: MetadataObject): Promise<void> {
    await apiClient.put(`${this.baseUrl}/${id}/metadata`, metadata);
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
    const response = await apiClient.put<TankoubonUpdateResponse>(`${this.baseUrl}/${id}`, data);
    const payload = response.data;

    const rawTaskId = payload?.archives_task_id;
    const taskId =
      typeof rawTaskId === 'number'
        ? rawTaskId
        : typeof rawTaskId === 'string' && rawTaskId.trim() !== ''
        ? Number(rawTaskId)
        : 0;

    if (!taskId || !Number.isFinite(taskId) || taskId <= 0) {
      return;
    }

    const finalTask = await this.waitForTaskCompletion(taskId);
    if (finalTask.status === 'failed' || finalTask.status === 'stopped') {
      const err =
        payload?.archives_task_error ||
        finalTask.result ||
        finalTask.message ||
        'Archive metadata task failed';
      throw new Error(err);
    }
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
    page?: number;
    pageSize?: number;
  }): Promise<{ data: Tankoubon[] }> {
    const response = await apiClient.get('/api/search', {
      params: {
        favorite_tankoubons_only: true,
        groupby_tanks: true,
        page: params?.page ?? 1,
        pageSize: params?.pageSize ?? 1000
      }
    });

    return {
      data: response.data.data as unknown as Tankoubon[]
    };
  }

  private static async waitForTaskCompletion(
    jobId: number,
    options?: { timeoutMs?: number }
  ): Promise<Task> {
    return await TaskPoolService.waitForTaskTerminal(jobId, {
      timeoutMs: options?.timeoutMs ?? 10 * 60 * 1000,
    });
  }

}
