export function formatSeconds(seconds: number) {
  if (!Number.isFinite(seconds) || seconds < 0) return '--:--';
  const whole = Math.floor(seconds);
  const h = Math.floor(whole / 3600);
  const m = Math.floor((whole % 3600) / 60);
  const s = whole % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${m}:${String(s).padStart(2, '0')}`;
}

export function formatPercent(value: number) {
  if (!Number.isFinite(value)) return '--%';
  return `${Math.round(value * 100)}%`;
}

export function formatMiB(bytes: number | null) {
  if (!bytes || !Number.isFinite(bytes) || bytes <= 0) return '-- MiB';
  return `${(bytes / 1024 / 1024).toFixed(2)} MiB`;
}

export function formatKiB(bytes: number | null) {
  if (!bytes || !Number.isFinite(bytes) || bytes <= 0) return '-- KiB';
  return `${(bytes / 1024).toFixed(1)} KiB`;
}

export function formatMs(value: number | null) {
  if (!value || !Number.isFinite(value) || value < 0) return '--ms';
  if (value < 1000) return `${Math.round(value)}ms`;
  return `${(value / 1000).toFixed(2)}s`;
}

export function getApproxResourceBytes(resourceUrl: string) {
  if (typeof window === 'undefined') return null;
  if (!resourceUrl) return null;

  if (resourceUrl.startsWith('data:')) {
    const base64Index = resourceUrl.indexOf('base64,');
    if (base64Index >= 0) {
      const base64 = resourceUrl.slice(base64Index + 'base64,'.length);
      const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0;
      return Math.floor((base64.length * 3) / 4) - padding;
    }
    return null;
  }

  try {
    const entries = performance.getEntriesByName(resourceUrl) as PerformanceEntry[];
    const resourceEntries = entries.filter((entry) => entry.entryType === 'resource') as PerformanceResourceTiming[];
    const latest = resourceEntries.sort((a, b) => a.startTime - b.startTime).at(-1);
    if (!latest) return null;
    const bytes = latest.transferSize || latest.encodedBodySize || latest.decodedBodySize;
    return bytes && bytes > 0 ? bytes : null;
  } catch {
    return null;
  }
}

export function getLatestResourceTiming(resourceUrl: string) {
  if (typeof window === 'undefined') return null;
  if (!resourceUrl) return null;
  try {
    const entries = performance.getEntriesByName(resourceUrl) as PerformanceEntry[];
    const resourceEntries = entries.filter((entry) => entry.entryType === 'resource') as PerformanceResourceTiming[];
    const latest = resourceEntries.sort((a, b) => a.startTime - b.startTime).at(-1);
    return latest || null;
  } catch {
    return null;
  }
}

export function getImageFormatLabel(resourceUrl: string) {
  if (!resourceUrl) return null;

  if (resourceUrl.startsWith('data:')) {
    const match = resourceUrl.match(/^data:([^;,]+)[;,]/i);
    const mime = match?.[1]?.toLowerCase() || '';
    if (mime.startsWith('image/')) return mime.slice('image/'.length);
    return null;
  }

  try {
    const parsed = new URL(resourceUrl, typeof window !== 'undefined' ? window.location.origin : 'http://localhost');
    const pathnameExt = parsed.pathname.split('/').pop()?.split('.').pop();
    if (pathnameExt && pathnameExt !== parsed.pathname) return pathnameExt.toLowerCase();

    const pathParam = parsed.searchParams.get('path');
    if (pathParam) {
      const decoded = decodeURIComponent(pathParam);
      const ext = decoded.split('/').pop()?.split('.').pop();
      if (ext) return ext.toLowerCase();
    }
  } catch {
    const ext = resourceUrl.split('?')[0]?.split('#')[0]?.split('.').pop();
    if (ext && ext !== resourceUrl) return ext.toLowerCase();
  }

  return null;
}

export function getLastPathSegment(url: string) {
  try {
    const parsed = new URL(url, typeof window !== 'undefined' ? window.location.origin : 'http://localhost');
    const pathname = parsed.pathname || '';
    const last = pathname.split('/').filter(Boolean).pop();
    return last || url;
  } catch {
    const parts = url.split('?')[0]?.split('#')[0]?.split('/').filter(Boolean);
    return parts?.[parts.length - 1] || url;
  }
}

