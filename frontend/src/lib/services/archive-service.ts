import { apiClient } from '../api';
import { Archive, SearchResponse, SearchParams, ArchiveMetadata, MetadataAssetInput, MetadataObject, MetadataUpdatePayload, ArchiveFilesParams } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';
import { ServerInfo } from '@/types/server';
import { ChunkedUploadService, UploadMetadata, UploadProgressCallback, UploadResult } from './chunked-upload-service';
import { TaskPoolService } from './taskpool-service';
import { buildQueryParams, isSuccessResponse } from '@/lib/utils/api-utils';
import type { Task } from '@/types/task';
import { normalizeArchiveAssets, normalizeArchivePayload } from '@/lib/utils/archive-assets';
import { normalizeArchiveMetadata } from '@/lib/utils/metadata';

// 下载相关接口定义
export interface DownloadMetadata {
  title?: string;
  tags?: string;
  summary?: string;
  categoryId?: string | number;
}

export interface DownloadProgressCallback {
  onProgress?: (progress: number) => void;
  onComplete?: (result: DownloadResult) => void;
  onError?: (error: string) => void;
}

export interface DownloadResult {
  success: boolean;
  archives: Array<{
    relativePath: string;
    pluginRelativePath: string;
    filename: string;
  }>;
  id?: string;
  error?: string;
}

export interface MetadataPluginRunCallbacks {
  onUpdate?: (task: Task) => void;
}

export type MetadataPluginAssetInput = MetadataAssetInput;

export interface MetadataPluginInputMetadata extends MetadataObject {
  assets?: MetadataPluginAssetInput[];
  children?: MetadataPluginInputMetadata[];
  pages?: MetadataPagePatchInput[];
}

export interface MetadataPluginRunOptions {
  writeBack?: boolean;
  metadata?: MetadataPluginInputMetadata;
}

export interface MetadataPagePatchInput {
  page_number?: number;
  entry_path?: string;
  title?: string;
  description?: string;
  thumb?: string;
  lyrics?: string;
  lyrics_asset_id?: number;
  order_index?: number;
  hidden_in_files?: boolean;
  release_at?: string;
}

export interface PageSourceInfo {
  id: string;
  path: string;
  url: string;
  type: 'image' | 'video' | 'audio' | 'html';
  title?: string;
  metadata?: {
    title?: string;
    description?: string;
    thumb_asset_id?: number;
    thumb?: string;
    lyrics_asset_id?: number;
    release_at?: string;
  };
}

// 页面信息接口（支持图片、视频和HTML）
export interface PageInfo {
  id: string;
  type: 'image' | 'video' | 'audio' | 'html';
  title?: string;  // 章节标题（EPUB类型会有值）
  groupKey?: string;
  defaultSourceIndex?: number;
  sourceCount?: number;
  defaultSource?: PageSourceInfo;
  sources?: PageSourceInfo[];
  metadata?: {
    title?: string;
    description?: string;
    thumb_asset_id?: number;
    thumb?: string;
    lyrics_asset_id?: number;
    release_at?: string;
  };
}

export class ArchiveService {
  private static readonly METADATA_CACHE_TTL_MS = 30_000;
  private static readonly metadataCache = new Map<string, { expiresAt: number; data: ArchiveMetadata }>();
  private static readonly metadataInflight = new Map<string, Promise<ArchiveMetadata>>();
  private static readonly SERVER_INFO_CACHE_TTL_MS = 5 * 60_000;
  private static readonly SERVER_INFO_CACHE_KEY = 'lanlu:server-info-cache:v1';
  private static serverInfoCache: { expiresAt: number; data: ServerInfo } | null = null;
  private static serverInfoInflight: Promise<ServerInfo> | null = null;

  private static buildMetadataCacheKey(id: string, lang?: string, options?: { includePages?: boolean }): string {
    return `${id}|${lang || ''}|${options?.includePages ? 'pages' : 'meta'}`;
  }

  private static invalidateMetadataCache(id: string): void {
    const prefix = `${id}|`;
    for (const key of this.metadataCache.keys()) {
      if (key.startsWith(prefix)) this.metadataCache.delete(key);
    }
    for (const key of this.metadataInflight.keys()) {
      if (key.startsWith(prefix)) this.metadataInflight.delete(key);
    }
  }

  private static isArchiveItem(item: unknown): item is Archive {
    return Boolean(item) && typeof item === 'object' && 'arcid' in (item as Record<string, unknown>);
  }

  private static normalizeArchiveItem(item: Archive): Archive {
    const normalized = normalizeArchivePayload(item);
    return {
      ...normalized,
      description: String((normalized as any).description || '').trim(),
    };
  }

  private static normalizeMixedItems(items: unknown[]): Array<Archive | Tankoubon> {
    return items.map((item) => {
      if (this.isArchiveItem(item)) {
        return this.normalizeArchiveItem(item);
      }
      const tank = item as Tankoubon & { assets?: unknown; children?: unknown };
      return {
        ...tank,
        title: String((tank as any).title || '').trim(),
        description: String((tank as any).description || '').trim(),
        children: Array.isArray(tank.children)
          ? tank.children.map((value) => String(value || '').trim()).filter(Boolean)
          : [],
        assets: normalizeArchiveAssets(tank.assets),
      };
    });
  }

  private static extractPathFromPageUrl(url: string): string {
    const raw = String(url || '').trim();
    if (!raw) return '';

    try {
      const parsed = new URL(raw, typeof window !== 'undefined' ? window.location.origin : 'http://localhost');
      const queryPath = parsed.searchParams.get('path');
      if (queryPath) return queryPath;
    } catch {
      // ignore and try lightweight parsing fallback
    }

    const marker = 'path=';
    const markerIndex = raw.indexOf(marker);
    if (markerIndex < 0) return '';
    const encoded = raw.slice(markerIndex + marker.length).split('&')[0];
    try {
      return decodeURIComponent(encoded);
    } catch {
      return encoded;
    }
  }

  static async search(params: SearchParams, options?: { signal?: AbortSignal }): Promise<SearchResponse> {
    const normalizedParams: Record<string, unknown> = { ...params };
    normalizedParams.page = Math.max(1, Math.trunc(params.page ?? 1));
    normalizedParams.pageSize = Math.max(1, Math.trunc(params.pageSize ?? 20));

    const response = await apiClient.get('/api/search', { params: normalizedParams, signal: options?.signal });
    const data = Array.isArray(response.data?.data) ? this.normalizeMixedItems(response.data.data) : [];
    const groups = Array.isArray(response.data?.groups)
      ? response.data.groups.map((group: any) => ({
          ...group,
          category_id: String(group?.category_id || '').trim(),
          data: Array.isArray(group?.data) ? this.normalizeMixedItems(group.data) : [],
          recordsFiltered: Number(group?.recordsFiltered || 0),
          recordsTotal: Number(group?.recordsTotal || 0),
        }))
      : undefined;
    return {
      ...response.data,
      data,
      groups,
    };
  }

  static async getMetadata(id: string, lang?: string, options?: { includePages?: boolean }): Promise<ArchiveMetadata> {
    const cacheKey = this.buildMetadataCacheKey(id, lang, options);
    const now = Date.now();
    const cached = this.metadataCache.get(cacheKey);
    if (cached && cached.expiresAt > now) {
      return cached.data;
    }

    const inflight = this.metadataInflight.get(cacheKey);
    if (inflight) {
      return inflight;
    }

    const request = (async () => {
      const params: Record<string, string> = {};
      if (lang) {
        params.lang = lang;
      }
      if (options?.includePages) {
        params.include_pages = '1';
      }
      const response = await apiClient.get(`/api/archives/${id}/metadata`, { params });
      const normalized = normalizeArchiveMetadata(response.data);
      this.metadataCache.set(cacheKey, {
        data: normalized,
        expiresAt: Date.now() + this.METADATA_CACHE_TTL_MS,
      });
      return normalized;
    })().finally(() => {
      this.metadataInflight.delete(cacheKey);
    });

    this.metadataInflight.set(cacheKey, request);
    return request;
  }

  static async updateMetadata(
    id: string,
    metadata: MetadataUpdatePayload,
    lang?: string
  ): Promise<void> {
    const params = buildQueryParams({ lang: lang || undefined });
    const query = params.toString();
    const url = query ? `/api/archives/${id}/metadata?${query}` : `/api/archives/${id}/metadata`;
    await apiClient.put(url, metadata);
    this.invalidateMetadataCache(id);
  }

  static async getFiles(id: string, params?: ArchiveFilesParams): Promise<{ pages: PageInfo[] }> {
    const response = await apiClient.get(`/api/archives/${id}/files`, { params });
    const pages = (response.data.pages || []).map((rawPage: any): PageInfo => {
      const normalizeMetadata = (rawMetadata: any) => {
        if (!rawMetadata) return undefined;
        const rawThumbAssetId = Number(rawMetadata.thumb_asset_id || 0);
        const thumbAssetId = Number.isFinite(rawThumbAssetId) && rawThumbAssetId > 0 ? rawThumbAssetId : 0;
        const rawLyricsAssetId = Number(rawMetadata.lyrics_asset_id || 0);
        const lyricsAssetId = Number.isFinite(rawLyricsAssetId) && rawLyricsAssetId > 0 ? rawLyricsAssetId : 0;
        const legacyThumb = typeof rawMetadata.thumb === 'string' ? rawMetadata.thumb : '';
        const thumbUrl = thumbAssetId > 0
          ? this.addTokenToUrl(`/api/assets/${thumbAssetId}`)
          : legacyThumb
          ? this.addTokenToUrl(legacyThumb)
          : '';

        return {
          ...rawMetadata,
          thumb_asset_id: thumbAssetId > 0 ? thumbAssetId : undefined,
          thumb: thumbUrl || undefined,
          lyrics_asset_id: lyricsAssetId > 0 ? lyricsAssetId : undefined,
          release_at:
            typeof rawMetadata.release_at === 'string' && rawMetadata.release_at.trim()
              ? rawMetadata.release_at.trim()
              : undefined,
        };
      };

      const normalizePath = (raw: any): string => {
        return typeof raw?.path === 'string' && raw.path.trim()
          ? raw.path
          : this.extractPathFromPageUrl(String(raw?.url || ''));
      };

      const buildPageUrl = (path: string, fallbackUrl: string): string => {
        return path
          ? this.addTokenToUrl(this.getPageUrl(id, path))
          : this.addTokenToUrl(String(fallbackUrl || ''));
      };

      const path = normalizePath(rawPage);
      const metadata = normalizeMetadata(rawPage?.metadata);
      const rawDefaultSource = rawPage?.default_source ?? rawPage?.defaultSource;
      const sources = Array.isArray(rawPage?.sources)
        ? rawPage.sources.map((rawSource: any): PageSourceInfo => {
            const sourcePath = normalizePath(rawSource);
            return {
              id:
                typeof rawSource?.id === 'string' && rawSource.id.trim()
                  ? rawSource.id.trim()
                  : sourcePath || String(rawSource?.title || '').trim() || `${rawPage?.group_key || path}-source`,
              path: sourcePath,
              url: buildPageUrl(sourcePath, String(rawSource?.url || '')),
              type:
                rawSource?.type === 'video' || rawSource?.type === 'audio' || rawSource?.type === 'html'
                  ? rawSource.type
                  : 'image',
              title: typeof rawSource?.title === 'string' && rawSource.title.trim() ? rawSource.title.trim() : undefined,
              metadata: normalizeMetadata(rawSource?.metadata),
            };
          })
        : undefined;
      const rawDefaultSourceIndex = Number(rawPage?.default_source_index ?? rawPage?.defaultSourceIndex ?? 0);
      const defaultSourceIndex =
        Number.isFinite(rawDefaultSourceIndex) && rawDefaultSourceIndex >= 0 ? Math.trunc(rawDefaultSourceIndex) : 0;
      const sourceCount = Array.isArray(sources) ? sources.length : Number(rawPage?.source_count || 0);
      const fallbackDefaultSource = (rawDefaultSource || path)
        ? {
            id:
              typeof rawDefaultSource?.id === 'string' && rawDefaultSource.id.trim()
                ? rawDefaultSource.id.trim()
                : typeof rawPage?.id === 'string' && rawPage.id.trim()
                ? rawPage.id.trim()
                : normalizePath(rawDefaultSource) || path,
            path: normalizePath(rawDefaultSource) || path,
            url: buildPageUrl(normalizePath(rawDefaultSource) || path, String(rawDefaultSource?.url || rawPage?.url || '')),
            type:
              rawDefaultSource?.type === 'video' || rawDefaultSource?.type === 'audio' || rawDefaultSource?.type === 'html'
                ? rawDefaultSource.type
                : rawPage?.type === 'video' || rawPage?.type === 'audio' || rawPage?.type === 'html'
                ? rawPage.type
                : 'image',
            title:
              typeof rawDefaultSource?.title === 'string' && rawDefaultSource.title.trim()
                ? rawDefaultSource.title.trim()
                : typeof rawPage?.title === 'string' && rawPage.title.trim()
                ? rawPage.title.trim()
                : undefined,
            metadata: normalizeMetadata(rawDefaultSource?.metadata) || metadata,
          } satisfies PageSourceInfo
        : undefined;
      const defaultSource =
        sources && sources.length > 0
          ? sources[Math.max(0, Math.min(sources.length - 1, defaultSourceIndex))]
          : fallbackDefaultSource;

      return {
        id:
          typeof rawPage?.id === 'string' && rawPage.id.trim()
            ? rawPage.id.trim()
            : typeof rawPage?.group_key === 'string' && rawPage.group_key.trim()
            ? rawPage.group_key.trim()
            : defaultSource?.id || path,
        type:
          rawPage?.type === 'video' || rawPage?.type === 'audio' || rawPage?.type === 'html'
            ? rawPage.type
            : 'image',
        title: typeof rawPage?.title === 'string' && rawPage.title.trim() ? rawPage.title.trim() : undefined,
        groupKey:
          typeof rawPage?.group_key === 'string' && rawPage.group_key.trim()
            ? rawPage.group_key.trim()
            : undefined,
        defaultSourceIndex,
        sourceCount: sourceCount > 0 ? sourceCount : undefined,
        defaultSource,
        sources: sources && sources.length > 0 ? sources : undefined,
        metadata,
      };
    });
    return {
      pages,
    };
  }

  /**
   * 设置归档为新状态（PUT /api/archives/:id/isnew）
   */
  static async setIsNew(id: string): Promise<void> {
    await apiClient.put(`/api/archives/${id}/isnew`);
    this.invalidateMetadataCache(id);
  }

  /**
   * 清除归档的新标记（DELETE /api/archives/:id/isnew）
   */
  static async clearIsNew(id: string): Promise<void> {
    await apiClient.delete(`/api/archives/${id}/isnew`);
    this.invalidateMetadataCache(id);
  }

  /**
   * 更新阅读进度并自动标记为已读（PUT /api/archives/:id/progress/:page）
   */
  static async updateProgress(id: string, page: number): Promise<void> {
    await apiClient.put(`/api/archives/${id}/progress/${page}`);
    this.invalidateMetadataCache(id);
  }

  /**
   * 删除档案（仅管理员可用）
   */
  static async deleteArchive(id: string): Promise<void> {
    await apiClient.delete(`/api/archives/${id}`);
    this.invalidateMetadataCache(id);
  }

  static getAssetUrl(assetId?: number): string {
    if (!assetId || assetId <= 0) {
      return '';
    }
    return `/api/assets/${assetId}`;
  }

  static getPageUrl(id: string, path: string): string {
    const normalizedPath = String(path || '').trim();
    const encodedPath = encodeURIComponent(normalizedPath);
    return `/api/archives/${id}/page?path=${encodedPath}`;
  }

  static getPageDefaultSource(page: Pick<PageInfo, 'defaultSource' | 'sources' | 'defaultSourceIndex'> | null | undefined): PageSourceInfo | undefined {
    if (!page) return undefined;
    if (page.defaultSource) return page.defaultSource;
    const sources = Array.isArray(page.sources) ? page.sources : [];
    if (sources.length <= 0) return undefined;
    const sourceIndex = Math.max(0, Math.min(sources.length - 1, page.defaultSourceIndex ?? 0));
    return sources[sourceIndex];
  }

  static getPageSource(
    page: Pick<PageInfo, 'defaultSource' | 'sources' | 'defaultSourceIndex'> | null | undefined,
    sourceIndex?: number
  ): PageSourceInfo | undefined {
    if (!page) return undefined;
    const sources = Array.isArray(page.sources) ? page.sources : [];
    if (typeof sourceIndex === 'number' && sources.length > 0) {
      const clamped = Math.max(0, Math.min(sources.length - 1, sourceIndex));
      return sources[clamped];
    }
    return this.getPageDefaultSource(page);
  }

  static getPagePath(page: PageInfo | null | undefined, sourceIndex?: number): string {
    return this.getPageSource(page, sourceIndex)?.path?.trim() || '';
  }

  static getResolvedPageUrl(page: PageInfo | null | undefined, sourceIndex?: number): string {
    return this.getPageSource(page, sourceIndex)?.url?.trim() || '';
  }

  static getPageMediaType(page: PageInfo | null | undefined, sourceIndex?: number): PageSourceInfo['type'] | PageInfo['type'] | '' {
    return this.getPageSource(page, sourceIndex)?.type || page?.type || '';
  }

  static getPagePrimaryKey(page: Pick<PageInfo, 'id' | 'defaultSource' | 'sources' | 'defaultSourceIndex'> | null | undefined): string {
    if (!page) return '';
    return String(page.id || this.getPageSource(page)?.id || this.getPageSource(page)?.path || '').trim();
  }

  static getPageDisplayTitle(page: PageInfo | null | undefined, sourceIndex?: number): string {
    const source = this.getPageSource(page, sourceIndex);
    return String(source?.metadata?.title || page?.metadata?.title || source?.title || page?.title || '').trim();
  }

  static getPageDisplayMetadata(page: PageInfo | null | undefined, sourceIndex?: number): PageInfo['metadata'] | undefined {
    const source = this.getPageSource(page, sourceIndex);
    return source?.metadata || page?.metadata;
  }

  static getDownloadUrl(id: string): string {
    return `/api/archives/${id}/download`;
  }

  /**
   * Cookie 鉴权下无需再拼接 token query。
   */
  static addTokenToUrl(url: string): string {
    return url;
  }

  private static readServerInfoStorage(): { expiresAt: number; data: ServerInfo } | null {
    if (typeof window === 'undefined') return null;
    try {
      const raw = window.localStorage.getItem(this.SERVER_INFO_CACHE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as { expiresAt?: number; data?: ServerInfo };
      if (!parsed || typeof parsed.expiresAt !== 'number' || !parsed.data) return null;
      return {
        expiresAt: parsed.expiresAt,
        data: parsed.data,
      };
    } catch {
      return null;
    }
  }

  private static writeServerInfoStorage(entry: { expiresAt: number; data: ServerInfo } | null): void {
    if (typeof window === 'undefined') return;
    try {
      if (!entry) {
        window.localStorage.removeItem(this.SERVER_INFO_CACHE_KEY);
        return;
      }
      window.localStorage.setItem(this.SERVER_INFO_CACHE_KEY, JSON.stringify(entry));
    } catch {
      // ignore storage write failures
    }
  }

  static getCachedServerInfo(): ServerInfo | null {
    const now = Date.now();
    if (this.serverInfoCache && this.serverInfoCache.expiresAt > now) {
      return this.serverInfoCache.data;
    }

    const stored = this.readServerInfoStorage();
    if (stored && stored.expiresAt > now) {
      this.serverInfoCache = stored;
      return stored.data;
    }

    return null;
  }

  static async getServerInfo(options?: { force?: boolean }): Promise<ServerInfo> {
    const now = Date.now();
    if (!options?.force) {
      const cached = this.getCachedServerInfo();
      if (cached) {
        return cached;
      }
    }

    if (!options?.force && this.serverInfoInflight) {
      return this.serverInfoInflight;
    }

    const request = (async () => {
      const response = await apiClient.get('/api/info');
      const entry = {
        data: response.data as ServerInfo,
        expiresAt: Date.now() + this.SERVER_INFO_CACHE_TTL_MS,
      };
      this.serverInfoCache = entry;
      this.writeServerInfoStorage(entry);
      return entry.data;
    })().finally(() => {
      this.serverInfoInflight = null;
    });

    this.serverInfoInflight = request;
    return request;
  }

  /**
   * 新的分片上传方法（推荐使用）
   * 支持断点续传、进度显示、错误重试等功能
   */
  static async uploadArchiveWithChunks(
    file: File,
    metadata?: UploadMetadata,
    callbacks?: UploadProgressCallback
  ): Promise<UploadResult> {
    // 默认回调函数
    const defaultCallbacks: UploadProgressCallback = {
      onProgress: () => {},
      onChunkComplete: () => {},
      onError: () => {}
    };
    const mergedMetadata: UploadMetadata = {
      ...(metadata || {}),
      targetType: 'archive',
      contentType: file.type || (metadata?.contentType ?? '')
    };

    return await ChunkedUploadService.uploadWithChunks(
      file,
      mergedMetadata,
      callbacks || defaultCallbacks
    );
  }

  
  /**
   * 恢复上传
   */
  static async resumeUpload(
    taskId: string,
    file: File,
    metadata?: UploadMetadata,
    callbacks?: UploadProgressCallback
  ): Promise<UploadResult> {
    const defaultCallbacks: UploadProgressCallback = {
      onProgress: () => {},
      onChunkComplete: () => {},
      onError: () => {}
    };
    const mergedMetadata: UploadMetadata = {
      ...(metadata || {}),
      targetType: 'archive',
      contentType: file.type || (metadata?.contentType ?? '')
    };

    return await ChunkedUploadService.resumeUpload(
      taskId,
      file,
      mergedMetadata,
      callbacks || defaultCallbacks
    );
  }

  /**
   * 验证文件
   */
  static validateFile(file: File) {
    return ChunkedUploadService.validateFile(file);
  }

  /**
   * 获取错误消息
   */
  static getUploadErrorMessage(error: any): string {
    return ChunkedUploadService.getErrorMessage(error);
  }

  // ==================== 下载相关方法 ====================

  /**
   * 从单个URL下载档案
   * @param url 下载链接
   * @param metadata 下载元数据
   * @param callbacks 进度回调
   */
  static async downloadFromUrl(
    url: string,
    metadata?: DownloadMetadata,
    callbacks?: DownloadProgressCallback
  ): Promise<DownloadResult> {
    try {
      callbacks?.onProgress?.(0);

      const response = await apiClient.post('/api/download_url', {
        url,
        title: metadata?.title,
        tags: metadata?.tags,
        summary: metadata?.summary,
        category_id: metadata?.categoryId
      });

      const rawSuccess = response.data?.success;
      const enqueueSuccess = isSuccessResponse(rawSuccess);

      if (!enqueueSuccess) {
        const errorMessage = response.data?.error || 'Download failed';
        callbacks?.onError?.(errorMessage);
        return { success: false, error: errorMessage, archives: [] };
      }

      const jobId = response.data?.job;
      if (!jobId) {
        // 兼容旧返回（若后端仍直接返回id等信息）
        const result: DownloadResult = {
          success: true,
          id: response.data.id,
          error: response.data.error,
          archives: response.data.relative_path ? [{
            relativePath: response.data.relative_path,
            pluginRelativePath: response.data.plugin_relative_path,
            filename: response.data.filename
          }] : []
        };
        callbacks?.onProgress?.(100);
        callbacks?.onComplete?.(result);
        return result;
      }

      const finalTask = await this.waitForTaskCompletion(Number(jobId), (task) => {
        const p = typeof task.progress === 'number' ? task.progress : 0;
        callbacks?.onProgress?.(Math.max(0, Math.min(100, p)));
      });

      const parsed = this.parseTaskOutput(finalTask);
      if (finalTask.status === 'failed' || parsed.success === false) {
        const err = parsed.error || finalTask.result || finalTask.message || 'Download failed';
        const failResult: DownloadResult = { success: false, error: err, archives: [] };
        callbacks?.onComplete?.(failResult);
        return failResult;
      }

      const okResult: DownloadResult = {
        success: true,
        id: parsed.id,
        archives: parsed.archives || []
      };
      callbacks?.onProgress?.(100);
      callbacks?.onComplete?.(okResult);
      return okResult;
    } catch (error: any) {
      const errorMessage = error.response?.data?.error || error.message || 'Download failed';
      callbacks?.onError?.(errorMessage);

      return {
        success: false,
        error: errorMessage,
        archives: []
      };
    }
  }

  /**
   * 执行元数据插件（进入TaskPool，返回的job由前端轮询）
   */
  static async runMetadataPlugin(
    archiveId: string,
    namespace: string,
    param?: string,
    callbacks?: MetadataPluginRunCallbacks,
    options?: MetadataPluginRunOptions
  ): Promise<Task> {
    return await this.runMetadataPluginForTarget(
      'archive',
      archiveId,
      namespace,
      param,
      callbacks,
      options
    );
  }

  /**
   * 执行元数据插件（支持 archive / tankoubon 目标）
   * - Preview (writeBack=false): 返回 wasm_task，前端读取输出并填充编辑表单
   * - Write-back (writeBack=true): 返回 metadata_plugin，再跟踪 callback 任务完成持久化
   */
  static async runMetadataPluginForTarget(
    targetType: 'archive' | 'tankoubon',
    targetId: string,
    namespace: string,
    param?: string,
    callbacks?: MetadataPluginRunCallbacks,
    options?: MetadataPluginRunOptions
  ): Promise<Task> {
    const payload: Record<string, unknown> = {
      target_type: targetType,
      target_id: targetId,
      namespace,
      param: param || '',
      // Default is preview/query (no persistence). Explicitly pass the flag so behavior is stable.
      write_back: options?.writeBack ? 1 : 0,
    };
    if (options?.metadata) {
      payload.metadata = options.metadata;
    }

    const response = await apiClient.post('/api/metadata_plugin', payload);

    const rawSuccess = response.data?.success;
    const enqueueSuccess = isSuccessResponse(rawSuccess);

    if (!enqueueSuccess) {
      const errorMessage = response.data?.error || 'Metadata plugin enqueue failed';
      throw new Error(errorMessage);
    }

    const jobId = response.data?.job;
    if (!jobId) {
      throw new Error('No job id returned');
    }

    // Two modes:
    // - Preview/query (default): API returns a `wasm_task` job. Frontend reads plugin output from that task.
    // - Write-back: API returns a `metadata_plugin` job which spawns a callback that persists data.
    const taskType = String(response.data?.task_type || response.data?.taskType || '').trim();
    const writeBack = Boolean(response.data?.write_back ?? response.data?.writeBack ?? options?.writeBack);
    if (!writeBack || taskType === 'wasm_task') {
      return await this.waitForTaskCompletion(Number(jobId), (task) => {
        callbacks?.onUpdate?.(task);
      });
    }

    const enqueueTask = await this.waitForTaskCompletion(Number(jobId), (task) => {
      callbacks?.onUpdate?.(task);
    });

    let callbackTaskId: number | undefined;
    try {
      const out = enqueueTask.result ? JSON.parse(enqueueTask.result) : null;
      const rawId = out?.callback_task_id ?? out?.callbackTaskId;
      if (typeof rawId === 'number') callbackTaskId = rawId;
      else if (typeof rawId === 'string' && rawId.trim() !== '') callbackTaskId = Number(rawId);
    } catch {
      // ignore parse errors; fall back to returning enqueueTask
    }

    if (!callbackTaskId || !Number.isFinite(callbackTaskId) || callbackTaskId <= 0) {
      return enqueueTask;
    }

    const finalTask = await this.waitForTaskCompletion(callbackTaskId, (task) => {
      callbacks?.onUpdate?.(task);
    });

    return finalTask;
  }

  private static async waitForTaskCompletion(
    jobId: number,
    onUpdate?: (task: Task) => void,
    options?: { timeoutMs?: number }
  ): Promise<Task> {
    return await TaskPoolService.waitForTaskTerminal(jobId, {
      timeoutMs: options?.timeoutMs ?? 10 * 60 * 1000,
      onUpdate: (task) => onUpdate?.(task),
    });
  }

  private static parseTaskOutput(task: Task): {
    success: boolean;
    id?: string;
    error?: string;
    filename?: string;
    relativePath?: string;
    pluginRelativePath?: string;
    archives?: Array<{
      relativePath: string;
      pluginRelativePath: string;
      filename: string;
    }>;
  } {
    const raw = task.result;
    if (!raw) return { success: task.status === 'completed', archives: [] };
    try {
      const obj = JSON.parse(raw);
      const success = isSuccessResponse(obj?.success);

      // 解析 archives 数组
      if (obj?.archives && Array.isArray(obj.archives)) {
        return {
          success,
          archives: obj.archives.map((archive: any) => ({
            relativePath: archive.relative_path,
            pluginRelativePath: archive.plugin_relative_path,
            filename: archive.filename
          }))
        };
      }

      return {
        success,
        id: obj?.id,
        error: obj?.error,
        filename: obj?.filename,
        relativePath: obj?.relative_path,
        pluginRelativePath: obj?.plugin_relative_path,
        archives: []
      };
    } catch {
      return { success: task.status === 'completed', archives: [] };
    }
  }

  /**
   * 批量下载URL
   * @param urls 下载链接数组
   * @param metadata 下载元数据
   * @param callbacks 进度回调
   */
  static async downloadMultipleUrls(
    urls: string[],
    metadata?: DownloadMetadata,
    callbacks?: DownloadProgressCallback
  ): Promise<DownloadResult[]> {
    const results: DownloadResult[] = [];

    for (let i = 0; i < urls.length; i++) {
      const url = urls[i].trim();
      if (!url) continue;

      try {
        const result = await this.downloadFromUrl(url, metadata, {
          onProgress: (progress) => {
            const overallProgress = ((i * 100) + progress) / urls.length;
            callbacks?.onProgress?.(Math.round(overallProgress));
          },
          onComplete: callbacks?.onComplete,
          onError: callbacks?.onError
        });

        results.push(result);
      } catch (error: any) {
        results.push({
          success: false,
          error: error.message || 'Download failed',
          archives: []
        });
      }
    }

    return results;
  }

  /**
   * 模拟下载进度（用于UI测试，实际会调用真实API）
   * @param url 下载链接
   * @param callbacks 进度回调
   */
  static async simulateDownload(
    url: string,
    callbacks?: DownloadProgressCallback
  ): Promise<DownloadResult> {
    try {
      // 模拟下载进度
      for (let i = 0; i <= 100; i += 10) {
        await new Promise(resolve => setTimeout(resolve, 200));
        callbacks?.onProgress?.(i);
      }

      const result: DownloadResult = {
        success: true,
        id: Math.random().toString(36).substr(2, 9),
        archives: [{
          relativePath: `archive/archive_${Date.now()}.zip`,
          pluginRelativePath: `plugins/simulate/archive_${Date.now()}.zip`,
          filename: `archive_${Date.now()}.zip`
        }]
      };

      callbacks?.onComplete?.(result);
      return result;
    } catch (error: any) {
      const errorMessage = error.message || 'Download failed';
      callbacks?.onError?.(errorMessage);

      return {
        success: false,
        error: errorMessage,
        archives: []
      };
    }
  }
}
