import type { Archive, ArchiveAssets, MetadataLocator, MetadataObject, MetadataPagePatch } from './archive';

export interface Tankoubon {
  tankoubon_id: string;
  title: string;
  description: string;
  tags: string;
  release_at?: string;
  created_at?: string;
  updated_at?: string;
  assets?: ArchiveAssets;
  children?: string[];
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
  volume_no?: number;
  order_index?: number;
  release_at?: string;
  updated_at?: string;
  readonly created_at?: string;
  cover?: string;
  backdrop?: string;
  clearlogo?: string;
  pages?: MetadataPagePatch[];
  locator?: MetadataLocator;
}

export interface TankoubonMetadata extends MetadataObject {
  tankoubon_id: string;
  title: string;
  description: string;
  tags: string[];
  assets?: ArchiveAssets;
  children: TankoubonMemberMetadataPatch[];
  archive_count?: number;
  pagecount?: number;
  progress?: number;
  lastreadtime?: string;
  isnew?: boolean;
  isfavorite?: boolean;
  release_at?: string;
  updated_at?: string;
  readonly created_at?: string;
  cover?: string;
  backdrop?: string;
  clearlogo?: string;
}

export interface TankoubonResponse {
  filtered: number;
  result: Tankoubon | Tankoubon[];
  total: number;
}
