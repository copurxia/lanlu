import type { ReaderContentItemType } from '@/features/reader/domain/models/reader-item';

export type ReaderProgressLaneId = 'book' | 'video-left' | 'video-right' | (string & {});

export type ReaderProgressLaneSpec = {
  id: ReaderProgressLaneId;
  kind: 'book' | 'video';
  label: string;
  videoPageIndex?: number;
};

export type BuildReaderProgressLaneSpecsInput = {
  readingMode: 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';
  doublePageMode: boolean;
  splitCoverMode: boolean;
  isHtmlSpreadView: boolean;
  currentPage: number;
  pagesLength: number;
  getPageType: (pageIndex: number) => ReaderContentItemType | null;
  includeBookLane?: boolean;
};

export function buildReaderProgressLaneSpecs({
  readingMode,
  doublePageMode,
  splitCoverMode,
  isHtmlSpreadView,
  currentPage,
  pagesLength,
  getPageType,
  includeBookLane = true,
}: BuildReaderProgressLaneSpecsInput): ReaderProgressLaneSpec[] {
  const specs: ReaderProgressLaneSpec[] = [];

  const tryAddVideoLane = (id: ReaderProgressLaneId, label: string, pageIndex: number) => {
    if (pageIndex < 0 || pageIndex >= pagesLength) return;
    if (getPageType(pageIndex) !== 'video') return;
    specs.push({
      id,
      kind: 'video',
      label,
      videoPageIndex: pageIndex,
    });
  };

  if (readingMode === 'webtoon') {
    tryAddVideoLane('video-left', 'Video', currentPage);
  } else {
    const leftPage = currentPage;
    tryAddVideoLane('video-left', 'Video L', leftPage);

    const hasRightPage =
      doublePageMode &&
      !isHtmlSpreadView &&
      !(splitCoverMode && currentPage === 0) &&
      currentPage + 1 < pagesLength;

    if (hasRightPage) {
      tryAddVideoLane('video-right', 'Video R', currentPage + 1);
    }
  }

  if (includeBookLane) {
    specs.push({
      id: 'book',
      kind: 'book',
      label: 'Book',
    });
  }

  return specs;
}
