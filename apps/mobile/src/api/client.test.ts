import { AxiosError, AxiosHeaders } from 'axios';

import { clearSessionCache, getSession } from '../auth/session';
import { clearStoredToken } from '../storage/token';
import {
  apiClient,
  buildApiUrl,
  buildAuthorizedAssetImageSource,
  buildAuthorizedImageSource,
  buildAuthorizedImageSourceForSession,
  buildAuthorizedUri,
  extractApiError,
  isNetworkError,
  isSameOriginUrl,
  parseHttpOrigin,
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

function requestConfig(url?: string) {
  return { url, headers: new AxiosHeaders() } as any;
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

  it('leaves the request untouched without a server even when a token exists', async () => {
    mockedGetSession.mockResolvedValue({ server: null, token: 'token-1' });
    const config = requestConfig('/api/archives');

    const result = await requestHandler(config);

    expect(result.headers.Authorization).toBeUndefined();
  });

  it('attaches auth to same-origin absolute requests', async () => {
    const config = await requestHandler(
      requestConfig('https://lanlu.example/api/archives'),
    );

    expect(config.headers.Authorization).toBe('Bearer token-1');
  });

  it('does not attach auth to cross-origin absolute requests', async () => {
    const config = await requestHandler(
      requestConfig('https://lanlu.example.evil.com/api/archives'),
    );

    expect(config.headers.Authorization).toBeUndefined();
  });

  it('resolves protocol-relative request urls against the server scheme', async () => {
    const same = await requestHandler(requestConfig('//lanlu.example/api/archives'));
    expect(same.headers.Authorization).toBe('Bearer token-1');

    const cross = await requestHandler(requestConfig('//evil.com/api/archives'));
    expect(cross.headers.Authorization).toBeUndefined();
  });

  it('does not attach auth to non-http schemes', async () => {
    const config = await requestHandler(
      requestConfig('ftp://lanlu.example/api/archives'),
    );

    expect(config.headers.Authorization).toBeUndefined();
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
      token: undefined,
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

describe('authorized header origin checks', () => {
  beforeEach(() => {
    mockedGetSession.mockReset();
    mockedGetSession.mockResolvedValue({ server, token: 'token-1' });
  });

  async function expectRejected(url: string) {
    const image = await buildAuthorizedImageSource(url);
    expect(image).toEqual({ uri: url });

    const video = await buildAuthorizedUri(url);
    expect(video).toEqual({ uri: url, token: undefined, headers: undefined });
  }

  it('rejects a lookalike host suffix', async () => {
    await expectRejected('https://lanlu.example.evil.com/api/assets/1');
  });

  it('rejects a different port on the same host', async () => {
    await expectRejected('https://lanlu.example:8443/api/assets/1');
  });

  it('rejects a scheme downgrade', async () => {
    await expectRejected('http://lanlu.example/api/assets/1');
  });

  it('rejects a userinfo host spoof', async () => {
    await expectRejected('https://lanlu.example@evil.com/api/assets/1');
  });

  it('rejects a different IPv6 host for both image and video sinks', async () => {
    mockedGetSession.mockResolvedValue({
      server: { id: 's1', baseUrl: 'https://[::1]:8443' } as any,
      token: 'token-1',
    });

    await expect(
      buildAuthorizedImageSource('https://[::2]:8443/api/assets/1'),
    ).resolves.toEqual({ uri: 'https://[::2]:8443/api/assets/1' });
    await expect(
      buildAuthorizedUri('https://[::2]:8443/api/assets/1'),
    ).resolves.toEqual({
      uri: 'https://[::2]:8443/api/assets/1',
      token: undefined,
      headers: undefined,
    });

    await expect(
      buildAuthorizedUri('https://[::1]:8443/api/assets/1'),
    ).resolves.toEqual({
      uri: 'https://[::1]:8443/api/assets/1',
      token: 'token-1',
      headers: { Authorization: 'Bearer token-1' },
    });
  });

  it('treats a protocol-relative path as an absolute candidate', async () => {
    const image = await buildAuthorizedImageSource('//evil.com/api/assets/1');
    expect(image).toEqual({ uri: 'https://lanlu.example//evil.com/api/assets/1' });

    const video = await buildAuthorizedUri('//evil.com/api/assets/1');
    expect(video).toEqual({
      uri: 'https://lanlu.example//evil.com/api/assets/1',
      token: undefined,
      headers: undefined,
    });
  });

  it('keeps query strings and fragments on the same origin authenticated', async () => {
    const absolute = 'https://lanlu.example/api/assets/1?v=2#page';
    await expect(buildAuthorizedImageSource(absolute)).resolves.toEqual({
      uri: absolute,
      headers: { Authorization: 'Bearer token-1' },
    });
    await expect(buildAuthorizedUri(absolute)).resolves.toEqual({
      uri: absolute,
      token: 'token-1',
      headers: { Authorization: 'Bearer token-1' },
    });
  });

  it('treats an explicit default port as the same origin', async () => {
    mockedGetSession.mockResolvedValue({
      server: { id: 's1', baseUrl: 'https://lanlu.example:443' } as any,
      token: 'token-1',
    });

    await expect(
      buildAuthorizedImageSource('https://lanlu.example/api/assets/1'),
    ).resolves.toEqual({
      uri: 'https://lanlu.example/api/assets/1',
      headers: { Authorization: 'Bearer token-1' },
    });
  });

  it('handles a base url that includes a path prefix', async () => {
    mockedGetSession.mockResolvedValue({
      server: { id: 's1', baseUrl: 'https://lanlu.example/lanlu' } as any,
      token: 'token-1',
    });

    await expect(buildAuthorizedImageSource('/api/assets/1')).resolves.toEqual({
      uri: 'https://lanlu.example/lanlu/api/assets/1',
      headers: { Authorization: 'Bearer token-1' },
    });
    await expect(
      buildAuthorizedImageSource('https://lanlu.example/other/cover.png'),
    ).resolves.toEqual({
      uri: 'https://lanlu.example/other/cover.png',
      headers: { Authorization: 'Bearer token-1' },
    });
    await expect(
      buildAuthorizedImageSource('https://lanlu.example.evil.com/cover.png'),
    ).resolves.toEqual({ uri: 'https://lanlu.example.evil.com/cover.png' });
  });

  it('prefixes a leading at-sign so a relative path cannot become userinfo', async () => {
    await expect(buildAuthorizedImageSource('@evil.com/cover.png')).resolves.toEqual({
      uri: 'https://lanlu.example/@evil.com/cover.png',
      headers: { Authorization: 'Bearer token-1' },
    });
  });

  it('never attaches credentials when no server is selected', async () => {
    mockedGetSession.mockResolvedValue({ server: null, token: 'token-1' });

    await expect(buildAuthorizedImageSource('/api/assets/1')).resolves.toEqual({
      uri: '/api/assets/1',
    });
    await expect(buildAuthorizedUri('/api/assets/1')).resolves.toEqual({
      uri: '/api/assets/1',
      token: undefined,
      headers: undefined,
    });
    await expect(
      buildAuthorizedImageSource('https://lanlu.example/api/assets/1'),
    ).resolves.toEqual({ uri: 'https://lanlu.example/api/assets/1' });
  });
});

describe('http origin parser', () => {
  it('normalizes scheme, host case and default ports', () => {
    expect(parseHttpOrigin('HTTPS://LANLU.EXAMPLE:443/x')).toBe(
      'https://lanlu.example',
    );
    expect(parseHttpOrigin('http://Lanlu.Example:80')).toBe('http://lanlu.example');
    expect(parseHttpOrigin('https://lanlu.example:8443/x?q=1#h')).toBe(
      'https://lanlu.example:8443',
    );
    expect(parseHttpOrigin('https://lanlu.example:0443/x')).toBe(
      'https://lanlu.example',
    );
  });

  it('keeps IPv6 literals distinct instead of truncating at the first colon', () => {
    expect(parseHttpOrigin('https://[::1]/x')).toBe('https://[::1]');
    expect(parseHttpOrigin('https://[::1]:8443/x')).toBe('https://[::1]:8443');
    expect(parseHttpOrigin('https://[::2]/x')).toBe('https://[::2]');
    expect(parseHttpOrigin('https://[::1]:443/x')).toBe('https://[::1]');

    expect(isSameOriginUrl('https://[::1]/x', 'https://[::1]')).toBe(true);
    expect(isSameOriginUrl('https://[::1]:443/x', 'https://[::1]')).toBe(true);
    expect(isSameOriginUrl('https://[::1]/x', 'https://[::2]')).toBe(false);
    expect(isSameOriginUrl('https://[::1]:8443/x', 'https://[::1]')).toBe(false);
    expect(isSameOriginUrl('https://[::2]:8443/x', 'https://[::1]:8443')).toBe(
      false,
    );
  });

  it('fails closed on malformed authorities and unsupported schemes', () => {
    expect(parseHttpOrigin('https://[::1/x')).toBeNull();
    expect(parseHttpOrigin('https://::1]/x')).toBeNull();
    expect(parseHttpOrigin('https://[127.0.0.1]/x')).toBeNull();
    expect(parseHttpOrigin('https://user@lanlu.example/x')).toBeNull();
    expect(parseHttpOrigin('https://lanlu.example@evil.com/x')).toBeNull();
    expect(parseHttpOrigin('ftp://lanlu.example/x')).toBeNull();
    expect(parseHttpOrigin('lanlu.example/x')).toBeNull();
    expect(parseHttpOrigin('https://lanlu.example%2eevil.com/x')).toBeNull();
    expect(parseHttpOrigin('https://[fe80::1%25eth0]/x')).toBeNull();
  });

  it('rejects invalid ports', () => {
    expect(parseHttpOrigin('https://lanlu.example:65536/x')).toBeNull();
    expect(parseHttpOrigin('https://lanlu.example:-1/x')).toBeNull();
    expect(parseHttpOrigin('https://lanlu.example:abc/x')).toBeNull();
    expect(parseHttpOrigin('https://lanlu.example:/x')).toBeNull();
    expect(parseHttpOrigin('https://[::1]:/x')).toBeNull();
    expect(parseHttpOrigin('https://lanlu.example:0/x')).toBe(
      'https://lanlu.example:0',
    );
  });

  it('resolves protocol-relative urls against the base scheme', () => {
    expect(isSameOriginUrl('//lanlu.example/x', 'https://lanlu.example')).toBe(true);
    expect(isSameOriginUrl('//lanlu.example:443/x', 'https://lanlu.example')).toBe(
      true,
    );
    expect(isSameOriginUrl('//lanlu.example/x', 'http://lanlu.example')).toBe(true);
    expect(isSameOriginUrl('//evil.com/x', 'https://lanlu.example')).toBe(false);
    expect(isSameOriginUrl('//lanlu.example.evil.com/x', 'https://lanlu.example')).toBe(
      false,
    );
  });

  it('compares exact origins rather than host prefixes', () => {
    expect(isSameOriginUrl('https://lanlu.example./x', 'https://lanlu.example')).toBe(
      false,
    );
    expect(isSameOriginUrl('https://lanlu.example/x', 'https://LANLU.example/')).toBe(
      true,
    );
    expect(isSameOriginUrl('http://lanlu.example/x', 'https://lanlu.example')).toBe(
      false,
    );
    expect(isSameOriginUrl('https://lanlu.example:8443/x', 'https://lanlu.example')).toBe(
      false,
    );
  });
});

describe('session image builder for sidebar thumbnails', () => {
  const sessionServer = { id: 's1', baseUrl: 'https://lanlu.example' } as any;

  it('omits headers for cross-origin absolute thumbnails', () => {
    expect(
      buildAuthorizedImageSourceForSession(
        'https://evil.example/thumb.png',
        sessionServer,
        'token-1',
      ),
    ).toEqual({ uri: 'https://evil.example/thumb.png' });
    expect(
      buildAuthorizedImageSourceForSession(
        'https://lanlu.example.evil.com/thumb.png',
        sessionServer,
        'token-1',
      ),
    ).toEqual({ uri: 'https://lanlu.example.evil.com/thumb.png' });
  });

  it('omits headers for protocol-relative thumbnails', () => {
    expect(
      buildAuthorizedImageSourceForSession(
        '//evil.example/thumb.png',
        sessionServer,
        'token-1',
      ),
    ).toEqual({ uri: 'https://lanlu.example//evil.example/thumb.png' });
  });

  it('keeps headers for same-origin and relative thumbnails', () => {
    expect(
      buildAuthorizedImageSourceForSession(
        'https://lanlu.example/thumb.png',
        sessionServer,
        'token-1',
      ),
    ).toEqual({
      uri: 'https://lanlu.example/thumb.png',
      headers: { Authorization: 'Bearer token-1' },
    });
    expect(
      buildAuthorizedImageSourceForSession('/api/assets/1', sessionServer, 'token-1'),
    ).toEqual({
      uri: 'https://lanlu.example/api/assets/1',
      headers: { Authorization: 'Bearer token-1' },
    });
  });

  it('omits headers without a server or token', () => {
    expect(
      buildAuthorizedImageSourceForSession('/api/assets/1', null, 'token-1'),
    ).toEqual({ uri: '/api/assets/1' });
    expect(
      buildAuthorizedImageSourceForSession('/api/assets/1', sessionServer, null),
    ).toEqual({ uri: 'https://lanlu.example/api/assets/1' });
  });
});
