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

/** True for request paths that axios resolves against `baseURL`. */
export function isRelativeRequestUrl(url: string): boolean {
  return !/^[a-z][a-z\d+.-]*:/i.test(url) && !url.startsWith('//');
}

/**
 * Credential gate shared by the axios interceptor and every non-axios sink
 * (EventSource, native upload, FastImage, VLC). A missing or unparseable base
 * URL always fails closed.
 */
export function shouldAttachAuth(
  url: string,
  baseUrl?: string | null,
): boolean {
  if (!baseUrl || !parseHttpOrigin(baseUrl)) {
    return false;
  }
  return isRelativeRequestUrl(url) || isSameOriginUrl(url, baseUrl);
}

export function authHeadersForUrl(
  url: string,
  baseUrl: string | null | undefined,
  token: string | null | undefined,
): Record<string, string> | undefined {
  return token && shouldAttachAuth(url, baseUrl)
    ? {Authorization: `Bearer ${token}`}
    : undefined;
}
