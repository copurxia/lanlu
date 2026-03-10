import type { ArchiveAssets } from '@/types/archive';

type ArchiveAssetSource = {
  assets?: unknown;
} | null | undefined;

type CoverAssetSource = {
  assets?: unknown;
} | null | undefined;

function toPositiveAssetId(value: unknown): number | undefined {
  if (value === null || value === undefined) return undefined;
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n)) return undefined;
  const id = Math.trunc(n);
  return id > 0 ? id : undefined;
}

export function normalizeArchiveAssets(rawAssets: unknown): ArchiveAssets {
  const normalized: ArchiveAssets = {};
  if (rawAssets && typeof rawAssets === 'object' && !Array.isArray(rawAssets)) {
    for (const [key, value] of Object.entries(rawAssets as Record<string, unknown>)) {
      const id = toPositiveAssetId(value);
      if (id !== undefined) {
        normalized[key] = id;
      }
    }
  }
  return normalized;
}

function normalizeMetadataAssetValue(rawValue: unknown): string {
  if (rawValue === null || rawValue === undefined) return '';
  if (typeof rawValue === 'number' && Number.isFinite(rawValue)) {
    return String(Math.trunc(rawValue));
  }
  if (typeof rawValue === 'bigint') {
    return String(rawValue);
  }
  if (typeof rawValue === 'string') {
    return rawValue.trim();
  }
  if (rawValue && typeof rawValue === 'object' && !Array.isArray(rawValue)) {
    const row = rawValue as Record<string, unknown>;
    const candidates = [row.value, row.path, row.id, row.asset_id, row.assetId];
    for (const candidate of candidates) {
      const normalized = normalizeMetadataAssetValue(candidate);
      if (normalized) return normalized;
    }
  }
  return '';
}

/**
 * Read a metadata-plugin asset value from either:
 * - array form: [{ key, value }]
 * - object form: { cover: 123, backdrop: "..." }
 */
export function readMetadataAssetValue(rawAssets: unknown, key: string): string {
  const wanted = String(key || '').trim().toLowerCase();
  if (!wanted) return '';

  if (Array.isArray(rawAssets)) {
    for (const item of rawAssets) {
      if (!item || typeof item !== 'object' || Array.isArray(item)) continue;
      const row = item as Record<string, unknown>;
      const itemKey = String(row.key ?? row.type ?? row.name ?? '').trim().toLowerCase();
      if (itemKey !== wanted) continue;
      return normalizeMetadataAssetValue(row.value ?? row.path ?? row.id ?? row.asset_id ?? row.assetId);
    }
    return '';
  }

  if (rawAssets && typeof rawAssets === 'object') {
    const assets = rawAssets as Record<string, unknown>;
    const directMatch = assets[wanted];
    if (directMatch !== undefined) {
      return normalizeMetadataAssetValue(directMatch);
    }
    for (const [assetKey, assetValue] of Object.entries(assets)) {
      if (assetKey.trim().toLowerCase() !== wanted) continue;
      return normalizeMetadataAssetValue(assetValue);
    }
  }

  return '';
}

function toAssetUrl(rawValue: unknown): string {
  const normalized = normalizeMetadataAssetValue(rawValue);
  if (!normalized) return '';
  if (/^\d+$/.test(normalized)) {
    return `/api/assets/${normalized}`;
  }
  if (normalized.startsWith('/') || /^https?:\/\//i.test(normalized)) {
    return normalized;
  }
  return '';
}

export function getArchiveAssetId(source: ArchiveAssetSource, key: string = 'cover'): number | undefined {
  if (!source) return undefined;
  const assets = normalizeArchiveAssets(source.assets);
  return assets[key];
}

export function getCoverAssetId(source: CoverAssetSource): number | undefined {
  if (!source) return undefined;
  return getArchiveAssetId(source, 'cover');
}

export function resolveArchiveAssetUrl(
  source: ArchiveAssetSource,
  key: string,
  fallbackValue?: unknown
): string {
  const id = getArchiveAssetId(source, key);
  if (id !== undefined) return `/api/assets/${id}`;

  const fromAssets = readMetadataAssetValue(source?.assets, key);
  if (fromAssets) return toAssetUrl(fromAssets);

  return toAssetUrl(fallbackValue);
}

export function normalizeArchivePayload<T extends { assets?: unknown }>(
  payload: T
): T & { assets: ArchiveAssets } {
  return {
    ...payload,
    assets: normalizeArchiveAssets(payload.assets),
  };
}
