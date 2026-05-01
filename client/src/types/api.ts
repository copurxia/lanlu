export type ApiEnvelope<T> = {
  code: number;
  message: string;
  data?: T;
};

export type ArchiveAssets = {
  cover?: number;
  backdrop?: number;
  clearlogo?: number;
  [key: string]: number | undefined;
};

export type Archive = {
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
};

export type SearchResponse = {
  data: Archive[];
  draw: number;
  recordsFiltered: number;
  recordsTotal: number;
};

export type ArchiveMetadata = {
  arcid: string;
  title?: string;
  filename?: string;
  description?: string;
  tags?: string[];
  assets?: ArchiveAssets;
  pagecount?: number;
  progress?: number;
  isnew?: boolean;
  isfavorite?: boolean;
  archivetype?: string;
  size?: number;
  release_at?: string;
  updated_at?: string;
  created_at?: string;
};

export type PageInfo = {
  id: string;
  path?: string;
  url?: string;
  type?: 'image' | 'video' | 'audio' | 'html';
  title?: string;
  defaultSourceIndex?: number;
  defaultSource?: PageSourceInfo;
  sources?: PageSourceInfo[];
  metadata?: {
    title?: string;
    description?: string;
    thumb_asset_id?: number;
    thumb?: string;
  };
};

export type PageSourceInfo = {
  id: string;
  path: string;
  url?: string;
  type: 'image' | 'video' | 'audio' | 'html';
  title?: string;
  metadata?: PageInfo['metadata'];
};

export type ArchiveFilesResponse =
  | PageInfo[]
  | {
      pages?: PageInfo[];
      files?: PageInfo[];
      data?: PageInfo[];
      pagecount?: number;
    };

export type AuthUser = {
  id: number;
  username: string;
  isAdmin?: boolean;
  avatarAssetId?: number;
  createdAt?: string;
};

export type AuthToken = {
  id: number;
  name: string;
  prefix: string;
  token?: string;
};

export type AuthLoginPendingTotp = {
  challengeId: string;
};

export type LoginResponse = ApiEnvelope<{
  user?: AuthUser;
  token?: AuthToken;
  challengeId?: string;
}>;
