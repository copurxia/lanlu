export interface ArchiveAssets {
  cover?: number;
  backdrop?: number;
  clearlogo?: number;
  [key: string]: number | undefined;
}

export interface MetadataAssetInput {
  key: string;
  value: string | number;
}

export type MetadataAssets = ArchiveAssets | MetadataAssetInput[];

export interface MetadataLocator {
  entity_type?: string;
  entity_id?: string;
  parent_entity_type?: string;
  parent_entity_id?: string;
  page_number?: number;
  entry_path?: string;
  volume_no?: number;
  order_index?: number;
  [key: string]: unknown;
}

export interface MetadataPageAttachment {
  slot: string;
  asset_id?: number;
  path?: string;
  name: string;
  mime_type?: string;
  kind?: string;
  language?: string;
  order_index?: number;
}

export interface MetadataPagePatch {
  page_number?: number;
  entry_path?: string;
  title?: string;
  description?: string;
  thumb?: string;
  attachments?: MetadataPageAttachment[];
  order_index?: number;
  hidden_in_files?: boolean;
  release_at?: string;
  updated_at?: string;
  readonly created_at?: string;
  locator?: MetadataLocator;
}

export interface MetadataChild {
  entity_type?: string;
  entity_id?: string;
  volume_no?: number;
  order_index?: number;
  release_at?: string;
  updated_at?: string;
  title?: string;
  description?: string;
  tags?: string[];
  assets?: MetadataAssets;
  pages?: MetadataPagePatch[];
  locator?: MetadataLocator;
  children?: MetadataChild[];
  [key: string]: unknown;
}

export interface MetadataObject {
  title?: string;
  type?: number;
  description?: string;
  tags?: string[];
  release_at?: string;
  updated_at?: string;
  assets?: MetadataAssets;
  children?: MetadataChild[];
  pages?: MetadataPagePatch[];
  locator?: MetadataLocator;
  entity_type?: string;
  entity_id?: string;
  volume_no?: number;
  order_index?: number;
  [key: string]: unknown;
}

export interface MetadataUpdatePayload extends MetadataObject {
  metadata_namespace?: string;
}

export interface Archive {
  arcid: string;
  title: string;
  filename: string;
  description: string;
  tags: string;
  release_at?: string;
  created_at?: string;
  updated_at?: string;
  pagecount: number;
  progress: number;
  isnew: boolean;
  isfavorite?: boolean;
  favoritetime?: string;
  archivetype: string;
  lastreadtime: number;
  size: number;
  assets?: ArchiveAssets;
}

export interface SearchResponse {
  data: Array<Archive | import('./tankoubon').Tankoubon>;
  groups?: SearchCategoryGroup[];
  draw: number;
  recordsFiltered: number;
  recordsTotal: number;
}

export interface SearchCategoryGroup {
  category_id: string;
  data: Array<Archive | import('./tankoubon').Tankoubon>;
  recordsFiltered: number;
  recordsTotal: number;
}

export interface SearchParams {
  filter?: string;
  category?: string;
  category_id?: string;
  category_ids?: string;
  tankoubon_id?: string;
  page?: number;
  pageSize?: number;
  sortby?: string;
  order?: string;
  newonly?: boolean;
  untaggedonly?: boolean;
  favoriteonly?: boolean;
  favorite_tankoubons_only?: boolean;
  date_from?: string;
  date_to?: string;
  groupby_tanks?: boolean;
  lang?: string;
  aggregate_by?: 'category';
}

export interface ArchiveFilesParams {
  images_only?: boolean;
  include_metadata?: boolean;
  limit?: number;
  offset?: number;
}

export interface ArchiveMetadata extends MetadataObject {
  arcid: string;
  description: string;
  tags: string[];
  assets?: ArchiveAssets;
  cover?: string;
  backdrop?: string;
  clearlogo?: string;
  filename?: string;
  isnew?: boolean;
  isfavorite?: boolean;
  pagecount?: number;
  progress?: number;
  last_read_time?: string;
  lastreadtime?: number;
  file_size?: number;
  size?: number;
  archivetype?: string;
  release_at?: string;
  readonly created_at?: string;
  updated_at?: string;
  relative_path?: string;
  thumbnail_hash?: string;
}
