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

export interface MetadataPagePatch {
  page?: number;
  path?: string;
  title?: string;
  description?: string;
  thumb?: string;
  sort?: number;
  hidden_in_files?: boolean;
}

export interface MetadataObject {
  title?: string;
  type?: number;
  description?: string;
  tags?: string[];
  assets?: MetadataAssets;
  archive?: MetadataObject[];
  pages?: MetadataPagePatch[];
  archive_id?: string;
  volume_no?: number;
  metadata_namespace?: string;
  [key: string]: unknown;
}

export interface Archive {
  arcid: string;
  title: string;
  filename: string;
  summary: string;
  tags: string;
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
  draw: number;
  recordsFiltered: number;
  recordsTotal: number;
}

export interface SearchParams {
  filter?: string;
  category?: string;
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
}

export interface RandomParams {
  filter?: string;
  category?: string;
  count?: number;
  newonly?: boolean;
  untaggedonly?: boolean;
  groupby_tanks?: boolean;
  lang?: string;
}

export interface ArchiveMetadata extends MetadataObject {
  archive_id: string;
  arcid: string;
  summary: string;
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
  created_at?: string;
  updated_at?: string;
  relative_path?: string;
  thumbnail_hash?: string;
}
