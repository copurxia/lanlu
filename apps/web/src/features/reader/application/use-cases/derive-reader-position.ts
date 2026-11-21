import type {
  ReaderItemType,
  ReaderPageItem,
  ReaderSegment,
  ReaderStreamItem,
} from '@/features/reader/domain/models/reader-item';
import { isHtmlReaderItem, isVirtualEndReaderItem } from '@/features/reader/domain/rules/reader-item-capabilities';

export type DeriveReaderPositionInput = {
  currentPage: number;
  pages: ReaderPageItem[];
  streamPages: ReaderStreamItem[];
  effectiveSegments: ReaderSegment[];
  sourceArchiveId: string | null;
  readingMode: 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';
  doublePageMode: boolean;
  seamlessEnabled: boolean;
};

export type DeriveReaderPositionResult = {
  currentStreamItem: ReaderStreamItem | null;
  activeSegment: ReaderSegment | null;
  activeArchiveId: string | null;
  activeLocalPage: number;
  currentRealPage: number;
  nextArchiveLookupId: string | null;
  currentPageType: ReaderItemType | null;
  isCurrentHtmlPage: boolean;
  isCollectionEndPage: boolean;
  activeSegmentLastRealPage: number;
  isCurrentOrTailHtmlPage: boolean;
  isHtmlSpreadView: boolean;
  sliderCurrentPage: number;
  sliderTotalPages: number;
};

export function deriveReaderPosition({
  currentPage,
  pages,
  streamPages,
  effectiveSegments,
  sourceArchiveId,
  readingMode,
  doublePageMode,
  seamlessEnabled,
}: DeriveReaderPositionInput): DeriveReaderPositionResult {
  const currentStreamItem = streamPages[currentPage] ?? null;

  const activeSegment = (() => {
    if (effectiveSegments.length <= 0) return null;
    const segmentIndex = currentStreamItem?.streamSegmentIndex;
    if (
      typeof segmentIndex === 'number' &&
      segmentIndex >= 0 &&
      segmentIndex < effectiveSegments.length
    ) {
      return effectiveSegments[segmentIndex];
    }
    return effectiveSegments[effectiveSegments.length - 1] ?? null;
  })();

  const activeArchiveId = currentStreamItem?.archiveId ?? activeSegment?.archiveId ?? sourceArchiveId;

  const activeLocalPage = (() => {
    if (!activeSegment) return Math.max(0, currentPage);
    if (currentStreamItem && !isVirtualEndReaderItem(currentStreamItem)) {
      return currentStreamItem.streamLocalPage;
    }
    return Math.max(0, activeSegment.count - 1);
  })();

  const currentRealPage = (() => {
    if (currentStreamItem && !isVirtualEndReaderItem(currentStreamItem)) {
      return currentStreamItem.streamRealPage;
    }
    if (activeSegment) {
      return Math.max(0, activeSegment.start + activeSegment.count - 1);
    }
    return Math.max(0, Math.min(currentPage, Math.max(0, pages.length - 1)));
  })();

  const nextArchiveLookupId = activeSegment?.archiveId ?? activeArchiveId ?? sourceArchiveId;
  const currentPageType = currentStreamItem?.type ?? null;
  const isCurrentHtmlPage = isHtmlReaderItem(currentStreamItem);
  const isCollectionEndPage = isVirtualEndReaderItem(currentStreamItem);
  const activeSegmentLastRealPage =
    activeSegment && activeSegment.count > 0 ? activeSegment.start + activeSegment.count - 1 : -1;
  const isCurrentOrTailHtmlPage =
    isCurrentHtmlPage ||
    (isCollectionEndPage && activeSegmentLastRealPage >= 0 && pages[activeSegmentLastRealPage]?.type === 'html');
  const isHtmlSpreadView = readingMode !== 'webtoon' && doublePageMode && isCurrentHtmlPage;
  const totalPages = streamPages.length;
  const sliderCurrentPage = seamlessEnabled ? activeLocalPage : currentPage;
  const sliderTotalPages = seamlessEnabled && activeSegment ? activeSegment.count : totalPages;

  return {
    currentStreamItem,
    activeSegment,
    activeArchiveId,
    activeLocalPage,
    currentRealPage,
    nextArchiveLookupId,
    currentPageType,
    isCurrentHtmlPage,
    isCollectionEndPage,
    activeSegmentLastRealPage,
    isCurrentOrTailHtmlPage,
    isHtmlSpreadView,
    sliderCurrentPage,
    sliderTotalPages,
  };
}
