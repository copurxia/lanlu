import { apiClient } from '@/lib/api';
import { normalizeArchiveAssets, normalizeArchivePayload } from '@/lib/utils/archive-assets';
import { getRecommendationSessionKey } from '@/lib/utils/recommendation-session';
import type { Archive } from '@/types/archive';
import type {
  ArchiveRelatedRecommendationOptions,
  RecommendationInteractionPayload,
  RecommendationItem,
  RecommendationQueryOptions,
  RecommendationResponse,
  TankoubonRelatedRecommendationOptions,
} from '@/types/recommendation';
import type { Tankoubon } from '@/types/tankoubon';

function isArchiveItem(item: unknown): item is Archive {
  return Boolean(item) && typeof item === 'object' && 'arcid' in (item as Record<string, unknown>);
}

function normalizeTagsText(source: unknown): string {
  if (Array.isArray(source)) {
    return source.map((value) => String(value || '').trim()).filter(Boolean).join(',');
  }
  return String(source || '').trim();
}

function normalizeArchiveItem(item: Archive): Archive {
  const normalized = normalizeArchivePayload(item);
  return {
    ...normalized,
    description: String((normalized as any).description || '').trim(),
    tags: normalizeTagsText((normalized as any).tags ?? (normalized as any).tags_text),
  };
}

function normalizeMixedItems(items: unknown[]): Array<Archive | Tankoubon> {
  return items.map((item) => {
    if (isArchiveItem(item)) {
      return normalizeArchiveItem(item);
    }
    const tank = item as Tankoubon & { assets?: unknown; children?: unknown };
    return {
      ...tank,
      title: String((tank as any).title || '').trim(),
      description: String((tank as any).description || '').trim(),
      tags: normalizeTagsText((tank as any).tags ?? (tank as any).tags_text),
      children: Array.isArray(tank.children)
        ? tank.children.map((value) => String(value || '').trim()).filter(Boolean)
        : [],
      assets: normalizeArchiveAssets(tank.assets),
    };
  });
}

function buildHeaders() {
  return {
    'X-Recommendation-Session': getRecommendationSessionKey(),
  };
}

export class RecommendationService {
  static async getDiscover(options: RecommendationQueryOptions = {}): Promise<RecommendationItem[]> {
    const response = await apiClient.get<RecommendationResponse>('/api/recommendations', {
      params: {
        scene: 'discover',
        count: options.count ?? 12,
        category_id: options.category_id,
        lang: options.lang,
      },
      headers: buildHeaders(),
    });
    return normalizeMixedItems(Array.isArray(response.data?.data) ? response.data.data : []);
  }

  static async getArchiveRelated(
    archiveId: string,
    options: ArchiveRelatedRecommendationOptions = {}
  ): Promise<Archive[]> {
    const response = await apiClient.get<RecommendationResponse>('/api/recommendations', {
      params: {
        scene: 'archive_related',
        archive_id: archiveId,
        count: options.count ?? 12,
        lang: options.lang,
      },
      headers: buildHeaders(),
    });
    return normalizeMixedItems(Array.isArray(response.data?.data) ? response.data.data : []).filter(
      (item): item is Archive => isArchiveItem(item)
    );
  }

  static async getTankoubonRelated(
    tankoubonId: string,
    options: TankoubonRelatedRecommendationOptions = {}
  ): Promise<Tankoubon[]> {
    const response = await apiClient.get<RecommendationResponse>('/api/recommendations', {
      params: {
        scene: 'tankoubon_related',
        tankoubon_id: tankoubonId,
        count: options.count ?? 12,
        lang: options.lang,
      },
      headers: buildHeaders(),
    });
    return normalizeMixedItems(Array.isArray(response.data?.data) ? response.data.data : []).filter(
      (item): item is Tankoubon => !isArchiveItem(item)
    );
  }

  static async recordInteraction(payload: RecommendationInteractionPayload): Promise<void> {
    await apiClient.post('/api/recommendations/interactions', payload, {
      headers: buildHeaders(),
    });
  }
}
