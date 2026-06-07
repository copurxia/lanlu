'use client';

import { apiClient } from '../api';
import { extractApiError } from '@/lib/utils/api-utils';
import {
  sourceCoverAssetLimiter,
  sourceDirectActionLimiter,
  sourcePageAssetLimiter,
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
  cover_asset_id?: number;
  tags?: string[];
  description?: string;
  page_count?: number;
  downloadable?: boolean;
  readable?: boolean;
  children?: SourceItem[];
  reader?: {
    page_count?: number;
    media_type?: string;
    reader_action?: string;
    download_action?: string;
  };
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

  static async reader(
    namespace: string,
    remoteId: string,
    archiveId?: string,
    parentRemoteId?: string
  ): Promise<{ success: boolean; error?: string; data?: { pages: Array<{ path: string; url?: string; asset_id?: number; type?: string; width?: number; height?: number; metadata?: Record<string, unknown> }> } }> {
    try {
      const params: Record<string, unknown> = { remote_id: remoteId };
      if (archiveId) {
        params.archive_id = archiveId;
      }
      if (parentRemoteId) {
        params.parent_remote_id = parentRemoteId;
      }
      const parsed = await this.executeAction(
        namespace,
        'source_reader',
        params,
        'Failed to get reader pages'
      );
      if (!Boolean(parsed.success)) {
        return { success: false, error: (typeof parsed.error === 'string' ? parsed.error : undefined) || 'Failed to get reader pages' };
      }
      const data = isRecord(parsed.data) ? parsed.data : parsed;
      const pages = Array.isArray(data.pages) ? data.pages : [];
      return { success: true, data: { pages } };
    } catch (error) {
      return { success: false, error: extractApiError(error, 'Failed to get reader pages') };
    }
  }

  /**
   * 按需获取单页资产。Reader 翻页时调用，避免一次性下载全部页面。
   * 输入: remote_id, parent_remote_id (可选), page, path
   * 输出: { success, data: { asset_id } }
   */
  static async pageAsset(
    namespace: string,
    remoteId: string,
    page: number,
    path: string,
    parentRemoteId?: string,
    signal?: AbortSignal
  ): Promise<{ success: boolean; error?: string; data?: { asset_id: number } }> {
    return sourcePageAssetLimiter.run(async () => {
      try {
        const params: Record<string, unknown> = {
          remote_id: remoteId,
          page,
          path,
        };
        if (parentRemoteId) {
          params.parent_remote_id = parentRemoteId;
        }
        const parsed = await this.executeAction(
          namespace,
          'source_page_asset',
          params,
          'Failed to get page asset',
          signal
        );
        if (!Boolean(parsed.success)) {
          return { success: false, error: (typeof parsed.error === 'string' ? parsed.error : undefined) || 'Failed to get page asset' };
        }
        const data = isRecord(parsed.data) ? parsed.data : parsed;
        const assetId = typeof data.asset_id === 'number' ? data.asset_id : 0;
        if (assetId <= 0) {
          return { success: false, error: 'Invalid asset_id from source_page_asset' };
        }
        return { success: true, data: { asset_id: assetId } };
      } catch (error) {
        return { success: false, error: extractApiError(error, 'Failed to get page asset') };
      }
    });
  }

  /**
   * 按需获取 Source 列表/搜索封面资产。
   * 输入: remote_id, cover_ref
   * 输出: { success, data: { asset_id } }
   */
  static async coverAsset(
    namespace: string,
    remoteId: string,
    coverRef: string,
    signal?: AbortSignal
  ): Promise<{ success: boolean; error?: string; data?: { asset_id: number } }> {
    return sourceCoverAssetLimiter.run(async () => {
      try {
        const parsed = await this.executeAction(
          namespace,
          'source_cover_asset',
          {
            remote_id: remoteId,
            cover_ref: coverRef,
          },
          'Failed to get cover asset',
          signal
        );
        if (!Boolean(parsed.success)) {
          return { success: false, error: (typeof parsed.error === 'string' ? parsed.error : undefined) || 'Failed to get cover asset' };
        }
        const data = isRecord(parsed.data) ? parsed.data : parsed;
        const assetId = typeof data.asset_id === 'number' ? data.asset_id : 0;
        if (assetId <= 0) {
          return { success: false, error: 'Invalid asset_id from source_cover_asset' };
        }
        return { success: true, data: { asset_id: assetId } };
      } catch (error) {
        return { success: false, error: extractApiError(error, 'Failed to get cover asset') };
      }
    });
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
    kind: 'archive' | 'tankoubon' = 'archive',
    parentRemoteId?: string
  ): Promise<SourceDownloadResult> {
    try {
      const payload: Record<string, string> = {
        remote_id: remoteId,
        category_id: String(categoryId),
        kind,
      };
      if (parentRemoteId) {
        payload.parent_remote_id = parentRemoteId;
      }
      const response = await apiClient.post(
        `/api/admin/source-plugins/${namespace}/download`,
        payload
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
        cover_asset_id: typeof raw.cover_asset_id === 'number' ? raw.cover_asset_id : undefined,
        tags: Array.isArray(raw.tags) ? raw.tags as string[] : undefined,
        description: typeof raw.description === 'string' ? raw.description : undefined,
        page_count: typeof raw.page_count === 'number' ? raw.page_count : undefined,
        downloadable: Boolean(raw.downloadable),
        readable: Boolean(raw.readable),
        children: Array.isArray(raw.children) ? this.parseChildren(raw.children as unknown[]) : undefined,
        reader: isRecord(raw.reader) ? {
          page_count: typeof raw.reader.page_count === 'number' ? raw.reader.page_count : undefined,
          media_type: typeof raw.reader.media_type === 'string' ? raw.reader.media_type : undefined,
          reader_action: typeof raw.reader.reader_action === 'string' ? raw.reader.reader_action : undefined,
          download_action: typeof raw.reader.download_action === 'string' ? raw.reader.download_action : undefined,
        } : undefined,
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
        cover_asset_id: typeof raw.cover_asset_id === 'number' ? raw.cover_asset_id : undefined,
        tags: Array.isArray(raw.tags) ? raw.tags as string[] : undefined,
        description: typeof raw.description === 'string' ? raw.description : undefined,
        page_count: typeof raw.page_count === 'number' ? raw.page_count : undefined,
        downloadable: Boolean(raw.downloadable),
        readable: Boolean(raw.readable),
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
      cover_asset_id: typeof data.cover_asset_id === 'number' ? data.cover_asset_id : undefined,
      tags: Array.isArray(data.tags) ? data.tags as string[] : undefined,
      description: typeof data.description === 'string' ? data.description : undefined,
      page_count: typeof data.page_count === 'number' ? data.page_count : undefined,
      downloadable: Boolean(data.downloadable),
      readable: Boolean(data.readable),
      children: Array.isArray(data.children) ? this.parseChildren(data.children as unknown[]) : undefined,
      reader: isRecord(data.reader) ? {
        page_count: typeof data.reader.page_count === 'number' ? data.reader.page_count : undefined,
        media_type: typeof data.reader.media_type === 'string' ? data.reader.media_type : undefined,
        reader_action: typeof data.reader.reader_action === 'string' ? data.reader.reader_action : undefined,
        download_action: typeof data.reader.download_action === 'string' ? data.reader.download_action : undefined,
      } : undefined,
    };

    return {
      success: true,
      data: item,
    };
  }
}
