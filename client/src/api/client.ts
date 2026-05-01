import axios, {AxiosError, InternalAxiosRequestConfig} from 'axios';

import {getActiveServer} from '../storage/servers';
import {clearStoredToken, getStoredToken} from '../storage/token';

type UnauthorizedHandler = () => void;

let onUnauthorized: UnauthorizedHandler | null = null;

export function setUnauthorizedHandler(handler: UnauthorizedHandler | null) {
  onUnauthorized = handler;
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
  response => response,
  async (error: AxiosError) => {
    if (error.response?.status === 401) {
      const server = await getActiveServer();
      await clearStoredToken(server?.id);
      onUnauthorized?.();
    }
    return Promise.reject(error);
  },
);

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
  return token
    ? {uri, headers: {Authorization: `Bearer ${token}`}}
    : {uri};
}

export async function buildAuthorizedUri(path: string) {
  const uri = await buildApiUrl(path);
  const server = await getActiveServer();
  const token = await getStoredToken(server?.id);
  return {
    uri,
    token: token || undefined,
    headers: token ? {Authorization: `Bearer ${token}`} : undefined,
  };
}
