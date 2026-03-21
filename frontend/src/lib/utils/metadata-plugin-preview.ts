import { readMetadataAssetValue } from '@/lib/utils/archive-assets';
import { isSuccessResponse } from '@/lib/utils/api-utils';
import { normalizeMetadataPages } from '@/lib/utils/metadata';
import type { MetadataPagePatch } from '@/types/archive';

export type MetadataPluginPreviewData = {
  title: string;
  summary: string;
  tags: string[];
  cover: string;
  backdrop: string;
  clearlogo: string;
  children: unknown[];
  pages: MetadataPagePatch[];
};

export type MetadataPluginPreviewParseResult =
  | { ok: true; data: MetadataPluginPreviewData }
  | { ok: false; error?: string; parseFailed?: boolean };

export function parseMetadataPluginPreviewResult(rawResult: string | null | undefined): MetadataPluginPreviewParseResult {
  if (!rawResult) {
    return { ok: false, parseFailed: true };
  }

  let out: any;
  try {
    out = JSON.parse(rawResult);
  } catch {
    return { ok: false, parseFailed: true };
  }

  if (!isSuccessResponse(out?.success)) {
    return { ok: false, error: String(out?.error || '').trim() || undefined };
  }

  const data = out?.data || {};
  const tags = Array.isArray(data.tags)
    ? data.tags.map((tag: unknown) => String(tag || '').trim()).filter(Boolean)
    : [];

  return {
    ok: true,
    data: {
      title: typeof data.title === 'string' ? data.title : '',
      summary: typeof data.description === 'string' ? data.description : '',
      tags,
      cover: readMetadataAssetValue(data.assets, 'cover'),
      backdrop: readMetadataAssetValue(data.assets, 'backdrop'),
      clearlogo: readMetadataAssetValue(data.assets, 'clearlogo'),
      children: Array.isArray(data.children) ? data.children : [],
      pages: normalizeMetadataPages(data.pages),
    },
  };
}

export function applyAssetPreviewValue(
  rawValue: string,
  setPathValue: (next: string) => void,
  setAssetIdValue: (next: string) => void
): void {
  const trimmed = String(rawValue || '').trim();
  if (!trimmed) return;

  if (/^\d+$/.test(trimmed)) {
    const parsedId = Number.parseInt(trimmed, 10);
    if (Number.isFinite(parsedId) && parsedId > 0) {
      setAssetIdValue(String(parsedId));
      setPathValue('');
      return;
    }
  }

  setPathValue(trimmed);
}
