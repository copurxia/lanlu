export interface Archive {
  arcid: string;
  title: string;
  filename: string;
  summary: string;
  tags: string;
  pagecount: number;
  progress: number;
  isnew: boolean;  // 改为布尔值类型
  isfavorite?: boolean;  // 用户收藏状态（可选，仅在需要时提供）
  favoritetime?: string;  // 收藏时间（可选）
  archivetype: string;
  lastreadtime: number;
  size: number;
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
  start?: number;
  count?: number;
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
  lang?: string;
}

export interface ArchiveMetadata {
  arcid: string;
  title: string;
  filename: string;
  summary: string;
  tags: string;
  isnew: boolean;  // 改为布尔值类型
  isfavorite: boolean;  // 用户收藏状态
  pagecount: number;
  progress: number;
  lastreadtime: number;
  file_size: number;
  size: number;
  archivetype: string;
  created_at: string;
  updated_at: string;
  relative_path: string;
}
