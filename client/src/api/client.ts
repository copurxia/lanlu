import axios, {AxiosError, InternalAxiosRequestConfig} from 'axios';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

import {getActiveServer} from '../storage/servers';
import {clearStoredToken, getStoredToken} from '../storage/token';

type UnauthorizedHandler = () => void;
type OfflineHandler = () => void;
type OnlineHandler = () => void;

let onUnauthorized: UnauthorizedHandler | null = null;
let onOffline: OfflineHandler | null = null;
let onOnline: OnlineHandler | null = null;

export function setUnauthorizedHandler(handler: UnauthorizedHandler | null) {
  onUnauthorized = handler;
}

export function setOfflineHandler(handler: OfflineHandler | null) {
  onOffline = handler;
}

export function setOnlineHandler(handler: OnlineHandler | null) {
  onOnline = handler;
}

export const apiClient = axios.create({
  timeout: 15000,
  headers: {'Content-Type': 'application/json'},
});

apiClient.interceptors.request.use(async (config: InternalAxiosRequestConfig) => {
  const server = await getActiveServer();
  if (server) {
    config.baseURL = server.baseUrl;
  }

  const token = await getStoredToken(server?.id);
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

apiClient.interceptors.response.use(
  response => {
    onOnline?.();
    return response;
  },
  async (error: AxiosError) => {
    if (error.response?.status === 401) {
      const server = await getActiveServer();
      await clearStoredToken(server?.id);
      onUnauthorized?.();
    } else if (!error.response) {
      onOffline?.();
    }
    return Promise.reject(error);
  },
);

export function isNetworkError(error: unknown): boolean {
  return axios.isAxiosError(error) && !error.response;
}

export function extractApiError(error: unknown, fallback = 'Request failed') {
  if (axios.isAxiosError(error)) {
    const data = error.response?.data as
      | {message?: string; error?: string}
      | string
      | undefined;
    if (typeof data === 'string' && data.trim()) {
      return data;
    }
    if (data && typeof data === 'object') {
      return data.message || data.error || error.message || fallback;
    }
    return error.message || fallback;
  }

  if (error instanceof Error) {
    return error.message;
  }

  return fallback;
}

export async function buildApiUrl(path: string): Promise<string> {
  if (/^https?:\/\//i.test(path)) {
    return path;
  }
  const server = await getActiveServer();
  if (!server) {
    return path;
  }
  return `${server.baseUrl}${path.startsWith('/') ? path : `/${path}`}`;
}

export async function buildAuthorizedImageSource(path: string) {
  const uri = await buildApiUrl(path);
  const server = await getActiveServer();
  const token = await getStoredToken(server?.id);
  const shouldAttachAuth = !/^https?:\/\//i.test(path) || Boolean(server?.baseUrl && uri.startsWith(server.baseUrl));
  return token && shouldAttachAuth
    ? {uri, headers: {Authorization: `Bearer ${token}`}}
    : {uri};
}

export async function buildAuthorizedAssetImageSource(
  assetId?: number | null,
  options: {
    priority?: FastImageSource['priority'];
  } = {},
): Promise<FastImageSource | null> {
  const id = Math.trunc(Number(assetId || 0));
  if (!Number.isFinite(id) || id <= 0) return null;
  const source = await buildAuthorizedImageSource(`/api/assets/${id}`);
  return {
    ...source,
    cache: FastImage.cacheControl.immutable,
    priority: options.priority || FastImage.priority.normal,
  };
}

export async function buildAuthorizedUri(path: string) {
  const uri = await buildApiUrl(path);
  const server = await getActiveServer();
  const token = await getStoredToken(server?.id);
  const shouldAttachAuth = !/^https?:\/\//i.test(path) || Boolean(server?.baseUrl && uri.startsWith(server.baseUrl));
  return {
    uri,
    token: token || undefined,
    headers: token && shouldAttachAuth ? {Authorization: `Bearer ${token}`} : undefined,
  };
}
