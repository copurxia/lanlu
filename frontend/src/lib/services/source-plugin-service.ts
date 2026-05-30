'use client';

import { apiClient } from '../api';
import { extractApiError } from '@/lib/utils/api-utils';
import { TaskPoolService } from './taskpool-service';
import type { Task } from '@/types/task';

export interface SourcePluginSummary {
  namespace: string;
  name: string;
  version: string;
  description: string;
  author: string;
  icon: string;
  enabled: boolean;
  tags: string;
}

export interface SourceItem {
  id: string;
  title: string;
  subtitle?: string;
  cover?: string;
  tags?: string[];
  source?: string;
  page_count?: number;
}

export interface SourceBrowseResult {
  success: boolean;
  error?: string;
  data?: {
    items: SourceItem[];
    next_page?: number;
  };
}

export interface SourceArchive {
  id: string;
  title: string;
  filename?: string;
  size?: number;
}

export interface SourceDetailResult {
  success: boolean;
  error?: string;
  data?: {
    id: string;
    title: string;
    description?: string;
    cover?: string;
    tags?: string[];
    archives: SourceArchive[];
  };
}

export interface SourceDownloadResult {
  success: boolean;
  task_id?: number;
  error?: string;
}

type SourceTaskEnqueueResponse = {
  success?: boolean | number;
  job?: number | string;
  task_id?: number | string;
  task_type?: string;
  error?: string;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export class SourcePluginService {
  static async listSourcePlugins(): Promise<SourcePluginSummary[]> {
    const response = await apiClient.get('/api/admin/source-plugins');
    return Array.isArray(response.data) ? response.data : [];
  }

  static async home(namespace: string, params?: Record<string, unknown>): Promise<SourceBrowseResult> {
    try {
      const parsed = await this.executeAction(namespace, 'source_home', params || {}, 'Failed to browse home');
      return this.parseBrowseResult(parsed, 'Failed to browse home');
    } catch (error) {
      return { success: false, error: extractApiError(error, 'Failed to browse home') };
    }
  }

  static async search(
    namespace: string,
    query: string,
    page?: number,
    params?: Record<string, unknown>
  ): Promise<SourceBrowseResult> {
    try {
      const parsed = await this.executeAction(
        namespace,
        'source_search',
        { query, page: page ?? 1, ...params },
        'Failed to search'
      );
      return this.parseBrowseResult(parsed, 'Failed to search');
    } catch (error) {
      return { success: false, error: extractApiError(error, 'Failed to search') };
    }
  }

  static async detail(namespace: string, remoteId: string): Promise<SourceDetailResult> {
    try {
      const parsed = await this.executeAction(
        namespace,
        'source_detail',
        { remote_id: remoteId },
        'Failed to get detail'
      );
      return this.parseDetailResult(parsed, 'Failed to get detail');
    } catch (error) {
      return { success: false, error: extractApiError(error, 'Failed to get detail') };
    }
  }

  static async download(
    namespace: string,
    remoteId: string,
    archiveId: string,
    categoryId: number
  ): Promise<SourceDownloadResult> {
    try {
      const response = await apiClient.post(
        `/api/admin/source-plugins/${namespace}/download`,
        {
          remote_id: remoteId,
          archive_id: archiveId,
          category_id: String(categoryId),
        }
      );
      return response.data;
    } catch (error) {
      return { success: false, error: extractApiError(error, 'Failed to create download task') };
    }
  }

  private static async executeAction(
    namespace: string,
    action: string,
    params: Record<string, unknown>,
    fallbackError: string
  ): Promise<Record<string, unknown>> {
    const response = await apiClient.post(
      `/api/admin/source-plugins/${encodeURIComponent(namespace)}/action/${encodeURIComponent(action)}`,
      params
    );
    return this.waitForSourceTask(response.data, fallbackError);
  }

  private static async waitForSourceTask(
    enqueueResponse: SourceTaskEnqueueResponse,
    fallbackError: string
  ): Promise<Record<string, unknown>> {
    const ok = Boolean(enqueueResponse?.success);
    if (!ok) {
      return { success: false, error: enqueueResponse?.error || fallbackError };
    }

    const jobId = this.readTaskId(enqueueResponse);
    if (!jobId) {
      return { success: false, error: 'No source task id returned' };
    }

    const task = await TaskPoolService.waitForTaskTerminal(jobId);
    return this.parseSourceTaskOutput(task, fallbackError);
  }

  private static readTaskId(response: SourceTaskEnqueueResponse): number {
    const raw = response?.job ?? response?.task_id;
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return raw;
    }
    if (typeof raw === 'string' && raw.trim() !== '') {
      const parsed = Number(raw);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  private static parseSourceTaskOutput(task: Task, fallbackError: string): Record<string, unknown> {
    const raw = task.result?.trim();
    if (!raw) {
      return {
        success: task.status === 'completed',
        error: task.status === 'completed' ? undefined : task.message || fallbackError,
      };
    }

    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      const success = Boolean(parsed.success);
      if (!success) {
        return {
          success: false,
          error: (typeof parsed.error === 'string' ? parsed.error : undefined) || task.message || fallbackError,
        };
      }

      return parsed;
    } catch {
      return {
        success: task.status === 'completed',
        error: task.status === 'completed' ? fallbackError : task.message || fallbackError,
      };
    }
  }

  private static parseBrowseResult(parsed: Record<string, unknown>, fallbackError: string): SourceBrowseResult {
    if (!Boolean(parsed.success)) {
      return { success: false, error: (typeof parsed.error === 'string' ? parsed.error : undefined) || fallbackError };
    }

    const data = isRecord(parsed.data) ? parsed.data : parsed;
    const items = Array.isArray(data.items) ? data.items as SourceItem[] : [];
    const nextPage = data.next_page ?? data.nextPage;
    return {
      success: true,
      data: {
        items,
        next_page: typeof nextPage === 'number' ? nextPage : Number(nextPage) || undefined,
      },
    };
  }

  private static parseDetailResult(parsed: Record<string, unknown>, fallbackError: string): SourceDetailResult {
    if (!Boolean(parsed.success)) {
      return { success: false, error: (typeof parsed.error === 'string' ? parsed.error : undefined) || fallbackError };
    }

    const data = isRecord(parsed.data) ? parsed.data : parsed;
    return {
      success: true,
      data: {
        id: typeof data.id === 'string' ? data.id : '',
        title: typeof data.title === 'string' ? data.title : '',
        description: typeof data.description === 'string' ? data.description : undefined,
        cover: typeof data.cover === 'string' ? data.cover : undefined,
        tags: Array.isArray(data.tags) ? data.tags as string[] : undefined,
        archives: Array.isArray(data.archives) ? data.archives as SourceArchive[] : [],
      },
    };
  }
}
