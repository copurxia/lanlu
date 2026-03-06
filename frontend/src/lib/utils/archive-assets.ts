import type { ArchiveAssets } from '@/types/archive';

type ArchiveAssetSource = {
  assets?: unknown;
} | null | undefined;

type CoverAssetSource = {
  assets?: unknown;
  cover_asset_id?: unknown;
  coverAssetId?: unknown;
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

export function getArchiveAssetId(source: ArchiveAssetSource, key: string = 'cover'): number | undefined {
  if (!source) return undefined;
  const assets = normalizeArchiveAssets(source.assets);
  return assets[key];
}

export function getCoverAssetId(source: CoverAssetSource): number | undefined {
  if (!source) return undefined;
  const fromAssets = getArchiveAssetId(source, 'cover');
  if (fromAssets !== undefined) return fromAssets;
  return toPositiveAssetId(source.cover_asset_id ?? source.coverAssetId);
}

export function normalizeArchivePayload<T extends { assets?: unknown }>(
  payload: T
): T & { assets: ArchiveAssets } {
  return {
    ...payload,
    assets: normalizeArchiveAssets(payload.assets),
  };
}
