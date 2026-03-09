import type {
  ArchiveAssets,
  ArchiveMetadata,
  MetadataAssetInput,
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

function normalizeMetadataLocator(rawLocator: unknown, fallback?: Record<string, unknown>): MetadataLocator | undefined {
  const locatorRow = asRecord(rawLocator);
  const entityType = readString(locatorRow.entity_type || locatorRow.entityType || fallback?.entity_type || fallback?.entityType);
  const entityId = readString(
    locatorRow.entity_id ||
      locatorRow.entityId ||
      fallback?.entity_id ||
      fallback?.entityId ||
      fallback?.archive_id ||
      fallback?.archiveId ||
      fallback?.arcid ||
      fallback?.tankoubon_id ||
      fallback?.tankoubonId
  );
  const parentEntityType = readString(
    locatorRow.parent_entity_type || locatorRow.parentEntityType || fallback?.parent_entity_type || fallback?.parentEntityType
  );
  const parentEntityId = readString(
    locatorRow.parent_entity_id ||
      locatorRow.parentEntityId ||
      fallback?.parent_entity_id ||
      fallback?.parentEntityId ||
      fallback?.archive_id ||
      fallback?.archiveId ||
      fallback?.arcid
  );
  const archiveId = readString(locatorRow.archive_id || locatorRow.archiveId || fallback?.archive_id || fallback?.archiveId || fallback?.arcid);
  const tankoubonId = readString(locatorRow.tankoubon_id || locatorRow.tankoubonId || fallback?.tankoubon_id || fallback?.tankoubonId);
  const page = readNumber(
    locatorRow.page ??
      locatorRow.page_number ??
      locatorRow.pageNumber ??
      fallback?.page ??
      fallback?.page_number ??
      fallback?.pageNumber
  );
  const path = readString(
    locatorRow.path ||
      locatorRow.entry_path ||
      locatorRow.entryPath ||
      locatorRow.entry ||
      fallback?.path ||
      fallback?.entry_path ||
      fallback?.entryPath ||
      fallback?.entry
  );
  const volumeNo = readNumber(locatorRow.volume_no || locatorRow.volumeNo || fallback?.volume_no || fallback?.volumeNo);
  const orderIndex = readNumber(
    locatorRow.order_index || locatorRow.orderIndex || fallback?.order_index || fallback?.orderIndex || fallback?.sort
  );

  const locator: MetadataLocator = {};
  if (entityType) locator.entity_type = entityType;
  if (entityId) locator.entity_id = entityId;
  if (parentEntityType) locator.parent_entity_type = parentEntityType;
  if (parentEntityId) locator.parent_entity_id = parentEntityId;
  if (archiveId) locator.archive_id = archiveId;
  if (tankoubonId) locator.tankoubon_id = tankoubonId;
  if (typeof page === 'number' && Number.isFinite(page)) {
    locator.page = Math.trunc(page);
    locator.page_number = Math.trunc(page);
  }
  if (path) {
    locator.path = path;
    locator.entry_path = path;
    locator.entry = path;
  }
  if (typeof volumeNo === 'number' && Number.isFinite(volumeNo)) locator.volume_no = Math.trunc(volumeNo);
  if (typeof orderIndex === 'number' && Number.isFinite(orderIndex)) locator.order_index = Math.trunc(orderIndex);

  return Object.keys(locator).length > 0 ? locator : undefined;
}

function normalizeMetadataChildren(rawChildren: unknown): MetadataObject[] {
  if (!Array.isArray(rawChildren)) return [];
  return rawChildren.map((item) => normalizeMetadataObject(item));
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
    const sort = readNumber(row.sort ?? row.order_index ?? row.orderIndex);
    const hiddenInFiles = row.hidden_in_files === true || row.hiddenInFiles === true;
    const path = readString(row.path || row.entry_path || row.entryPath || row.entry);
    const title = readString(row.title);
    const description = readString(row.description || row.summary);
    const thumb = readString(row.thumb || asRecord(row.metadata).thumb);

    if (!path && !(typeof page === 'number' && page > 0)) continue;

    const normalizedPage = typeof page === 'number' && page > 0 ? Math.trunc(page) : undefined;
    const normalizedSort = typeof sort === 'number' && Number.isFinite(sort) ? Math.trunc(sort) : undefined;

    normalized.push({
      page: normalizedPage,
      page_number: normalizedPage,
      path: path || undefined,
      entry_path: path || undefined,
      title: title || undefined,
      description: description || undefined,
      thumb: thumb || undefined,
      sort: normalizedSort,
      order_index: normalizedSort,
      hidden_in_files: hiddenInFiles || undefined,
      locator: normalizeMetadataLocator(row.locator, row),
    });
  }

  return normalized;
}

export function normalizeMetadataObject(raw: unknown): MetadataObject {
  const row = asRecord(raw);
  const rawChildren = Array.isArray(row.children) ? row.children : Array.isArray(row.archive) ? row.archive : [];
  const children = normalizeMetadataChildren(rawChildren);
  const orderIndex = readNumber(row.order_index || row.orderIndex || row.sort);
  const volumeNo = readNumber(row.volume_no || row.volumeNo);

  return {
    ...row,
    title: readString(row.title || row.name) || undefined,
    type: readNumber(row.type),
    description: readString(row.description || row.summary) || undefined,
    tags: normalizeMetadataTags(row.tags),
    assets: normalizeMetadataAssetMap(row.assets),
    children,
    archive: children,
    pages: normalizeMetadataPages(row.pages),
    locator: normalizeMetadataLocator(row.locator, row),
    entity_type: readString(row.entity_type || row.entityType) || undefined,
    entity_id: readString(row.entity_id || row.entityId) || undefined,
    archive_id: readString(row.archive_id || row.archiveId || row.arcid || row.entity_id || row.entityId) || undefined,
    volume_no: typeof volumeNo === 'number' && Number.isFinite(volumeNo) ? Math.trunc(volumeNo) : undefined,
    order_index: typeof orderIndex === 'number' && Number.isFinite(orderIndex) ? Math.trunc(orderIndex) : undefined,
  };
}

export function normalizeArchiveMetadata(raw: unknown): ArchiveMetadata {
  const row = asRecord(raw);
  const metadata = normalizeMetadataObject(raw);
  const archiveId = readString(metadata.archive_id || row.archive_id || row.archiveId || row.arcid || metadata.entity_id);
  const description = readString(metadata.description || row.description || row.summary);
  const pagecount = readNumber(row.pagecount);
  const progress = readNumber(row.progress);
  const fileSize = readNumber(row.file_size ?? row.size);
  const lastReadTime = readNumber(row.lastreadtime);

  const normalizedAssets = normalizeMetadataAssetMap(metadata.assets ?? row.assets);
  const rawAssets = metadata.assets ?? row.assets;

  return {
    ...metadata,
    archive_id: archiveId,
    arcid: archiveId,
    summary: description,
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
  const description = readString(metadata.description || row.description || row.summary);
  const archiveId = readString(metadata.archive_id || row.archive_id || row.archiveId || row.arcid || metadata.entity_id);

  return {
    ...metadata,
    archive_id: archiveId || undefined,
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
  const childrenSource = Array.isArray(row.children) ? row.children : Array.isArray(row.archive) ? row.archive : [];
  const children = childrenSource.map((item) => normalizeTankoubonMemberMetadataPatch(item));
  const archives = children
    .map((item) => readString(item.archive_id || item.entity_id))
    .filter(Boolean);
  const archiveCount = readNumber(row.archive_count ?? row.archiveCount);
  const pagecount = readNumber(row.pagecount);
  const progress = readNumber(row.progress);

  const normalizedAssets = normalizeMetadataAssetMap(metadata.assets ?? row.assets);
  const rawAssets = metadata.assets ?? row.assets;

  return {
    ...metadata,
    tankoubon_id: readString(row.tankoubon_id || row.id || metadata.entity_id),
    name: readString(row.name || metadata.title),
    title: readString(metadata.title || row.name) || undefined,
    description: description || undefined,
    summary: description,
    tags: metadata.tags || [],
    assets: normalizedAssets,
    children,
    archive: children,
    archives,
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
