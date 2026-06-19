'use client';

import { apiClient } from '../api';
import { extractApiError } from '@/lib/utils/api-utils';
import {
  sourceDirectActionLimiter,
} from '@/lib/utils/concurrency-limiter';

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
  source_namespace: string;
  remote_id: string;
  kind: 'archive' | 'tankoubon';
  title: string;
  subtitle?: string;
  cover?: string;
  tags?: string[];
  description?: string;
  page_count?: number;
  children?: SourceItem[];
}

export interface SourceBrowseResult {
  success: boolean;
  error?: string;
  data?: {
    items: SourceItem[];
    next_page?: number;
  };
}

export interface SourceDetailResult {
  success: boolean;
  error?: string;
  data?: SourceItem;
}

export interface SourceFilterOption {
  label: string;
  value: string;
}

export interface SourceFilter {
  key: string;
  label: string;
  type: 'tabs' | 'select' | 'multi-select' | 'toggle' | 'text' | 'range';
  options?: SourceFilterOption[];
  default?: string | string[] | boolean;
}

export interface SourceFilterSchema {
  filters: SourceFilter[];
}

export interface SourceFilterResult {
  success: boolean;
  filters?: SourceFilter[];
  error?: string;
}

export interface SourceDownloadResult {
  success: boolean;
  task_id?: number;
  error?: string;
}



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


  static async getFilters(namespace: string): Promise<SourceFilterResult> {
    try {
      const parsed = await this.executeAction(
        namespace,
        'source_filters',
        {},
        'Failed to get source filters'
      );
      if (!Boolean(parsed.success)) {
        return { success: false, error: (typeof parsed.error === 'string' ? parsed.error : undefined) };
      }
      const data = isRecord(parsed.data) ? parsed.data : parsed;
      const filters = Array.isArray(data.filters) ? (data.filters as unknown[]) : [];
      const validated: SourceFilter[] = [];
      for (const raw of filters) {
        if (!isRecord(raw)) continue;
        const key = String(raw.key ?? '');
        const label = String(raw.label ?? '');
        const type = String(raw.type ?? '');
        if (!key || !label || !type) continue;
        if (!['tabs', 'select', 'multi-select', 'toggle', 'text', 'range'].includes(type)) continue;
        const options = Array.isArray(raw.options)
          ? (raw.options as unknown[]).filter(isRecord).map((o) => ({
              label: String(o.label ?? ''),
              value: String(o.value ?? ''),
            }))
          : undefined;
        validated.push({ key, label, type: type as SourceFilter['type'], options });
      }
      return { success: true, filters: validated };
    } catch (error) {
      return { success: false, error: extractApiError(error, 'Failed to get source filters') };
    }
  }


  static async download(
    namespace: string,
    remoteId: string,
    categoryId: number,
    kind: 'archive' | 'tankoubon' = 'archive'
  ): Promise<SourceDownloadResult> {
    try {
      const response = await apiClient.post(
        `/api/admin/source-plugins/${encodeURIComponent(namespace)}/download`,
        { remote_id: remoteId, category_id: String(categoryId), kind }
      );
      return response.data as SourceDownloadResult;
    } catch (error) {
      return { success: false, error: extractApiError(error, 'Failed to create download task') };
    }
  }

  private static async executeAction(
    namespace: string,
    action: string,
    params: Record<string, unknown>,
    fallbackError: string,
    signal?: AbortSignal
  ): Promise<Record<string, unknown>> {
    return sourceDirectActionLimiter.run(async () => {
      try {
        const response = await apiClient.post(
          `/api/admin/source-plugins/${encodeURIComponent(namespace)}/action/${encodeURIComponent(action)}`,
          params,
          { signal }
        );
        // 浏览类 action 后端已改为直连返回 { success, data, error }
        const data = response.data as Record<string, unknown>;
        return data;
      } catch (error) {
        return { success: false, error: extractApiError(error, fallbackError) };
      }
    });
  }

  private static parseBrowseResult(parsed: Record<string, unknown>, fallbackError: string): SourceBrowseResult {
    if (!Boolean(parsed.success)) {
      return { success: false, error: (typeof parsed.error === 'string' ? parsed.error : undefined) || fallbackError };
    }

    const data = isRecord(parsed.data) ? parsed.data : parsed;
    const rawItems = Array.isArray(data.items) ? data.items : [];
    const items: SourceItem[] = [];
    for (const raw of rawItems) {
      if (!isRecord(raw)) continue;
      const kind = raw.kind;
      if (kind !== 'archive' && kind !== 'tankoubon') continue;
      const remoteId = String(raw.remote_id ?? '');
      if (!remoteId) continue;
      const sourceNs = String(raw.source_namespace ?? '');
      if (!sourceNs) continue;
      const item: SourceItem = {
        source_namespace: sourceNs,
        remote_id: remoteId,
        kind: kind as 'archive' | 'tankoubon',
        title: String(raw.title ?? ''),
        subtitle: typeof raw.subtitle === 'string' ? raw.subtitle : undefined,
        cover: typeof raw.cover === 'string' ? raw.cover : undefined,
        tags: Array.isArray(raw.tags) ? raw.tags as string[] : undefined,
        description: typeof raw.description === 'string' ? raw.description : undefined,
        page_count: typeof raw.page_count === 'number' ? raw.page_count : undefined,
        children: Array.isArray(raw.children) ? this.parseChildren(raw.children as unknown[]) : undefined,
      };
      items.push(item);
    }

    const nextPage = data.next_page ?? data.nextPage;
    return {
      success: true,
      data: {
        items,
        next_page: typeof nextPage === 'number' ? nextPage : Number(nextPage) || undefined,
      },
    };
  }

  private static parseChildren(rawChildren: unknown[]): SourceItem[] {
    const children: SourceItem[] = [];
    for (const raw of rawChildren) {
      if (!isRecord(raw)) continue;
      const kind = raw.kind;
      if (kind !== 'archive' && kind !== 'tankoubon') continue;
      const remoteId = String(raw.remote_id ?? '');
      if (!remoteId) continue;
      const sourceNs = String(raw.source_namespace ?? '');
      if (!sourceNs) continue;
      const item: SourceItem = {
        source_namespace: sourceNs,
        remote_id: remoteId,
        kind: kind as 'archive' | 'tankoubon',
        title: String(raw.title ?? ''),
        subtitle: typeof raw.subtitle === 'string' ? raw.subtitle : undefined,
        cover: typeof raw.cover === 'string' ? raw.cover : undefined,
        tags: Array.isArray(raw.tags) ? raw.tags as string[] : undefined,
        description: typeof raw.description === 'string' ? raw.description : undefined,
        page_count: typeof raw.page_count === 'number' ? raw.page_count : undefined,
        children: Array.isArray(raw.children) ? this.parseChildren(raw.children as unknown[]) : undefined,
      };
      children.push(item);
    }
    return children;
  }

  private static parseDetailResult(parsed: Record<string, unknown>, fallbackError: string): SourceDetailResult {
    if (!Boolean(parsed.success)) {
      return { success: false, error: (typeof parsed.error === 'string' ? parsed.error : undefined) || fallbackError };
    }

    const data = isRecord(parsed.data) ? parsed.data : parsed;
    const kind = data.kind;
    if (kind !== 'archive' && kind !== 'tankoubon') {
      return { success: false, error: 'Invalid detail result: missing or invalid kind' };
    }
    const remoteId = String(data.remote_id ?? '');
    if (!remoteId) {
      return { success: false, error: 'Invalid detail result: missing remote_id' };
    }
    const sourceNs = String(data.source_namespace ?? '');
    if (!sourceNs) {
      return { success: false, error: 'Invalid detail result: missing source_namespace' };
    }

    const item: SourceItem = {
      source_namespace: sourceNs,
      remote_id: remoteId,
      kind: kind as 'archive' | 'tankoubon',
      title: String(data.title ?? ''),
      subtitle: typeof data.subtitle === 'string' ? data.subtitle : undefined,
      cover: typeof data.cover === 'string' ? data.cover : undefined,
      tags: Array.isArray(data.tags) ? data.tags as string[] : undefined,
      description: typeof data.description === 'string' ? data.description : undefined,
      page_count: typeof data.page_count === 'number' ? data.page_count : undefined,
      children: Array.isArray(data.children) ? this.parseChildren(data.children as unknown[]) : undefined,
    };
    return {
      success: true,
      data: item,
    };
  }
}
