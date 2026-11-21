import {
  authHeadersForUrl,
  isSameOriginUrl,
  parseHttpOrigin,
  shouldAttachAuth,
} from './httpOrigin';

describe('http origin credentials gate', () => {
  const base = 'https://lanlu.example';

  it('returns auth headers for relative and same-origin urls only', () => {
    expect(authHeadersForUrl('/api/archives', base, 'token-1')).toEqual({
      Authorization: 'Bearer token-1',
    });
    expect(authHeadersForUrl('api/archives', base, 'token-1')).toEqual({
      Authorization: 'Bearer token-1',
    });
    expect(authHeadersForUrl('https://lanlu.example/api', base, 'token-1')).toEqual({
      Authorization: 'Bearer token-1',
    });
    expect(authHeadersForUrl('https://evil.example/api', base, 'token-1')).toBeUndefined();
    expect(authHeadersForUrl('https://lanlu.example.evil.com/api', base, 'token-1')).toBeUndefined();
    expect(authHeadersForUrl('//evil.example/api', base, 'token-1')).toBeUndefined();
  });

  it('fails closed without a token or a parseable base url', () => {
    expect(authHeadersForUrl('/api/archives', base, null)).toBeUndefined();
    expect(authHeadersForUrl('/api/archives', null, 'token-1')).toBeUndefined();
    expect(authHeadersForUrl('/api/archives', '192.168.1.5:8080', 'token-1')).toBeUndefined();
    expect(shouldAttachAuth('/api/archives', 'https://h:99999')).toBe(false);
    expect(shouldAttachAuth('/api/archives', 'https://u@h')).toBe(false);
  });

  it('keeps valid IPv6 and default-port forms working', () => {
    expect(parseHttpOrigin('https://[::1]:8443')).toBe('https://[::1]:8443');
    expect(authHeadersForUrl('https://[::1]:443/x', 'https://[::1]', 'token-1')).toEqual({
      Authorization: 'Bearer token-1',
    });
    expect(isSameOriginUrl('https://[::1]/x', 'https://[::2]')).toBe(false);
  });
});
