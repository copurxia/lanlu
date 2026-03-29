import type { Archive } from './archive';
import type { Tankoubon } from './tankoubon';

export type RecommendationScene = 'discover' | 'archive_related' | 'tankoubon_related';
export type RecommendationInteractionType = 'click' | 'open_reader' | 'favorite' | 'finish';
export type RecommendationItemType = 'archive' | 'tankoubon';

export type RecommendationItem = Archive | Tankoubon;

export interface RecommendationResponse {
  scene: RecommendationScene;
  data: RecommendationItem[];
}

export interface RecommendationQueryOptions {
  count?: number;
  category_id?: string | number;
  lang?: string;
}

export interface ArchiveRelatedRecommendationOptions {
  count?: number;
  lang?: string;
}

export interface TankoubonRelatedRecommendationOptions {
  count?: number;
  lang?: string;
}

export interface RecommendationInteractionPayload {
  scene: RecommendationScene;
  seed_entity_type?: RecommendationItemType;
  seed_entity_id?: string;
  item_type: RecommendationItemType;
  item_id: string;
  interaction_type: RecommendationInteractionType;
}
