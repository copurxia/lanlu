import { apiClient } from '@/lib/api';
import { isSuccessResponse, extractApiError, normalizeArrayResponse } from '@/lib/utils/api-utils';

export interface Category {
  id: number;
  catid: string;
  name: string;
  scan_path: string;
  description: string;
  icon: string;
  sort_order: number;
  enabled: boolean;
  plugins: string[];
  // Generated category cover image asset id (assets.id), computed by backend.
  cover_asset_id?: number;
  archive_count: number;
  created_at: string;
  updated_at: string;
}

export interface CategoryCreateRequest {
  name: string;
  scan_path: string;
  description?: string;
  icon?: string;
  sort_order?: number;
  enabled?: boolean;
  plugins?: string[];
}

export interface CategoryUpdateRequest {
  name?: string;
  scan_path?: string;
  description?: string;
  icon?: string;
  sort_order?: number;
  enabled?: boolean;
  plugins?: string[];
}

interface CategoryResponse {
  operation: string;
  data: Category | Category[];
  success: number;
}

export class CategoryService {
  private static baseUrl = '/api/categories';

  /**
   * Get all categories
   */
  static async getAllCategories(): Promise<Category[]> {
    const response = await apiClient.get<CategoryResponse>(this.baseUrl);
    if (isSuccessResponse(response.data.success)) {
      return normalizeArrayResponse(response.data.data);
    }
    return [];
  }

  /**
   * Get category by ID
   */
  static async getCategoryById(catid: string): Promise<Category | null> {
    const response = await apiClient.get<CategoryResponse>(`${this.baseUrl}/${catid}`);
    if (isSuccessResponse(response.data.success)) {
      return normalizeArrayResponse(response.data.data)[0] ?? null;
    }
    return null;
  }

  /**
   * Create a new category
   */
  static async createCategory(data: CategoryCreateRequest): Promise<{ success: boolean; category?: Category; error?: string }> {
    try {
      const response = await apiClient.post<CategoryResponse>(this.baseUrl, data);
      if (isSuccessResponse(response.data.success)) {
        return { success: true, category: normalizeArrayResponse(response.data.data)[0] };
      }
      return { success: false, error: 'Failed to create category' };
    } catch (error: unknown) {
      return { success: false, error: extractApiError(error, 'Failed to create category') };
    }
  }

  /**
   * Update category
   */
  static async updateCategory(catid: string, data: CategoryUpdateRequest): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.put<{ success: number; error?: string }>(`${this.baseUrl}/${catid}`, data);
      return { success: isSuccessResponse(response.data.success), error: response.data.error };
    } catch (error: unknown) {
      return { success: false, error: extractApiError(error, 'Failed to update category') };
    }
  }

  /**
   * Delete category
   */
  static async deleteCategory(catid: string): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.delete<{ success: number; error?: string }>(`${this.baseUrl}/${catid}`);
      return { success: isSuccessResponse(response.data.success), error: response.data.error };
    } catch (error: unknown) {
      return { success: false, error: extractApiError(error, 'Failed to delete category') };
    }
  }

  /**
   * Trigger category scan
   */
  static async scanCategory(catid: string): Promise<{ success: boolean; task_id?: number; error?: string }> {
    try {
      const response = await apiClient.post<{ success: number; task_id?: number; error?: string }>(
        `${this.baseUrl}/${catid}/scan`
      );
      return {
        success: isSuccessResponse(response.data.success),
        task_id: response.data.task_id,
        error: response.data.error
      };
    } catch (error: unknown) {
      return { success: false, error: extractApiError(error, 'Failed to trigger scan') };
    }
  }
}
