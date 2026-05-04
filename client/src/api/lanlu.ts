import {apiClient} from './client';
import type {
  ApiEnvelope,
  Archive,
  ArchiveFilesResponse,
  ArchiveMetadata,
  AuthSession,
  AuthToken,
  AuthTokenFull,
  AuthUser,
  Category,
  LoginResponse,
  MediaItem,
  PageInfo,
  PageSourceInfo,
  PasskeyCredential,
  SearchResponse,
  StepUpOptions,
  Tankoubon,
  TankoubonMetadata,
  TotpEnrollmentPayload,
  TotpStatus,
} from '../types/api';
import axios from 'axios';
import {appendDiagnosticLog} from '../storage/diagnostics';

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
  tankoubon_id?: string;
  category_id?: string;
  category_ids?: string;
  aggregate_by?: string;
  lang?: string;
  date_from?: string;
  date_to?: string;
};

export type TagSuggestion = {
  value: string;
  label: string;
  display: string;
};

export type SmartFilter = {
  id: number;
  name: string;
  translations?: Record<string, {text?: string; intro?: string}>;
  icon?: string;
  query?: string;
  sort_by?: string;
  sort_order?: 'asc' | 'desc' | string;
  date_from?: string;
  date_to?: string;
  newonly?: boolean;
  untaggedonly?: boolean;
  enabled?: boolean;
  sort_order_num?: number;
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
  const requestParams = {
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
    tankoubon_id: params.tankoubon_id || undefined,
    aggregate_by: params.aggregate_by || undefined,
    lang: params.lang || undefined,
    date_from: params.date_from || undefined,
    date_to: params.date_to || undefined,
  };
  const startedAt = Date.now();
  await appendDiagnosticLog('search.request', {params: requestParams});
  try {
    const response = await apiClient.get<SearchResponse>('/api/search', {
      params: requestParams,
    });
    const payload = response.data;
    const normalized = {
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
    await appendDiagnosticLog('search.response', {
      durationMs: Date.now() - startedAt,
      status: response.status,
      params: requestParams,
      dataCount: normalized.data.length,
      groupCount: normalized.groups?.length || 0,
      recordsFiltered: normalized.recordsFiltered,
      recordsTotal: normalized.recordsTotal,
      firstIds: normalized.data.slice(0, 5).map(mediaItemId),
    });
    return normalized;
  } catch (error) {
    await appendDiagnosticLog('search.error', {
      durationMs: Date.now() - startedAt,
      params: requestParams,
      status: axios.isAxiosError(error) ? error.response?.status : undefined,
      message: error instanceof Error ? error.message : String(error),
      response: axios.isAxiosError(error) ? error.response?.data : undefined,
    });
    throw error;
  }
}

export async function fetchTagAutocomplete(
  query: string,
  lang: string,
  limit = 10,
): Promise<TagSuggestion[]> {
  const q = query.trim();
  if (!q) return [];
  const response = await apiClient.get<{
    data?: {suggestions?: TagSuggestion[]};
  }>('/api/tags/autocomplete', {
    params: {q, lang, limit, require_bound: 1},
  });
  return Array.isArray(response.data?.data?.suggestions)
    ? response.data.data.suggestions
    : [];
}

export async function fetchSmartFilters(): Promise<SmartFilter[]> {
  const response = await apiClient.get<{
    data?: {items?: SmartFilter[]};
  }>('/api/smart_filters');
  const items = response.data?.data?.items;
  return Array.isArray(items) ? items.filter(item => item.enabled !== false) : [];
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

export async function fetchArchiveRelated(
  archiveId: string,
  count = 8,
): Promise<Archive[]> {
  const response = await apiClient.get<{data?: MediaItem[]}>(
    '/api/recommendations',
    {
      params: {
        scene: 'archive_related',
        archive_id: archiveId,
        count,
      },
      headers: {'X-Recommendation-Session': getRecommendationSessionKey()},
    },
  );
  const data = Array.isArray(response.data?.data) ? response.data.data : [];
  return data.map(normalizeMediaItem).filter((item): item is Archive => !isTankoubon(item));
}

export async function fetchTankoubonsForArchive(archiveId: string): Promise<Tankoubon[]> {
  const response = await apiClient.get<Tankoubon[] | {data?: Tankoubon[]}>(
    `/api/archives/${encodeURIComponent(archiveId)}/tankoubons`,
  );
  const data = Array.isArray(response.data) ? response.data : response.data.data || [];
  return data.map(item => normalizeMediaItem(item) as Tankoubon).filter(isTankoubon);
}

export async function fetchTankoubonMetadata(id: string, lang?: string): Promise<TankoubonMetadata> {
  const response = await apiClient.get<TankoubonMetadata>(
    `/api/tankoubons/${encodeURIComponent(id)}/metadata`,
    {params: {lang: lang || undefined}},
  );
  return response.data;
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

export async function fetchArchiveMetadata(id: string, lang?: string): Promise<ArchiveMetadata> {
  const response = await apiClient.get<ArchiveMetadata>(
    `/api/archives/${encodeURIComponent(id)}/metadata`,
    {params: {lang: lang || undefined}},
  );
  return response.data;
}

export async function setTankoubonFavorite(
  tankoubonId: string,
  favorite: boolean,
): Promise<void> {
  if (favorite) {
    await apiClient.put(`/api/tankoubons/${encodeURIComponent(tankoubonId)}/favorite`);
  } else {
    await apiClient.delete(`/api/tankoubons/${encodeURIComponent(tankoubonId)}/favorite`);
  }
}

export async function markArchiveAsRead(archiveId: string): Promise<void> {
  await apiClient.delete(`/api/archives/${encodeURIComponent(archiveId)}/isnew`);
}

export async function markArchiveAsNew(archiveId: string): Promise<void> {
  await apiClient.put(`/api/archives/${encodeURIComponent(archiveId)}/isnew`);
}

export async function deleteArchive(archiveId: string): Promise<void> {
  await apiClient.delete(`/api/archives/${encodeURIComponent(archiveId)}`);
}

export async function deleteTankoubon(tankoubonId: string): Promise<void> {
  await apiClient.delete(`/api/tankoubons/${encodeURIComponent(tankoubonId)}`);
}

export async function addArchiveToTankoubon(
  tankoubonId: string,
  archiveId: string,
): Promise<void> {
  await apiClient.post(
    `/api/tankoubons/${encodeURIComponent(tankoubonId)}/archives`,
    {archive_id: archiveId},
  );
}

export async function removeArchiveFromTankoubon(
  tankoubonId: string,
  archiveId: string,
): Promise<void> {
  await apiClient.delete(
    `/api/tankoubons/${encodeURIComponent(tankoubonId)}/archives/${encodeURIComponent(archiveId)}`,
  );
}

export async function fetchTankoubonRelated(
  tankoubonId: string,
  count = 8,
): Promise<Tankoubon[]> {
  const response = await apiClient.get<{data?: MediaItem[]}>(
    '/api/recommendations',
    {
      params: {
        scene: 'tankoubon_related',
        tankoubon_id: tankoubonId,
        count,
      },
      headers: {'X-Recommendation-Session': getRecommendationSessionKey()},
    },
  );
  const data = Array.isArray(response.data?.data) ? response.data.data : [];
  return data
    .map(normalizeMediaItem)
    .filter((item): item is Tankoubon => isTankoubon(item));
}

export function getArchiveDownloadUrl(archiveId: string): string {
  return `/api/archives/${encodeURIComponent(archiveId)}/download`;
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

function responseBodyPreview(data: unknown): string | undefined {
  if (typeof data === 'string') {
    return data.slice(0, 300);
  }
  if (data instanceof ArrayBuffer) {
    const bytes = new Uint8Array(data).slice(0, 300);
    return Array.from(bytes)
      .map(byte => (byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.'))
      .join('');
  }
  if (data && typeof data === 'object' && 'byteLength' in data) {
    const bytes = new Uint8Array(data as ArrayBufferLike).slice(0, 300);
    return Array.from(bytes)
      .map(byte => (byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.'))
      .join('');
  }
  if (data === undefined || data === null) {
    return undefined;
  }
  try {
    return JSON.stringify(data).slice(0, 300);
  } catch {
    return String(data).slice(0, 300);
  }
}

export async function probeMediaPage(pathOrUrl: string, range = 'bytes=0-0') {
  const response = await apiClient.get(pathOrUrl, {
    headers: {Range: range},
    responseType: 'arraybuffer',
    timeout: 10000,
    validateStatus: status => status >= 200 && status < 600,
  });
  const headers = response.headers || {};
  return {
    status: response.status,
    requestedRange: range,
    contentType: headers['content-type'],
    contentLength: headers['content-length'],
    contentRange: headers['content-range'],
    acceptRanges: headers['accept-ranges'],
    bodyPreview: responseBodyPreview(response.data),
  };
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
  return (
    readAssetId(item.assets, 'cover') ||
    readAssetId(item.assets, 'clearlogo') ||
    readAssetId(item.assets, 'backdrop')
  );
}

export function archiveCoverAsset(item?: {assets?: unknown} | null): number | undefined {
  if (!item) return undefined;
  return (
    readAssetId(item.assets, 'cover') ||
    readAssetId(item.assets, 'clearlogo') ||
    readAssetId(item.assets, 'backdrop')
  );
}

function normalizeMediaItem(raw: MediaItem): MediaItem {
  if (isTankoubon(raw)) {
    return {
      ...raw,
      assets: normalizeAssets(raw.assets),
      title: String(raw.title || '').trim(),
      description: String(raw.description || '').trim(),
      children: Array.isArray(raw.children)
        ? raw.children.map(child => String(child || '').trim()).filter(Boolean)
        : [],
    };
  }
  return {
    ...raw,
    assets: normalizeAssets(raw.assets),
    title: String(raw.title || '').trim(),
    description: String(raw.description || '').trim(),
  };
}

function toPositiveAssetId(value: unknown): number | undefined {
  if (value === null || value === undefined) return undefined;
  const id = Math.trunc(typeof value === 'number' ? value : Number(value));
  return Number.isFinite(id) && id > 0 ? id : undefined;
}

function normalizeAssetValue(value: unknown): number | undefined {
  const direct = toPositiveAssetId(value);
  if (direct !== undefined) return direct;
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const row = value as Record<string, unknown>;
    for (const key of ['value', 'path', 'id', 'asset_id', 'assetId']) {
      const nested = normalizeAssetValue(row[key]);
      if (nested !== undefined) return nested;
    }
  }
  return undefined;
}

function readAssetId(rawAssets: unknown, wantedKey: string): number | undefined {
  const wanted = wantedKey.trim().toLowerCase();
  if (!wanted) return undefined;

  if (Array.isArray(rawAssets)) {
    for (const item of rawAssets) {
      if (!item || typeof item !== 'object' || Array.isArray(item)) continue;
      const row = item as Record<string, unknown>;
      const itemKey = String(row.key ?? row.slot ?? row.type ?? row.name ?? '').trim().toLowerCase();
      if (itemKey !== wanted) continue;
      const value = normalizeAssetValue(row.value ?? row.path ?? row.id ?? row.asset_id ?? row.assetId);
      if (value !== undefined) return value;
    }
    return undefined;
  }

  if (rawAssets && typeof rawAssets === 'object') {
    const assets = rawAssets as Record<string, unknown>;
    const direct = normalizeAssetValue(assets[wanted]);
    if (direct !== undefined) return direct;
    for (const [key, value] of Object.entries(assets)) {
      if (key.trim().toLowerCase() !== wanted) continue;
      const id = normalizeAssetValue(value);
      if (id !== undefined) return id;
    }
  }
  return undefined;
}

function normalizeAssets(rawAssets: unknown): Record<string, number> | undefined {
  const out: Record<string, number> = {};
  for (const key of ['cover', 'clearlogo', 'backdrop']) {
    const id = readAssetId(rawAssets, key);
    if (id !== undefined) out[key] = id;
  }
  return Object.keys(out).length ? out : undefined;
}

// ─── Auth Security API ────────────────────────────────────────────────────

export async function listTokens(): Promise<ApiEnvelope<{tokens: AuthToken[]}>> {
  const response = await apiClient.get<ApiEnvelope<{tokens: AuthToken[]}>>('/api/auth/tokens');
  return response.data;
}

export async function createToken(name: string): Promise<ApiEnvelope<{token: AuthTokenFull}>> {
  const response = await apiClient.post<ApiEnvelope<{token: AuthTokenFull}>>('/api/auth/tokens', {name});
  return response.data;
}

export async function revokeToken(id: number): Promise<void> {
  await apiClient.delete(`/api/auth/tokens/${id}`);
}

export async function listSessions(): Promise<ApiEnvelope<{sessions: AuthSession[]}>> {
  const response = await apiClient.get<ApiEnvelope<{sessions: AuthSession[]}>>('/api/auth/sessions');
  return response.data;
}

export async function revokeSession(id: number): Promise<void> {
  await apiClient.delete(`/api/auth/sessions/${id}`);
}

export async function revokeOtherSessions(): Promise<void> {
  await apiClient.post('/api/auth/sessions/revoke-others', {});
}

export async function changeUsername(newUsername: string): Promise<ApiEnvelope<{user: AuthUser}>> {
  const response = await apiClient.post<ApiEnvelope<{user: AuthUser}>>('/api/auth/username', {newUsername});
  return response.data;
}

export async function changePassword(newPassword: string): Promise<void> {
  await apiClient.post('/api/auth/password', {newPassword});
}

export async function getTotpStatus(): Promise<ApiEnvelope<TotpStatus>> {
  const response = await apiClient.get<ApiEnvelope<TotpStatus>>('/api/auth/totp/status');
  return response.data;
}

export async function startTotpEnrollment(name?: string): Promise<ApiEnvelope<TotpEnrollmentPayload>> {
  const response = await apiClient.post<ApiEnvelope<TotpEnrollmentPayload>>(
    '/api/auth/totp/enroll/start',
    {name: name?.trim() || ''},
  );
  return response.data;
}

export async function confirmTotpEnrollment(params: {
  challengeId: string;
  code: string;
  name?: string;
}): Promise<ApiEnvelope<{recoveryCodes: string[]}>> {
  const response = await apiClient.post<ApiEnvelope<{recoveryCodes: string[]}>>(
    '/api/auth/totp/enroll/confirm',
    {
      challengeId: params.challengeId,
      code: params.code,
      name: params.name?.trim() || '',
    },
  );
  return response.data;
}

export async function regenerateRecoveryCodes(code: string): Promise<ApiEnvelope<{recoveryCodes: string[]}>> {
  const response = await apiClient.post<ApiEnvelope<{recoveryCodes: string[]}>>(
    '/api/auth/totp/recovery-codes/regenerate',
    {code},
  );
  return response.data;
}

export async function disableTotp(): Promise<void> {
  await apiClient.delete('/api/auth/totp');
}

export async function listPasskeyCredentials(): Promise<ApiEnvelope<{credentials: PasskeyCredential[]}>> {
  const response = await apiClient.get<ApiEnvelope<{credentials: PasskeyCredential[]}>>(
    '/api/auth/webauthn/credentials',
  );
  return response.data;
}

export async function revokePasskeyCredential(id: number): Promise<void> {
  await apiClient.delete(`/api/auth/webauthn/credentials/${id}`, {data: {}});
}

export async function getStepUpOptions(): Promise<ApiEnvelope<StepUpOptions>> {
  const response = await apiClient.get<ApiEnvelope<StepUpOptions>>('/api/auth/step-up/options');
  return response.data;
}

export async function verifyStepUpPassword(password: string): Promise<void> {
  await apiClient.post('/api/auth/step-up/password', {password});
}

export async function verifyStepUpTotp(params: {code?: string; recoveryCode?: string}): Promise<void> {
  await apiClient.post('/api/auth/step-up/totp', {
    code: params.code || '',
    recoveryCode: params.recoveryCode || '',
  });
}

// WebAuthn registration via passkey native module
export async function getWebauthnRegisterOptions(): Promise<ApiEnvelope<{
  challengeId: string;
  publicKey: Record<string, unknown>;
}>> {
  const response = await apiClient.post<ApiEnvelope<{
    challengeId: string;
    publicKey: Record<string, unknown>;
  }>>('/api/auth/webauthn/register/options', {});
  return response.data;
}

export async function verifyWebauthnRegistration(params: {
  challengeId: string;
  name: string;
  credential: Record<string, unknown>;
}): Promise<void> {
  await apiClient.post('/api/auth/webauthn/register/verify', {
    challengeId: params.challengeId,
    name: params.name,
    credential: params.credential,
  });
}

// WebAuthn step-up via passkey native module
export async function getWebauthnStepUpOptions(): Promise<ApiEnvelope<{
  challengeId: string;
  publicKey: Record<string, unknown>;
}>> {
  const response = await apiClient.post<ApiEnvelope<{
    challengeId: string;
    publicKey: Record<string, unknown>;
  }>>('/api/auth/step-up/webauthn/options', {});
  return response.data;
}

export async function verifyWebauthnStepUp(params: {
  challengeId: string;
  credential: Record<string, unknown>;
}): Promise<void> {
  await apiClient.post('/api/auth/step-up/webauthn/verify', {
    challengeId: params.challengeId,
    credential: params.credential,
  });
}

// ─── User Stats ────────────────────────────────────────────────────────────

export type UserStats = {
  favoriteCount: number;
  readCount: number;
  totalPagesRead: number;
  totalArchives: number;
};

export type ReadingTrendItem = {
  date: string;
  count: number;
};

export async function fetchUserStats(): Promise<UserStats> {
  try {
    const response = await apiClient.get<ApiEnvelope<UserStats>>('/api/user/stats');
    const data = response.data?.data;
    if (data) {
      return {
        favoriteCount: Number(data.favoriteCount) || 0,
        readCount: Number(data.readCount) || 0,
        totalPagesRead: Number(data.totalPagesRead) || 0,
        totalArchives: Number(data.totalArchives) || 0,
      };
    }
  } catch {
    // silent
  }
  return {favoriteCount: 0, readCount: 0, totalPagesRead: 0, totalArchives: 0};
}

export async function fetchReadingTrend(days = 30): Promise<ReadingTrendItem[]> {
  try {
    const safeDays = Math.max(1, Math.min(365, Math.trunc(days)));
    const response = await apiClient.get<ApiEnvelope<ReadingTrendItem[]>>('/api/user/trend', {
      params: {days: safeDays},
    });
    if (Array.isArray(response.data?.data)) {
      return response.data.data.map(item => ({
        date: String(item.date || ''),
        count: Number(item.count) || 0,
      }));
    }
  } catch {
    // silent
  }
  return [];
}
