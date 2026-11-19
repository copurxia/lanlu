import axios, {AxiosError, InternalAxiosRequestConfig} from 'axios';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

import {clearSessionCache, getSession} from '../auth/session';
import {clearStoredToken} from '../storage/token';

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
  timeout: 8000,
  headers: {'Content-Type': 'application/json'},
});

apiClient.interceptors.request.use(async (config: InternalAxiosRequestConfig) => {
  const {server, token} = await getSession();
  if (server) {
    config.baseURL = server.baseUrl;
  }

  if (token && server) {
    const url = config.url || '';
    const hasScheme = /^[a-z][a-z\d+.-]*:/i.test(url);
    const relative = !hasScheme && !url.startsWith('//');
    if (
      parseHttpOrigin(server.baseUrl) &&
      (relative || isSameOriginUrl(url, server.baseUrl))
    ) {
      config.headers.Authorization = `Bearer ${token}`;
    }
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
      const {server} = await getSession();
      await clearStoredToken(server?.id);
      clearSessionCache();
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
  const {server} = await getSession();
  if (!server) {
    return path;
  }
  return `${server.baseUrl}${path.startsWith('/') ? path : `/${path}`}`;
}

const HTTP_ORIGIN_PATTERN = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^/?#]*)/;
const HOST_PATTERN = /^[^\s\\/?#@\[\]:%]+$/;

/**
 * Parses an absolute http(s) URL into a normalized origin. React Native
 * replaces the global URL with a regex-based polyfill whose hostname/port
 * getters truncate IPv6 literals, so this deliberately avoids `new URL()`.
 * Userinfo is rejected outright: no Lanlu URL needs it and stripping it is a
 * known parser-differential hazard. Malformed input always fails closed.
 */
export function parseHttpOrigin(value: string): string | null {
  const match = HTTP_ORIGIN_PATTERN.exec(value);
  if (!match) {
    return null;
  }
  const scheme = match[1].toLowerCase();
  if (scheme !== 'http' && scheme !== 'https') {
    return null;
  }

  const authority = match[2];
  if (!authority || authority.includes('@')) {
    return null;
  }

  let host: string;
  let portText = '';
  if (authority.startsWith('[')) {
    const close = authority.indexOf(']');
    if (close < 0) {
      return null;
    }
    const literal = authority.slice(1, close);
    if (!literal.includes(':') || !/^[0-9a-fA-F:.]+$/.test(literal)) {
      return null;
    }
    const remainder = authority.slice(close + 1);
    if (remainder) {
      if (!remainder.startsWith(':')) {
        return null;
      }
      portText = remainder.slice(1);
      if (!portText) {
        return null;
      }
    }
    host = `[${literal.toLowerCase()}]`;
  } else {
    if (authority.includes('[') || authority.includes(']')) {
      return null;
    }
    const colon = authority.indexOf(':');
    if (colon !== -1 && colon !== authority.lastIndexOf(':')) {
      return null;
    }
    host = colon === -1 ? authority : authority.slice(0, colon);
    if (colon !== -1) {
      portText = authority.slice(colon + 1);
      if (!portText) {
        return null;
      }
    }
    if (!HOST_PATTERN.test(host)) {
      return null;
    }
    host = host.toLowerCase();
  }

  let port = '';
  if (portText) {
    if (!/^[0-9]+$/.test(portText)) {
      return null;
    }
    const numeric = Number(portText);
    if (!Number.isInteger(numeric) || numeric > 65535) {
      return null;
    }
    port = String(numeric);
    if (
      (scheme === 'https' && numeric === 443) ||
      (scheme === 'http' && numeric === 80)
    ) {
      port = '';
    }
  }

  return `${scheme}://${host}${port ? `:${port}` : ''}`;
}

/** `//host/path` inherits the base scheme, exactly as axios resolves it. */
export function isSameOriginUrl(url: string, baseUrl: string): boolean {
  const base = parseHttpOrigin(baseUrl);
  if (!base) {
    return false;
  }
  const candidate = url.startsWith('//')
    ? `${base.slice(0, base.indexOf(':'))}:${url}`
    : url;
  return parseHttpOrigin(candidate) === base;
}

export async function buildAuthorizedImageSource(path: string) {
  const {server, token} = await getSession();
  const absolute = /^https?:\/\//i.test(path);
  const protocolRelative = path.startsWith('//');
  const uri = absolute
    ? path
    : server
      ? `${server.baseUrl}${path.startsWith('/') ? path : `/${path}`}`
      : path;
  const shouldAttachAuth =
    server !== null &&
    isSameOriginUrl(protocolRelative ? path : uri, server.baseUrl);
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
  const {server, token} = await getSession();
  const absolute = /^https?:\/\//i.test(path);
  const protocolRelative = path.startsWith('//');
  const uri = absolute
    ? path
    : server
      ? `${server.baseUrl}${path.startsWith('/') ? path : `/${path}`}`
      : path;
  const shouldAttachAuth =
    server !== null &&
    isSameOriginUrl(protocolRelative ? path : uri, server.baseUrl);
  return {
    uri,
    token: token && shouldAttachAuth ? token : undefined,
    headers: token && shouldAttachAuth ? {Authorization: `Bearer ${token}`} : undefined,
  };
}
