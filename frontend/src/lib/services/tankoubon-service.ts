import { apiClient } from '@/lib/api';
import { ArchiveService } from '@/lib/services/archive-service';
import type { Tankoubon, TankoubonCreateRequest, TankoubonMetadata, TankoubonResponse } from '@/types/tankoubon';
import type { MetadataUpdatePayload } from '@/types/archive';
import { normalizeArchiveAssets } from '@/lib/utils/archive-assets';
import { normalizeTankoubonMetadata } from '@/lib/utils/metadata';


export class TankoubonService {
  private static baseUrl = '/api/tankoubons';

  private static isTankoubonItem(item: unknown): item is Tankoubon {
    return item !== null && typeof item === 'object' && 'tankoubon_id' in item;
  }

  private static normalizeResult(data: TankoubonResponse): Tankoubon[] {
    if (!data) return [];
    const result = data.result;
    if (!result) return [];
    const list = Array.isArray(result) ? result : [result];
    return list.map((item) => {
      const normalizedItem = item as Tankoubon & { assets?: unknown; children?: unknown };
      return {
        ...normalizedItem,
        title: String(normalizedItem.title || '').trim(),
        description: String(normalizedItem.description || '').trim(),
        children: Array.isArray(normalizedItem.children)
          ? normalizedItem.children.map((value) => String(value || '').trim()).filter(Boolean)
          : [],
        assets: normalizeArchiveAssets(normalizedItem.assets),
      };
    });
  }

  /**
   * Get all tankoubons
   */
  static async getAllTankoubons(options?: { signal?: AbortSignal }): Promise<Tankoubon[]> {
    const response = await apiClient.get<TankoubonResponse>(this.baseUrl, { signal: options?.signal });
    return this.normalizeResult(response.data);
  }


  static async getMetadata(id: string, options?: { includePages?: boolean; lang?: string }): Promise<TankoubonMetadata> {
    const params: Record<string, string> = {};
    if (options?.lang) {
      params.lang = options.lang;
    }
    if (options?.includePages) {
      params.include_pages = '1';
    }
    const response = await apiClient.get<TankoubonMetadata>(`${this.baseUrl}/${id}/metadata`, { params });
    return normalizeTankoubonMetadata(response.data);
  }

  static async updateMetadata(id: string, metadata: MetadataUpdatePayload): Promise<void> {
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
  static async getTankoubonsWithArchives(ids: string[]): Promise<TankoubonMetadata[]> {
    const promises = ids.map((id) => this.getMetadata(id));
    const results = await Promise.allSettled(promises);
    return results
      .filter((result): result is PromiseFulfilledResult<TankoubonMetadata> =>
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
    const response = await ArchiveService.search({
      favorite_tankoubons_only: true,
      groupby_tanks: true,
      page: params?.page ?? 1,
      pageSize: params?.pageSize ?? 1000
    });

    return {
      data: response.data.filter(this.isTankoubonItem)
    };
  }


}
