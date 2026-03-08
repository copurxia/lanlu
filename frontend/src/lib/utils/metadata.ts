import type {
  ArchiveAssets,
  ArchiveMetadata,
  MetadataAssetInput,
  MetadataObject,
  MetadataPagePatch,
} from '@/types/archive';
import type { TankoubonMemberMetadataPatch, TankoubonMetadata } from '@/types/tankoubon';
import { normalizeArchiveAssets, readMetadataAssetValue } from '@/lib/utils/archive-assets';

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

function readString(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value.trim();
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return '';
}

function readNumber(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

function normalizeMetadataAssetInputs(rawAssets: unknown): MetadataAssetInput[] | undefined {
  if (Array.isArray(rawAssets)) {
    return rawAssets
      .map((item) => {
        const row = asRecord(item);
        const key = readString(row.key || row.type || row.name).toLowerCase();
        const value = row.value;
        if (!key) return null;
        if (typeof value !== 'string' && typeof value !== 'number') return null;
        return { key, value } satisfies MetadataAssetInput;
      })
      .filter((item): item is MetadataAssetInput => Boolean(item));
  }

  const record = asRecord(rawAssets);
  const entries = Object.entries(record)
    .map(([key, value]) => {
      const normalizedKey = readString(key).toLowerCase();
      if (!normalizedKey) return null;
      if (typeof value !== 'string' && typeof value !== 'number') return null;
      return { key: normalizedKey, value } satisfies MetadataAssetInput;
    })
    .filter((item): item is MetadataAssetInput => Boolean(item));

  return entries.length > 0 ? entries : undefined;
}

function normalizeMetadataAssetMap(rawAssets: unknown): ArchiveAssets | undefined {
  const entries = normalizeMetadataAssetInputs(rawAssets);
  if (!entries || entries.length === 0) return normalizeArchiveAssets(rawAssets);

  const normalized: ArchiveAssets = {};
  for (const item of entries) {
    const value = typeof item.value === 'number' ? item.value : Number(item.value);
    if (!Number.isFinite(value)) continue;
    const id = Math.trunc(value);
    if (id > 0) {
      normalized[item.key] = id;
    }
  }
  return normalized;
}

export function normalizeMetadataTags(rawTags: unknown): string[] {
  if (Array.isArray(rawTags)) {
    return rawTags.map((tag) => String(tag || '').trim()).filter(Boolean);
  }
  const text = readString(rawTags);
  if (!text) return [];
  return text.split(',').map((tag) => tag.trim()).filter(Boolean);
}

export function normalizeMetadataPages(rawPages: unknown): MetadataPagePatch[] {
  if (!Array.isArray(rawPages)) return [];

  const normalized: MetadataPagePatch[] = [];
  for (const item of rawPages) {
    const row = asRecord(item);
    const page = readNumber(row.page ?? row.page_number ?? row.pageNumber);
    const sort = readNumber(row.sort);
    const hiddenInFiles = row.hidden_in_files === true || row.hiddenInFiles === true;
    const path = readString(row.path || row.entry_path || row.entryPath || row.entry);
    const title = readString(row.title);
    const description = readString(row.description || row.summary);
    const thumb = readString(row.thumb || asRecord(row.metadata).thumb);

    if (!path && !(typeof page === 'number' && page > 0)) continue;

    normalized.push({
      page: typeof page === 'number' && page > 0 ? Math.trunc(page) : undefined,
      path: path || undefined,
      title: title || undefined,
      description: description || undefined,
      thumb: thumb || undefined,
      sort: typeof sort === 'number' && Number.isFinite(sort) ? Math.trunc(sort) : undefined,
      hidden_in_files: hiddenInFiles || undefined,
    });
  }

  return normalized;
}

export function normalizeMetadataObject(raw: unknown): MetadataObject {
  const row = asRecord(raw);
  return {
    ...row,
    title: readString(row.title || row.name) || undefined,
    type: readNumber(row.type),
    description: readString(row.description || row.summary) || undefined,
    tags: normalizeMetadataTags(row.tags),
    assets: normalizeMetadataAssetMap(row.assets),
    archive: Array.isArray(row.archive) ? row.archive.map((item) => normalizeMetadataObject(item)) : [],
    pages: normalizeMetadataPages(row.pages),
    archive_id: readString(row.archive_id || row.archiveId || row.arcid) || undefined,
    volume_no: (() => {
      const volumeNo = readNumber(row.volume_no || row.volumeNo);
      return typeof volumeNo === 'number' && Number.isFinite(volumeNo) ? Math.trunc(volumeNo) : undefined;
    })(),
    metadata_namespace: readString(row.metadata_namespace || row.metadataNamespace || row.namespace) || undefined,
  };
}

export function normalizeArchiveMetadata(raw: unknown): ArchiveMetadata {
  const row = asRecord(raw);
  const metadata = normalizeMetadataObject(raw);
  const archiveId = readString(metadata.archive_id || row.archive_id || row.archiveId || row.arcid);
  const description = readString(metadata.description || row.description || row.summary);
  const pagecount = readNumber(row.pagecount);
  const progress = readNumber(row.progress);
  const fileSize = readNumber(row.file_size ?? row.size);
  const lastReadTime = readNumber(row.lastreadtime);

  return {
    ...metadata,
    archive_id: archiveId,
    arcid: archiveId,
    summary: description,
    tags: metadata.tags || [],
    assets: normalizeMetadataAssetMap(row.assets),
    cover: readMetadataAssetValue(row.assets, 'cover') || readString(row.cover) || undefined,
    backdrop: readMetadataAssetValue(row.assets, 'backdrop') || readString(row.backdrop) || undefined,
    clearlogo: readMetadataAssetValue(row.assets, 'clearlogo') || readString(row.clearlogo) || undefined,
    filename: readString(row.filename) || undefined,
    relative_path: readString(row.relative_path) || undefined,
    pagecount: typeof pagecount === 'number' && Number.isFinite(pagecount) ? Math.trunc(pagecount) : metadata.pages?.length || 0,
    progress: typeof progress === 'number' && Number.isFinite(progress) ? Math.trunc(progress) : 0,
    isnew: row.isnew === true,
    isfavorite: row.isfavorite === true,
    last_read_time: readString(row.last_read_time) || undefined,
    lastreadtime: typeof lastReadTime === 'number' && Number.isFinite(lastReadTime) ? Math.trunc(lastReadTime) : undefined,
    file_size: typeof fileSize === 'number' && Number.isFinite(fileSize) ? fileSize : undefined,
    size: typeof fileSize === 'number' && Number.isFinite(fileSize) ? fileSize : undefined,
    archivetype: readString(row.archivetype || row.archive_type) || undefined,
    created_at: readString(row.created_at) || undefined,
    updated_at: readString(row.updated_at) || undefined,
    thumbnail_hash: readString(row.thumbnail_hash || row.thumbhash) || undefined,
  };
}

export function normalizeTankoubonMemberMetadataPatch(raw: unknown): TankoubonMemberMetadataPatch {
  const row = asRecord(raw);
  const metadata = normalizeMetadataObject(raw);
  const description = readString(metadata.description || row.description || row.summary);

  return {
    ...metadata,
    summary: description || undefined,
    updated_at: readString(row.updated_at || row.updatedAt) || undefined,
    cover: readMetadataAssetValue(row.assets, 'cover') || readString(row.cover) || undefined,
    backdrop: readMetadataAssetValue(row.assets, 'backdrop') || readString(row.backdrop) || undefined,
    clearlogo: readMetadataAssetValue(row.assets, 'clearlogo') || readString(row.clearlogo) || undefined,
    pages: normalizeMetadataPages(row.pages),
  };
}

export function normalizeTankoubonMetadata(raw: unknown): TankoubonMetadata {
  const row = asRecord(raw);
  const metadata = normalizeMetadataObject(raw);
  const description = readString(metadata.description || row.description || row.summary);
  const archive = Array.isArray(row.archive) ? row.archive.map((item) => normalizeTankoubonMemberMetadataPatch(item)) : [];
  const archives = archive
    .map((item) => readString(item.archive_id))
    .filter(Boolean);
  const archiveCount = readNumber(row.archive_count ?? row.archiveCount);
  const pagecount = readNumber(row.pagecount);
  const progress = readNumber(row.progress);

  return {
    ...metadata,
    tankoubon_id: readString(row.tankoubon_id || row.id),
    name: readString(row.name || metadata.title),
    summary: description,
    tags: metadata.tags || [],
    archive,
    archives,
    archive_count: typeof archiveCount === 'number' && Number.isFinite(archiveCount) ? Math.trunc(archiveCount) : archive.length,
    pagecount: typeof pagecount === 'number' && Number.isFinite(pagecount) ? Math.trunc(pagecount) : undefined,
    progress: typeof progress === 'number' && Number.isFinite(progress) ? Math.trunc(progress) : undefined,
    lastreadtime: readString(row.lastreadtime || row.last_read_time) || undefined,
    isnew: row.isnew === true,
    isfavorite: row.isfavorite === true,
    cover: readMetadataAssetValue(row.assets, 'cover') || readString(row.cover) || undefined,
    backdrop: readMetadataAssetValue(row.assets, 'backdrop') || readString(row.backdrop) || undefined,
    clearlogo: readMetadataAssetValue(row.assets, 'clearlogo') || readString(row.clearlogo) || undefined,
  };
}

export function buildMetadataAssetInputs(
  values: Partial<Record<'cover' | 'backdrop' | 'clearlogo', string>>,
  assetIds?: Partial<Record<'cover' | 'backdrop' | 'clearlogo', number | undefined>>
): MetadataAssetInput[] | undefined {
  const slots: Array<'cover' | 'backdrop' | 'clearlogo'> = ['cover', 'backdrop', 'clearlogo'];
  const assets: MetadataAssetInput[] = [];

  for (const slot of slots) {
    const textValue = readString(values[slot]);
    const assetId = assetIds?.[slot];
    if (textValue) {
      assets.push({ key: slot, value: textValue });
      continue;
    }
    if (typeof assetId === 'number' && Number.isFinite(assetId) && assetId > 0) {
      assets.push({ key: slot, value: Math.trunc(assetId) });
    }
  }

  return assets.length > 0 ? assets : undefined;
}
