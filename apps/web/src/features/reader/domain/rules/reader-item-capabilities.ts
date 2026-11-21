import type {
  ReaderContentItemType,
  ReaderPageItem,
  ReaderStreamItem,
  ReaderStreamPageItem,
  ReaderVirtualEndItem,
} from "@/features/reader/domain/models/reader-item";

export function isHtmlReaderItem(
  item: Pick<ReaderPageItem, "type"> | Pick<ReaderStreamItem, "type"> | null | undefined
): item is (ReaderPageItem | ReaderStreamPageItem) & { type: "html" } {
  return item?.type === "html";
}

export function isVideoReaderItem(
  item: Pick<ReaderPageItem, "type"> | Pick<ReaderStreamItem, "type"> | null | undefined
): item is (ReaderPageItem | ReaderStreamPageItem) & { type: "video" } {
  return item?.type === "video";
}

export function isImageReaderItem(
  item: Pick<ReaderPageItem, "type"> | Pick<ReaderStreamItem, "type"> | null | undefined
): item is (ReaderPageItem | ReaderStreamPageItem) & { type: "image" } {
  return item?.type === "image";
}

export function isVirtualEndReaderItem(
  item: Pick<ReaderStreamItem, "type"> | null | undefined
): item is ReaderVirtualEndItem {
  return item?.type === "virtual-end";
}

export function isReaderContentType(type: string | null | undefined): type is ReaderContentItemType {
  return type === "image" || type === "video" || type === "audio" || type === "html";
}

export function supportsSplitCoverProgressAdjustment(type: string | null | undefined): boolean {
  return type !== "html" && type !== "virtual-end";
}
