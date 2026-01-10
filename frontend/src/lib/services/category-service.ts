import { apiClient } from '@/lib/api';

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
    if (response.data.success === 1) {
      const data = response.data.data;
      return Array.isArray(data) ? data : [data];
    }
    return [];
  }

  /**
   * Get category by ID
   */
  static async getCategoryById(catid: string): Promise<Category | null> {
    const response = await apiClient.get<CategoryResponse>(`${this.baseUrl}/${catid}`);
    if (response.data.success === 1) {
      const data = response.data.data;
      return Array.isArray(data) ? data[0] : data;
    }
    return null;
  }

  /**
   * Create a new category
   */
  static async createCategory(data: CategoryCreateRequest): Promise<{ success: boolean; category?: Category; error?: string }> {
    try {
      const response = await apiClient.post<CategoryResponse>(this.baseUrl, data);
      if (response.data.success === 1) {
        const cat = response.data.data;
        return { success: true, category: Array.isArray(cat) ? cat[0] : cat };
      }
      return { success: false, error: 'Failed to create category' };
    } catch (error: unknown) {
      const err = error as { response?: { data?: { error?: string } } };
      return { success: false, error: err.response?.data?.error || 'Failed to create category' };
    }
  }

  /**
   * Update category
   */
  static async updateCategory(catid: string, data: CategoryUpdateRequest): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.put<{ success: number; error?: string }>(`${this.baseUrl}/${catid}`, data);
      return { success: response.data.success === 1, error: response.data.error };
    } catch (error: unknown) {
      const err = error as { response?: { data?: { error?: string } } };
      return { success: false, error: err.response?.data?.error || 'Failed to update category' };
    }
  }

  /**
   * Delete category
   */
  static async deleteCategory(catid: string): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await apiClient.delete<{ success: number; error?: string }>(`${this.baseUrl}/${catid}`);
      return { success: response.data.success === 1, error: response.data.error };
    } catch (error: unknown) {
      const err = error as { response?: { data?: { error?: string } } };
      return { success: false, error: err.response?.data?.error || 'Failed to delete category' };
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
        success: response.data.success === 1,
        task_id: response.data.task_id,
        error: response.data.error
      };
    } catch (error: unknown) {
      const err = error as { response?: { data?: { error?: string } } };
      return { success: false, error: err.response?.data?.error || 'Failed to trigger scan' };
    }
  }
}
