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
  relative_path?: string;
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

export type Tankoubon = {
  tankoubon_id: string;
  title: string;
  description?: string;
  children?: string[];
  assets?: ArchiveAssets;
  isfavorite?: boolean;
  favoritetime?: string;
  progress?: number;
  pagecount?: number;
};

export type TankoubonMetadata = {
  tankoubon_id: string;
  title?: string;
  description?: string;
  tags?: string[];
  assets?: ArchiveAssets;
  children?: string[];
  archive_count?: number;
  pagecount?: number;
  progress?: number;
  isfavorite?: boolean;
};

export type MediaItem = Archive | Tankoubon;

export type Category = {
  id: number;
  catid: string;
  name: string;
  description?: string;
  icon?: string;
  sort_order?: number;
  enabled?: boolean;
  archive_count?: number;
  cover_asset_id?: number;
};

export type SearchGroup = {
  category_id?: string;
  data: MediaItem[];
  recordsFiltered?: number;
  recordsTotal?: number;
};

export type SearchResponse = {
  data: MediaItem[];
  groups?: SearchGroup[];
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
    attachments?: MetadataPageAttachment[];
    release_at?: string;
  };
};

export type MetadataPageAttachment = {
  slot: string;
  name: string;
  asset_id: number;
  mime_type?: string;
  kind?: string;
  language?: string;
  order_index?: number;
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

export type AuthSession = {
  id: number;
  name: string;
  prefix: string;
  createdAt?: string;
  lastUsedAt?: string;
  lastUsedIp?: string;
  userAgent?: string;
  expiresAt?: string;
  current?: boolean;
};

export type PasskeyCredential = {
  id: number;
  name: string;
  credentialId: string;
  algorithm: string;
  transports: string[];
  userVerified: boolean;
  backupEligible: boolean;
  backupState: boolean;
  createdAt: string;
  lastUsedAt: string;
};

export type TotpStatus = {
  enabled: boolean;
  credentialName?: string;
  createdAt?: string;
  recoveryCodesRemaining: number;
};

export type TotpEnrollmentPayload = {
  challengeId: string;
  secret: string;
  manualEntryKey: string;
  otpauthUri: string;
  issuer: string;
  accountName: string;
};

export type StepUpOptions = {
  methods: string[];
};

export type AuthTokenFull = AuthToken & {token: string};
