export type ReaderContentItemType = "image" | "video" | "html";
export type ReaderItemType = ReaderContentItemType | "virtual-end";

export type ReaderItemMetadata = {
  title?: string;
  description?: string;
  thumb_asset_id?: number;
  thumb?: string;
};

export type ReaderPageItem = {
  archiveId: string;
  path: string;
  url: string;
  type: ReaderContentItemType;
  title?: string;
  metadata?: ReaderItemMetadata;
};

export type ReaderSegment = {
  archiveId: string;
  start: number;
  count: number;
  title: string;
  coverAssetId?: number;
};

export type ReaderStreamPageItem = ReaderPageItem & {
  streamSegmentIndex: number;
  streamLocalPage: number;
  streamRealPage: number;
};

export type ReaderVirtualEndItem = {
  type: "virtual-end";
  archiveId: string;
  streamSegmentIndex: number;
};

export type ReaderStreamItem = ReaderStreamPageItem | ReaderVirtualEndItem;
