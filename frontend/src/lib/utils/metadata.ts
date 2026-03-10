import type {
  ArchiveAssets,
  ArchiveMetadata,
  MetadataAssetInput,
  MetadataChild,
  MetadataLocator,
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
    const rows = rawAssets
      .map((item) => {
        const row = asRecord(item);
        const key = readString(row.key).toLowerCase();
        const value = row.value;
        if (!key) return null;
        if (typeof value !== 'string' && typeof value !== 'number') return null;
        return { key, value } satisfies MetadataAssetInput;
      })
      .filter((item): item is MetadataAssetInput => Boolean(item));
    return rows.length > 0 ? rows : undefined;
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

function normalizeMetadataLocator(rawLocator: unknown): MetadataLocator | undefined {
  const row = asRecord(rawLocator);
  const entityType = readString(row.entity_type);
  const entityId = readString(row.entity_id);
  const parentEntityType = readString(row.parent_entity_type);
  const parentEntityId = readString(row.parent_entity_id);
  const pageNumber = readNumber(row.page_number);
  const entryPath = readString(row.entry_path);
  const volumeNo = readNumber(row.volume_no);
  const orderIndex = readNumber(row.order_index);

  const locator: MetadataLocator = {};
  if (entityType) locator.entity_type = entityType;
  if (entityId) locator.entity_id = entityId;
  if (parentEntityType) locator.parent_entity_type = parentEntityType;
  if (parentEntityId) locator.parent_entity_id = parentEntityId;
  if (typeof pageNumber === 'number' && Number.isFinite(pageNumber)) locator.page_number = Math.trunc(pageNumber);
  if (entryPath) locator.entry_path = entryPath;
  if (typeof volumeNo === 'number' && Number.isFinite(volumeNo)) locator.volume_no = Math.trunc(volumeNo);
  if (typeof orderIndex === 'number' && Number.isFinite(orderIndex)) locator.order_index = Math.trunc(orderIndex);

  return Object.keys(locator).length > 0 ? locator : undefined;
}

function normalizeMetadataChildren(rawChildren: unknown): MetadataChild[] {
  if (!Array.isArray(rawChildren)) return [];
  return rawChildren.map((item) => normalizeMetadataObject(item));
}

export function normalizeMetadataTags(rawTags: unknown): string[] {
  if (Array.isArray(rawTags)) {
    return rawTags.map((tag) => String(tag || '').trim()).filter(Boolean);
  }
  const text = readString(rawTags);
  if (!text) return [];
  return text
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean);
}

export function normalizeMetadataPages(rawPages: unknown): MetadataPagePatch[] {
  if (!Array.isArray(rawPages)) return [];

  const normalized: MetadataPagePatch[] = [];
  for (const item of rawPages) {
    const row = asRecord(item);
    const pageNumber = readNumber(row.page_number);
    const orderIndex = readNumber(row.order_index);
    const hiddenInFiles = row.hidden_in_files === true;
    const entryPath = readString(row.entry_path);
    const title = readString(row.title);
    const description = readString(row.description);
    const thumb = readString(row.thumb);

    if (!entryPath && !(typeof pageNumber === 'number' && pageNumber > 0)) continue;

    normalized.push({
      page_number: typeof pageNumber === 'number' && pageNumber > 0 ? Math.trunc(pageNumber) : undefined,
      entry_path: entryPath || undefined,
      title: title || undefined,
      description: description || undefined,
      thumb: thumb || undefined,
      order_index: typeof orderIndex === 'number' && Number.isFinite(orderIndex) ? Math.trunc(orderIndex) : undefined,
      hidden_in_files: hiddenInFiles || undefined,
      locator: normalizeMetadataLocator(row.locator),
    });
  }

  return normalized;
}

export function normalizeMetadataObject(raw: unknown): MetadataObject {
  const row = asRecord(raw);
  const children = normalizeMetadataChildren(row.children);
  const orderIndex = readNumber(row.order_index);
  const volumeNo = readNumber(row.volume_no);

  return {
    ...row,
    title: readString(row.title) || undefined,
    type: readNumber(row.type),
    description: readString(row.description) || undefined,
    tags: normalizeMetadataTags(row.tags),
    assets: normalizeMetadataAssetMap(row.assets),
    children,
    pages: normalizeMetadataPages(row.pages),
    locator: normalizeMetadataLocator(row.locator),
    entity_type: readString(row.entity_type) || undefined,
    entity_id: readString(row.entity_id) || undefined,
    volume_no: typeof volumeNo === 'number' && Number.isFinite(volumeNo) ? Math.trunc(volumeNo) : undefined,
    order_index: typeof orderIndex === 'number' && Number.isFinite(orderIndex) ? Math.trunc(orderIndex) : undefined,
  };
}

export function normalizeArchiveMetadata(raw: unknown): ArchiveMetadata {
  const row = asRecord(raw);
  const metadata = normalizeMetadataObject(raw);
  const description = readString(metadata.description || row.description);
  const pagecount = readNumber(row.pagecount);
  const progress = readNumber(row.progress);
  const fileSize = readNumber(row.file_size ?? row.size);
  const lastReadTime = readNumber(row.lastreadtime);
  const arcid = readString(row.arcid || metadata.entity_id);

  const normalizedAssets = normalizeMetadataAssetMap(metadata.assets ?? row.assets);
  const rawAssets = metadata.assets ?? row.assets;

  return {
    ...metadata,
    arcid,
    description,
    tags: metadata.tags || [],
    assets: normalizedAssets,
    cover: readMetadataAssetValue(rawAssets, 'cover') || readString(row.cover) || undefined,
    backdrop: readMetadataAssetValue(rawAssets, 'backdrop') || readString(row.backdrop) || undefined,
    clearlogo: readMetadataAssetValue(rawAssets, 'clearlogo') || readString(row.clearlogo) || undefined,
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

  return {
    ...metadata,
    updated_at: readString(row.updated_at) || undefined,
    cover: readMetadataAssetValue(row.assets, 'cover') || readString(row.cover) || undefined,
    backdrop: readMetadataAssetValue(row.assets, 'backdrop') || readString(row.backdrop) || undefined,
    clearlogo: readMetadataAssetValue(row.assets, 'clearlogo') || readString(row.clearlogo) || undefined,
    pages: normalizeMetadataPages(row.pages),
  };
}

export function normalizeTankoubonMetadata(raw: unknown): TankoubonMetadata {
  const row = asRecord(raw);
  const metadata = normalizeMetadataObject(raw);
  const description = readString(metadata.description || row.description);
  const childrenSource = Array.isArray(row.children) ? row.children : [];
  const children = childrenSource.map((item) => normalizeTankoubonMemberMetadataPatch(item));
  const archiveCount = readNumber(row.archive_count);
  const pagecount = readNumber(row.pagecount);
  const progress = readNumber(row.progress);

  const normalizedAssets = normalizeMetadataAssetMap(metadata.assets ?? row.assets);
  const rawAssets = metadata.assets ?? row.assets;

  return {
    ...metadata,
    tankoubon_id: readString(row.tankoubon_id || metadata.entity_id),
    title: readString(metadata.title || row.title),
    description,
    tags: metadata.tags || [],
    assets: normalizedAssets,
    children,
    archive_count: typeof archiveCount === 'number' && Number.isFinite(archiveCount) ? Math.trunc(archiveCount) : children.length,
    pagecount: typeof pagecount === 'number' && Number.isFinite(pagecount) ? Math.trunc(pagecount) : undefined,
    progress: typeof progress === 'number' && Number.isFinite(progress) ? Math.trunc(progress) : undefined,
    lastreadtime: readString(row.lastreadtime || row.last_read_time) || undefined,
    isnew: row.isnew === true,
    isfavorite: row.isfavorite === true,
    cover: readMetadataAssetValue(rawAssets, 'cover') || readString(row.cover) || undefined,
    backdrop: readMetadataAssetValue(rawAssets, 'backdrop') || readString(row.backdrop) || undefined,
    clearlogo: readMetadataAssetValue(rawAssets, 'clearlogo') || readString(row.clearlogo) || undefined,
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
