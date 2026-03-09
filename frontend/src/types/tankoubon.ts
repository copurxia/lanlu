import type { Archive, ArchiveAssets, MetadataLocator, MetadataObject, MetadataPagePatch } from './archive';

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
  entity_type?: string;
  entity_id?: string;
  archive_id?: string;
  volume_no?: number;
  order_index?: number;
  summary?: string;
  updated_at?: string;
  cover?: string;
  backdrop?: string;
  clearlogo?: string;
  pages?: MetadataPagePatch[];
  locator?: MetadataLocator;
}

export interface TankoubonMetadata extends MetadataObject {
  tankoubon_id: string;
  name: string;
  title?: string;
  description?: string;
  summary: string;
  tags: string[];
  assets?: ArchiveAssets;
  children: TankoubonMemberMetadataPatch[];
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

export interface TankoubonResponse {
  filtered: number;
  result: Tankoubon | Tankoubon[];
  total: number;
}
