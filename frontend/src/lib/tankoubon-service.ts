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
  static async getAllTankoubons(): Promise<Tankoubon[]> {
    const response = await apiClient.get<TankoubonResponse>(this.baseUrl);
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
    const params = new URLSearchParams();
    if (data.name) params.append('name', data.name);
    if (data.summary) params.append('summary', data.summary);
    if (data.tags) params.append('tags', data.tags);

    await apiClient.put(`${this.baseUrl}/${id}?${params.toString()}`, undefined);
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
  static async addArchiveToTankoubon(tankoubonId: string, archiveId: string): Promise<void> {
    await apiClient.put(`${this.baseUrl}/${tankoubonId}/${archiveId}`, undefined);
  }

  /**
   * Remove archive from tankoubon
   */
  static async removeArchiveFromTankoubon(tankoubonId: string, archiveId: string): Promise<void> {
    await apiClient.delete(`${this.baseUrl}/${tankoubonId}/${archiveId}`);
  }

  /**
   * Get thumbnail URL for tankoubon (uses first archive's thumbnail)
   */
  static getThumbnailUrl(tankoubonId: string, thumbhash?: string): string {
    if (thumbhash) {
      return `/api/archives/${thumbhash}/thumbnail`;
    }
    return '/placeholder-thumbnail.png';
  }
}
