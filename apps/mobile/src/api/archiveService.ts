import {apiClient} from './client';
import type {ArchiveMetadata, PageInfo, ArchiveFilesResponse} from '../types/api';

/**
 * 判断 ID 是否为在线源（source: 前缀）。
 */
export function isSourceId(id: string): boolean {
  return id.startsWith('source:');
}

/**
 * 获取条目元数据（统一本地档案/在线源）。
 */
export async function fetchMetadata(id: string, lang?: string): Promise<ArchiveMetadata> {
  const response = await apiClient.get<ArchiveMetadata>(
    `/api/archives/${encodeURIComponent(id)}/metadata`,
    {params: {lang: lang || undefined}},
  );
  return response.data;
}

/**
 * 获取页面列表（统一本地档案/在线源）。
 */
export async function fetchFiles(id: string): Promise<PageInfo[]> {
  const response = await apiClient.get<ArchiveFilesResponse>(
    `/api/archives/${encodeURIComponent(id)}/files`,
    {params: {include_metadata: true}},
  );
  const payload = response.data;
  const pages = Array.isArray(payload)
    ? payload
    : payload.pages || payload.files || payload.data || [];
  return pages.map((page, index) => normalizePageInfo(id, page, index));
}

/**
 * 生成页面资源 URL（统一本地档案/在线源）。
 * 在线源使用 path 作为页面资源 key，本地档案使用 path 作为文件路径。
 */
export function getPageUrl(id: string, path: string): string {
  return `/api/archives/${encodeURIComponent(id)}/page?path=${encodeURIComponent(path)}`;
}

/**
 * 更新阅读进度（统一本地档案/在线源）。
 */
export async function updateProgress(id: string, page: number): Promise<void> {
  await apiClient.put(`/api/archives/${encodeURIComponent(id)}/progress/${page}`);
}

/**
 * 设置收藏状态（统一本地档案/在线源）。
 */
export async function setFavorite(id: string, favorite: boolean): Promise<void> {
  if (favorite) {
    await apiClient.put(`/api/archives/${encodeURIComponent(id)}/favorite`);
  } else {
    await apiClient.delete(`/api/archives/${encodeURIComponent(id)}/favorite`);
  }
}

/**
 * 标记为已读（统一本地档案/在线源）。
 */
export async function markAsRead(id: string): Promise<void> {
  await apiClient.delete(`/api/archives/${encodeURIComponent(id)}/isnew`);
}

/**
 * 标记为未读（统一本地档案/在线源）。
 */
export async function markAsNew(id: string): Promise<void> {
  await apiClient.put(`/api/archives/${encodeURIComponent(id)}/isnew`);
}

/**
 * 删除条目（仅本地档案支持，在线源返回 405）。
 */
export async function deleteArchive(id: string): Promise<void> {
  await apiClient.delete(`/api/archives/${encodeURIComponent(id)}`);
}

/**
 * 获取下载 URL。
 * 本地档案：直接下载链接
 * 在线源：创建 source_download task（后端处理）
 */
export function getDownloadUrl(id: string): string {
  return `/api/archives/${encodeURIComponent(id)}/download`;
}

/**
 * 更新元数据（仅本地档案支持，在线源返回 405）。
 */
export async function updateMetadata(id: string, body: Record<string, unknown>): Promise<void> {
  await apiClient.put(`/api/archives/${encodeURIComponent(id)}/metadata`, body);
}

// ─── 内部工具函数 ────────────────────────────────────────────────────────

function normalizePageInfo(archiveId: string, raw: any, index: number): PageInfo {
  const sources = Array.isArray(raw.sources)
    ? raw.sources.map((source: any) => normalizePageSource(archiveId, source, raw.id))
    : undefined;
  const defaultSource = raw.defaultSource
    ? normalizePageSource(archiveId, raw.defaultSource, raw.id)
    : sources?.[Math.max(0, Math.min((sources?.length || 1) - 1, raw.defaultSourceIndex || 0))];
  const path = raw.path || defaultSource?.path || sources?.[0]?.path || '';
  const type = raw.type || defaultSource?.type || sources?.[0]?.type || 'image';
  return {
    ...raw,
    id: raw.id || path || `page-${index + 1}`,
    path,
    type,
    sources,
    defaultSource,
    defaultSourceIndex: raw.defaultSourceIndex || 0,
  };
}

function normalizePageSource(archiveId: string, raw: any, fallbackId?: string): any {
  const path = raw.path || '';
  const url =
    raw.url ||
    (path
      ? `/api/archives/${encodeURIComponent(archiveId)}/page?path=${encodeURIComponent(path)}`
      : undefined);
  return {
    ...raw,
    id: raw.id || path || fallbackId || '',
    path,
    url,
    type: raw.type || 'image',
  };
}
