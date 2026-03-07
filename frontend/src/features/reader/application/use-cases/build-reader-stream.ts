import type {
  ReaderPageItem,
  ReaderSegment,
  ReaderStreamItem,
} from "@/features/reader/domain/models/reader-item";
import { isVirtualEndReaderItem } from "@/features/reader/domain/rules/reader-item-capabilities";

export type BuildReaderStreamInput = {
  sourceArchiveId: string | null;
  pages: ReaderPageItem[];
  segments: ReaderSegment[];
  includeInterChapterVirtualPages: boolean;
};

export type BuildReaderStreamResult = {
  effectiveSegments: ReaderSegment[];
  items: ReaderStreamItem[];
  streamIndexByRealPage: Map<number, number>;
  streamVirtualIndexBySegment: Map<number, number>;
  virtualPageIndex: number;
};

export function buildReaderStream({
  sourceArchiveId,
  pages,
  segments,
  includeInterChapterVirtualPages,
}: BuildReaderStreamInput): BuildReaderStreamResult {
  const effectiveSegments =
    segments.length > 0
      ? segments
      : sourceArchiveId
        ? [
            {
              archiveId: sourceArchiveId,
              start: 0,
              count: pages.length,
              title: sourceArchiveId,
            },
          ]
        : [];

  const items: ReaderStreamItem[] = [];

  if (pages.length > 0) {
    if (effectiveSegments.length <= 0) {
      pages.forEach((page, index) => {
        items.push({
          ...page,
          streamSegmentIndex: 0,
          streamLocalPage: index,
          streamRealPage: index,
        });
      });

      items.push({
        type: "virtual-end",
        archiveId: sourceArchiveId ?? "",
        streamSegmentIndex: 0,
      });
    } else {
      effectiveSegments.forEach((segment, segmentIndex) => {
        const end = segment.start + segment.count;
        for (let realIndex = segment.start; realIndex < end; realIndex += 1) {
          const page = pages[realIndex];
          if (!page) continue;
          items.push({
            ...page,
            streamSegmentIndex: segmentIndex,
            streamLocalPage: realIndex - segment.start,
            streamRealPage: realIndex,
          });
        }

        const isTailSegment = segmentIndex === effectiveSegments.length - 1;
        if (includeInterChapterVirtualPages || isTailSegment) {
          items.push({
            type: "virtual-end",
            archiveId: segment.archiveId,
            streamSegmentIndex: segmentIndex,
          });
        }
      });
    }
  }

  const streamIndexByRealPage = new Map<number, number>();
  const streamVirtualIndexBySegment = new Map<number, number>();
  let virtualPageIndex = -1;

  items.forEach((item, index) => {
    if (isVirtualEndReaderItem(item)) {
      streamVirtualIndexBySegment.set(item.streamSegmentIndex, index);
      virtualPageIndex = index;
      return;
    }
    streamIndexByRealPage.set(item.streamRealPage, index);
  });

  return {
    effectiveSegments,
    items,
    streamIndexByRealPage,
    streamVirtualIndexBySegment,
    virtualPageIndex,
  };
}
