import { AxiosError, AxiosHeaders } from 'axios';

import { clearSessionCache, getSession } from '../auth/session';
import { clearStoredToken } from '../storage/token';
import {
  apiClient,
  buildApiUrl,
  buildAuthorizedAssetImageSource,
  buildAuthorizedImageSource,
  buildAuthorizedUri,
  extractApiError,
  isNetworkError,
  setOfflineHandler,
  setOnlineHandler,
  setUnauthorizedHandler,
} from './client';

jest.mock('../auth/session', () => ({
  getSession: jest.fn(),
  clearSessionCache: jest.fn(),
}));

jest.mock('../storage/token', () => ({
  clearStoredToken: jest.fn(),
}));

const mockedGetSession = getSession as jest.MockedFunction<typeof getSession>;
const mockedClearSessionCache = clearSessionCache as jest.MockedFunction<
  typeof clearSessionCache
>;
const mockedClearStoredToken = clearStoredToken as jest.MockedFunction<
  typeof clearStoredToken
>;

const requestHandler = (apiClient.interceptors.request as any).handlers[0]
  .fulfilled as (config: any) => Promise<any>;
const responseSuccess = (apiClient.interceptors.response as any).handlers[0]
  .fulfilled as (response: any) => any;
const responseError = (apiClient.interceptors.response as any).handlers[0]
  .rejected as (error: unknown) => Promise<never>;

const server = { id: 's1', baseUrl: 'https://lanlu.example' } as any;

function requestConfig() {
  return { headers: new AxiosHeaders() } as any;
}

function axiosError(options: {
  status?: number;
  data?: unknown;
  message?: string;
}) {
  const config = requestConfig();
  const response =
    options.status === undefined
      ? undefined
      : {
          status: options.status,
          statusText: '',
          data: options.data,
          headers: {},
          config,
        };
  return new AxiosError(
    options.message || 'Request failed',
    'ERR_BAD_REQUEST',
    config,
    undefined,
    response as any,
  );
}

describe('api client request interceptor', () => {
  beforeEach(() => {
    mockedGetSession.mockReset();
    mockedClearSessionCache.mockReset();
    mockedClearStoredToken.mockReset();
    mockedClearStoredToken.mockResolvedValue(undefined);
    mockedGetSession.mockResolvedValue({ server, token: 'token-1' });
  });

  afterEach(() => {
    setUnauthorizedHandler(null);
    setOfflineHandler(null);
    setOnlineHandler(null);
  });

  it('applies the active server base url and bearer token', async () => {
    const config = await requestHandler(requestConfig());

    expect(config.baseURL).toBe('https://lanlu.example');
    expect(config.headers.Authorization).toBe('Bearer token-1');
  });

  it('leaves the request untouched when there is no session', async () => {
    mockedGetSession.mockResolvedValue({ server: null, token: null });
    const config = requestConfig();

    const result = await requestHandler(config);

    expect(result.baseURL).toBeUndefined();
    expect(result.headers.Authorization).toBeUndefined();
  });

  it('runs through the real axios pipeline without network access', async () => {
    const originalAdapter = apiClient.defaults.adapter;
    const adapter = jest.fn(async config => ({
      data: { ok: true },
      status: 200,
      statusText: 'OK',
      headers: {},
      config,
    }));
    apiClient.defaults.adapter = adapter as any;
    const online = jest.fn();
    setOnlineHandler(online);

    try {
      const response = await apiClient.get('/api/ping', {
        headers: { 'X-Test': '1' },
      });

      expect(response.data).toEqual({ ok: true });
      const sent = adapter.mock.calls[0][0] as any;
      expect(sent.baseURL).toBe('https://lanlu.example');
      expect(sent.headers.Authorization).toBe('Bearer token-1');
      expect(sent.headers['X-Test']).toBe('1');
      expect(online).toHaveBeenCalledTimes(1);
    } finally {
      apiClient.defaults.adapter = originalAdapter;
    }
  });

  it('calls the online handler on every successful response', () => {
    const online = jest.fn();
    setOnlineHandler(online);

    const response = { data: {} } as any;

    expect(responseSuccess(response)).toBe(response);
    expect(online).toHaveBeenCalledTimes(1);
  });

  it('clears the stored token, session cache and notifies on 401', async () => {
    const unauthorized = jest.fn();
    setUnauthorizedHandler(unauthorized);
    const error = axiosError({ status: 401, data: { message: 'expired' } });

    await expect(responseError(error)).rejects.toBe(error);

    expect(mockedClearStoredToken).toHaveBeenCalledWith('s1');
    expect(mockedClearSessionCache).toHaveBeenCalledTimes(1);
    expect(unauthorized).toHaveBeenCalledTimes(1);
  });

  it('treats a missing response as offline', async () => {
    const offline = jest.fn();
    const unauthorized = jest.fn();
    setOfflineHandler(offline);
    setUnauthorizedHandler(unauthorized);
    const error = axiosError({ message: 'Network Error' });

    await expect(responseError(error)).rejects.toBe(error);

    expect(offline).toHaveBeenCalledTimes(1);
    expect(unauthorized).not.toHaveBeenCalled();
    expect(mockedClearStoredToken).not.toHaveBeenCalled();
  });

  it('does not toggle connectivity for ordinary server errors', async () => {
    const offline = jest.fn();
    const unauthorized = jest.fn();
    setOfflineHandler(offline);
    setUnauthorizedHandler(unauthorized);
    const error = axiosError({ status: 500, data: { message: 'boom' } });

    await expect(responseError(error)).rejects.toBe(error);

    expect(offline).not.toHaveBeenCalled();
    expect(unauthorized).not.toHaveBeenCalled();
  });
});

describe('api error helpers', () => {
  it('detects network errors', () => {
    expect(isNetworkError(axiosError({ message: 'Network Error' }))).toBe(true);
    expect(isNetworkError(axiosError({ status: 500 }))).toBe(false);
    expect(isNetworkError(new Error('plain'))).toBe(false);
    expect(isNetworkError(null)).toBe(false);
  });

  it('extracts messages from the common response shapes', () => {
    expect(extractApiError(axiosError({ status: 400, data: 'plain text' }))).toBe(
      'plain text',
    );
    expect(
      extractApiError(axiosError({ status: 400, data: { message: 'by message' } })),
    ).toBe('by message');
    expect(
      extractApiError(axiosError({ status: 400, data: { error: 'by error' } })),
    ).toBe('by error');
    expect(extractApiError(new Error('thrown'))).toBe('thrown');
    expect(extractApiError({}, 'fallback')).toBe('fallback');
  });

  it('falls back to the axios message for blank bodies', () => {
    expect(
      extractApiError(axiosError({ status: 400, data: '   ', message: 'bad request' })),
    ).toBe('bad request');
  });
});

describe('authorized url builders', () => {
  beforeEach(() => {
    mockedGetSession.mockReset();
    mockedGetSession.mockResolvedValue({ server, token: 'token-1' });
  });

  it('resolves api urls against the active server', async () => {
    await expect(buildApiUrl('/api/archives')).resolves.toBe(
      'https://lanlu.example/api/archives',
    );
    await expect(buildApiUrl('api/archives')).resolves.toBe(
      'https://lanlu.example/api/archives',
    );
    await expect(buildApiUrl('https://cdn.example/a.png')).resolves.toBe(
      'https://cdn.example/a.png',
    );
  });

  it('returns relative api urls when no server is selected', async () => {
    mockedGetSession.mockResolvedValue({ server: null, token: null });
    await expect(buildApiUrl('/api/archives')).resolves.toBe('/api/archives');
  });

  it('attaches auth headers to relative and same-origin images only', async () => {
    await expect(buildAuthorizedImageSource('/api/assets/1')).resolves.toEqual({
      uri: 'https://lanlu.example/api/assets/1',
      headers: { Authorization: 'Bearer token-1' },
    });
    await expect(
      buildAuthorizedImageSource('https://lanlu.example/api/assets/2'),
    ).resolves.toEqual({
      uri: 'https://lanlu.example/api/assets/2',
      headers: { Authorization: 'Bearer token-1' },
    });
    await expect(
      buildAuthorizedImageSource('https://cdn.example/cover.png'),
    ).resolves.toEqual({ uri: 'https://cdn.example/cover.png' });
  });

  it('omits auth headers when there is no token', async () => {
    mockedGetSession.mockResolvedValue({ server, token: null });
    await expect(buildAuthorizedImageSource('/api/assets/1')).resolves.toEqual({
      uri: 'https://lanlu.example/api/assets/1',
    });
  });

  it('builds fast image sources for valid asset ids', async () => {
    await expect(buildAuthorizedAssetImageSource(12.9)).resolves.toEqual({
      uri: 'https://lanlu.example/api/assets/12',
      headers: { Authorization: 'Bearer token-1' },
      cache: 'immutable',
      priority: 'normal',
    });
    await expect(
      buildAuthorizedAssetImageSource(3, { priority: 'high' as any }),
    ).resolves.toMatchObject({ priority: 'high' });
  });

  it('returns null for missing or invalid asset ids', async () => {
    await expect(buildAuthorizedAssetImageSource()).resolves.toBeNull();
    await expect(buildAuthorizedAssetImageSource(0)).resolves.toBeNull();
    await expect(buildAuthorizedAssetImageSource(-2)).resolves.toBeNull();
    await expect(buildAuthorizedAssetImageSource(Number.NaN)).resolves.toBeNull();
  });

  it('exposes uri, token and headers for video playback', async () => {
    await expect(buildAuthorizedUri('/api/assets/5')).resolves.toEqual({
      uri: 'https://lanlu.example/api/assets/5',
      token: 'token-1',
      headers: { Authorization: 'Bearer token-1' },
    });
    await expect(buildAuthorizedUri('https://cdn.example/a.mp4')).resolves.toEqual({
      uri: 'https://cdn.example/a.mp4',
      token: 'token-1',
      headers: undefined,
    });
  });

  it('omits credentials when no token is stored', async () => {
    mockedGetSession.mockResolvedValue({ server: null, token: null });
    await expect(buildAuthorizedUri('/api/assets/5')).resolves.toEqual({
      uri: '/api/assets/5',
      token: undefined,
      headers: undefined,
    });
  });
});
