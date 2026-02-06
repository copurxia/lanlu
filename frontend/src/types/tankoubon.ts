export interface Tankoubon {
  tankoubon_id: string;
  name: string;
  summary: string;
  tags: string;
  cover_asset_id?: number;
  cover?: string;
  archives?: string[];  // Array of arcids (optional for search results)

  // Aggregated metadata for display (only in search results)
  pagecount?: number;
  progress?: number;
  lastreadtime?: string;
  isnew?: boolean;
  archive_count?: number;
  isfavorite?: boolean;
  favoritetime?: string;  // 收藏时间（可选）
}

export interface TankoubonDetail extends Tankoubon {
  archiveDetails: Archive[];  // Full archive objects
}

export interface TankoubonCreateRequest {
  name: string;
  summary?: string;
  tags?: string;
}

export interface TankoubonUpdateRequest {
  name?: string;
  summary?: string;
  tags?: string;
  cover?: string;
  cover_asset_id?: number;
  archives?: Array<{
    archive_id?: string;
    volume_no?: number;
    title?: string;
    summary?: string;
    tags?: string;
    updated_at?: string;
    cover?: string;
  }>;
}

export interface TankoubonResponse {
  filtered: number;
  result: Tankoubon | Tankoubon[];
  total: number;
}

// Import Archive type from existing types
import type { Archive } from './archive';
