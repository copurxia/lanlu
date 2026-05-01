import {apiClient} from './client';
import type {
  ApiEnvelope,
  Archive,
  ArchiveFilesResponse,
  ArchiveMetadata,
  AuthUser,
  Category,
  LoginResponse,
  MediaItem,
  PageInfo,
  PageSourceInfo,
  SearchResponse,
  Tankoubon,
} from '../types/api';
import axios from 'axios';

let recommendationSessionKey: string | null = null;

export type SearchArchivesParams = {
  filter?: string;
  page?: number;
  pageSize?: number;
  sortby?: string;
  order?: 'asc' | 'desc';
  favoriteonly?: boolean;
  favorite_tankoubons_only?: boolean;
  newonly?: boolean;
  untaggedonly?: boolean;
  groupby_tanks?: boolean;
  category_id?: string;
  category_ids?: string;
  aggregate_by?: string;
  lang?: string;
};

export async function login(params: {
  username: string;
  password: string;
  tokenName?: string;
}): Promise<LoginResponse> {
  const response = await apiClient.post<LoginResponse>('/api/auth/login', {
    username: params.username,
    password: params.password,
    tokenName: params.tokenName || 'Lanlu Mobile',
  });
  return response.data;
}

export async function fetchMe(): Promise<AuthUser> {
  const response = await apiClient.get<ApiEnvelope<{user: AuthUser}>>(
    '/api/auth/me',
  );
  if (!response.data.data?.user) {
    throw new Error(response.data.message || 'Missing current user');
  }
  return response.data.data.user;
}

export async function logout(): Promise<void> {
  await apiClient.post('/api/auth/logout', {});
}

export async function testServer(baseUrl: string): Promise<void> {
  await axios.get(`${baseUrl.replace(/\/+$/, '')}/api/info`, {timeout: 10000});
}

export async function searchArchives(
  params: SearchArchivesParams,
): Promise<SearchResponse> {
  const response = await apiClient.get<SearchResponse>('/api/search', {
    params: {
      page: params.page || 1,
      pageSize: params.pageSize || 24,
      filter: params.filter || undefined,
      sortby: params.sortby || 'created_at',
      order: params.order || 'desc',
      favoriteonly: params.favoriteonly || undefined,
      favorite_tankoubons_only: params.favorite_tankoubons_only || undefined,
      newonly: params.newonly || undefined,
      untaggedonly: params.untaggedonly || undefined,
      groupby_tanks: params.groupby_tanks,
      category_id: params.category_id || undefined,
      category_ids: params.category_ids || undefined,
      aggregate_by: params.aggregate_by || undefined,
      lang: params.lang || undefined,
    },
  });
  const payload = response.data;
  return {
    ...payload,
    data: Array.isArray(payload.data) ? payload.data.map(normalizeMediaItem) : [],
    groups: Array.isArray(payload.groups)
      ? payload.groups.map(group => ({
          ...group,
          category_id: String(group.category_id || '').trim(),
          data: Array.isArray(group.data)
            ? group.data.map(normalizeMediaItem)
            : [],
        }))
      : undefined,
  };
}

export async function fetchCategories(): Promise<Category[]> {
  const response = await apiClient.get<{
    success?: number;
    data?: Category | Category[];
  }>('/api/categories');
  const data = response.data?.data;
  return (Array.isArray(data) ? data : data ? [data] : [])
    .map(category => ({
      ...category,
      catid: String(category.catid || category.id || '').trim(),
      name: String(category.name || '').trim(),
      enabled: category.enabled !== false,
      sort_order: Number(category.sort_order || 0),
    }))
    .sort((a, b) => {
      if ((a.sort_order || 0) !== (b.sort_order || 0)) {
        return (a.sort_order || 0) - (b.sort_order || 0);
      }
      return a.name.localeCompare(b.name);
    });
}

export async function fetchDiscover(count = 12): Promise<MediaItem[]> {
  const response = await apiClient.get<MediaItem[] | {data?: MediaItem[]}>(
    '/api/recommendations',
    {
      params: {scene: 'discover', count},
      headers: {'X-Recommendation-Session': getRecommendationSessionKey()},
    },
  );
  const data = Array.isArray(response.data) ? response.data : response.data.data || [];
  return data.map(normalizeMediaItem);
}

function getRecommendationSessionKey(): string {
  if (!recommendationSessionKey) {
    recommendationSessionKey = `mobile-${Date.now()}-${Math.random()
      .toString(36)
      .slice(2)}`;
  }
  return recommendationSessionKey;
}

export async function fetchFavoriteTankoubons(): Promise<Tankoubon[]> {
  const result = await searchArchives({
    favorite_tankoubons_only: true,
    groupby_tanks: true,
    page: 1,
    pageSize: 1000,
  });
  return result.data.filter(isTankoubon);
}

export async function fetchArchiveMetadata(id: string): Promise<ArchiveMetadata> {
  const response = await apiClient.get<ArchiveMetadata>(
    `/api/archives/${encodeURIComponent(id)}/metadata`,
  );
  return response.data;
}

export async function fetchArchiveFiles(id: string): Promise<PageInfo[]> {
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

export async function setArchiveFavorite(
  archive: Archive | ArchiveMetadata,
  favorite: boolean,
): Promise<void> {
  const id = archive.arcid;
  if (favorite) {
    await apiClient.put(`/api/archives/${encodeURIComponent(id)}/favorite`);
  } else {
    await apiClient.delete(`/api/archives/${encodeURIComponent(id)}/favorite`);
  }
}

export async function updateArchiveProgress(
  archiveId: string,
  page: number,
): Promise<void> {
  await apiClient.put(
    `/api/archives/${encodeURIComponent(archiveId)}/progress/${page}`,
  );
}

export function assetPath(assetId?: number | null): string | null {
  return assetId && assetId > 0 ? `/api/assets/${assetId}` : null;
}

export function pagePath(archiveId: string, page: PageInfo): string {
  const source = getPageDefaultSource(page);
  if (source?.url?.startsWith('/api/')) {
    return source.url;
  }
  const path = source?.path || page.path || '';
  return `/api/archives/${encodeURIComponent(archiveId)}/page?path=${encodeURIComponent(
    path,
  )}`;
}

export function getPageDefaultSource(page: PageInfo): PageSourceInfo | null {
  if (page.defaultSource) {
    return page.defaultSource;
  }
  const sources = Array.isArray(page.sources) ? page.sources : [];
  if (!sources.length) {
    return page.path
      ? {
          id: page.id || page.path,
          path: page.path,
          type: page.type || 'image',
          title: page.title,
        }
      : null;
  }
  const index = Math.max(0, Math.min(sources.length - 1, page.defaultSourceIndex || 0));
  return sources[index];
}

function normalizePageInfo(archiveId: string, raw: PageInfo, index: number): PageInfo {
  const sources = Array.isArray(raw.sources)
    ? raw.sources.map(source => normalizePageSource(archiveId, source, raw.id))
    : undefined;
  const defaultSource = raw.defaultSource
    ? normalizePageSource(archiveId, raw.defaultSource, raw.id)
    : sources?.[Math.max(0, Math.min(sources.length - 1, raw.defaultSourceIndex || 0))];
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

function normalizePageSource(
  archiveId: string,
  raw: PageSourceInfo,
  fallbackId?: string,
): PageSourceInfo {
  const path = raw.path || '';
  const url =
    raw.url ||
    (path
      ? `/api/archives/${encodeURIComponent(archiveId)}/page?path=${encodeURIComponent(
          path,
        )}`
      : undefined);
  return {
    ...raw,
    id: raw.id || path || fallbackId || '',
    path,
    url,
    type: raw.type || 'image',
  };
}

export function isTankoubon(item: MediaItem): item is Tankoubon {
  return Boolean((item as Tankoubon).tankoubon_id);
}

export function mediaItemId(item: MediaItem): string {
  return isTankoubon(item) ? item.tankoubon_id : item.arcid;
}

export function mediaItemTitle(item: MediaItem): string {
  return item.title || (isTankoubon(item) ? item.tankoubon_id : item.filename || item.arcid);
}

export function mediaItemCoverAsset(item: MediaItem): number | undefined {
  return item.assets?.cover || item.assets?.clearlogo || item.assets?.backdrop;
}

function normalizeMediaItem(raw: MediaItem): MediaItem {
  if (isTankoubon(raw)) {
    return {
      ...raw,
      title: String(raw.title || '').trim(),
      description: String(raw.description || '').trim(),
      children: Array.isArray(raw.children)
        ? raw.children.map(child => String(child || '').trim()).filter(Boolean)
        : [],
    };
  }
  return {
    ...raw,
    title: String(raw.title || '').trim(),
    description: String(raw.description || '').trim(),
  };
}
