import type { ArchiveMetadata, MetadataPagePatch } from '@/types/archive';
import type { PageInfo } from '@/lib/services/archive-service';

function normalizeTags(tags: unknown): string[] {
  if (!Array.isArray(tags)) return [];
  return tags.map((tag) => String(tag || '').trim()).filter(Boolean);
}

function getTagValue(tags: string[], prefix: string): string {
  const wantedPrefix = `${prefix}:`.toLowerCase();
  const match = tags.find((tag) => tag.toLowerCase().startsWith(wantedPrefix));
  if (!match) return '';
  return match.slice(prefix.length + 1).trim();
}

export function isTvTagSet(tags: unknown): boolean {
  const normalized = normalizeTags(tags);
  return normalized.some((tag) => {
    const lower = tag.toLowerCase();
    return lower === 'media:tv' || lower === 'media:season' || lower.startsWith('source:tvdb:');
  });
}

export function isTvArchiveMetadata(metadata: Pick<ArchiveMetadata, 'tags'> | null | undefined): boolean {
  return isTvTagSet(metadata?.tags);
}

export function getTvMetaSummary(tags: unknown): {
  season: string;
  year: string;
  status: string;
} {
  const normalized = normalizeTags(tags);
  return {
    season: getTagValue(normalized, 'season'),
    year: getTagValue(normalized, 'year'),
    status: getTagValue(normalized, 'status'),
  };
}

export function getPageReleaseAt(page: PageInfo | MetadataPagePatch): string {
  if ('metadata' in page) {
    return String(page.metadata?.release_at || '').trim();
  }
  return String(('release_at' in page ? page.release_at : '') || '').trim();
}

export function getTvPageTitle(page: PageInfo | MetadataPagePatch): string {
  if ('metadata' in page) {
    return String(page.metadata?.title || page.title || '').trim();
  }
  return String(page.title || '').trim();
}
