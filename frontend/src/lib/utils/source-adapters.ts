import type { SourceItem } from '@/lib/services/source-plugin-service';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

/**
 * 将 SourceItem (kind=archive) 转换为 Archive 兼容形状，
 * 用于复用 ArchiveCard / Archive 详情页 / Reader 等本地库组件。
 */
export function sourceItemToArchiveLike(item: SourceItem): Archive {
  const arcid = `source:${item.source_namespace}:${item.remote_id}`;
  return {
    arcid,
    title: item.title || '',
    filename: '',
    description: item.description || '',
    tags: (item.tags || []).join(', '),
    pagecount: item.page_count || item.reader?.page_count || 0,
    progress: 0,
    isnew: true,
    archivetype: item.reader?.media_type || 'image',
    lastreadtime: 0,
    size: 0,
    assets: item.cover_asset_id ? { cover: item.cover_asset_id } : undefined,
  };
}

/**
 * 将 SourceItem (kind=tankoubon) 转换为 Tankoubon 兼容形状，
 * 用于复用 TankoubonCard / Tankoubon 详情页等本地库组件。
 */
export function sourceItemToTankoubonLike(item: SourceItem): Tankoubon {
  const tankoubonId = `source:${item.source_namespace}:${item.remote_id}`;
  const children = (item.children || [])
    .filter((c) => c.kind === 'archive')
    .map((c) => `source:${c.source_namespace}:${c.remote_id}`);

  return {
    tankoubon_id: tankoubonId,
    title: item.title || '',
    description: item.description || '',
    tags: (item.tags || []).join(', '),
    assets: item.cover_asset_id ? { cover: item.cover_asset_id } : undefined,
    children,
    pagecount: item.page_count || 0,
    progress: 0,
    isnew: true,
    archive_count: children.length,
    isfavorite: false,
  };
}

/**
 * 判断 SourceItem 是否可被本地库详情页渲染。
 * 只要包含 kind 和 remote_id，即视为合法。
 */
export function isValidSourceItem(item: unknown): item is SourceItem {
  if (typeof item !== 'object' || item == null) return false;
  const it = item as Record<string, unknown>;
  return (
    (it.kind === 'archive' || it.kind === 'tankoubon') &&
    typeof it.remote_id === 'string' &&
    it.remote_id.length > 0 &&
    typeof it.source_namespace === 'string'
  );
}

/**
 * 从 SourceItem 构建 Source 详情页/Reader/下载所需的参数对象。
 */
export function buildSourceRouteParams(item: SourceItem): {
  source: string;
  remote_id: string;
  kind: 'archive' | 'tankoubon';
} {
  return {
    source: item.source_namespace,
    remote_id: item.remote_id,
    kind: item.kind,
  };
}
