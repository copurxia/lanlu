import type { Archive, ArchiveAssets, MetadataObject, MetadataPagePatch } from './archive';

export interface Tankoubon {
  tankoubon_id: string;
  name: string;
  summary: string;
  tags: string;
  cover_asset_id?: number;
  assets?: ArchiveAssets;
  cover?: string;
  backdrop?: string;
  clearlogo?: string;
  archives?: string[];
  pagecount?: number;
  progress?: number;
  lastreadtime?: string;
  isnew?: boolean;
  archive_count?: number;
  isfavorite?: boolean;
  favoritetime?: string;
}

export interface TankoubonDetail extends Tankoubon {
  archiveDetails: Archive[];
}

export interface TankoubonCreateRequest {
  name: string;
  summary?: string;
  tags?: string;
}

export interface TankoubonMemberMetadataPatch extends MetadataObject {
  archive_id?: string;
  volume_no?: number;
  summary?: string;
  updated_at?: string;
  cover?: string;
  backdrop?: string;
  clearlogo?: string;
  pages?: MetadataPagePatch[];
}

export interface TankoubonMetadata extends MetadataObject {
  tankoubon_id: string;
  name: string;
  title?: string;
  description?: string;
  summary: string;
  tags: string[];
  archive: TankoubonMemberMetadataPatch[];
  archives: string[];
  archive_count?: number;
  pagecount?: number;
  progress?: number;
  lastreadtime?: string;
  isnew?: boolean;
  isfavorite?: boolean;
  cover?: string;
  backdrop?: string;
  clearlogo?: string;
}

export interface TankoubonUpdateRequest {
  name?: string;
  summary?: string;
  tags?: string;
  cover?: string;
  backdrop?: string;
  clearlogo?: string;
  metadata_namespace?: string;
  cover_asset_id?: number;
  assets?: ArchiveAssets;
  archives?: Array<{
    archive_id?: string;
    volume_no?: number;
    title?: string;
    summary?: string;
    tags?: string;
    updated_at?: string;
    cover?: string;
    backdrop?: string;
    clearlogo?: string;
  }>;
}

export interface TankoubonResponse {
  filtered: number;
  result: Tankoubon | Tankoubon[];
  total: number;
}
