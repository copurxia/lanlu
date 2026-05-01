import {apiClient} from './client';
import type {
  ApiEnvelope,
  Archive,
  ArchiveFilesResponse,
  ArchiveMetadata,
  AuthUser,
  LoginResponse,
  PageInfo,
  PageSourceInfo,
  SearchResponse,
} from '../types/api';
import axios from 'axios';

export type SearchArchivesParams = {
  filter?: string;
  page?: number;
  pageSize?: number;
  sortby?: string;
  order?: 'asc' | 'desc';
  favoriteonly?: boolean;
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
    },
  });
  return response.data;
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
    {params: {images_only: true, include_metadata: true}},
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
