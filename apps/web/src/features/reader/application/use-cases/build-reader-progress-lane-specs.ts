import type { ReaderContentItemType } from '@/features/reader/domain/models/reader-item';

export type ReaderProgressLaneId =
  | 'book'
  | 'video-left'
  | 'video-right'
  | 'audio-left'
  | 'audio-right'
  | (string & {});

export type ReaderProgressLaneSpec = {
  id: ReaderProgressLaneId;
  kind: 'book' | 'video' | 'audio';
  label: string;
  mediaPageIndex?: number;
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

  const tryAddMediaLane = (id: ReaderProgressLaneId, pageIndex: number, shortLabel: string) => {
    if (pageIndex < 0 || pageIndex >= pagesLength) return;
    const pageType = getPageType(pageIndex);
    if (pageType !== 'video' && pageType !== 'audio') return;
    const kind = pageType === 'audio' ? 'audio' : 'video';
    const laneLabel = (kind === 'audio' ? `Audio ${shortLabel}` : `Video ${shortLabel}`).trim();
    specs.push({
      id,
      kind,
      label: laneLabel,
      mediaPageIndex: pageIndex,
    });
  };

  if (readingMode === 'webtoon') {
    const pageType = getPageType(currentPage);
    if (pageType === 'audio') {
      tryAddMediaLane('audio-left', currentPage, '');
    } else {
      tryAddMediaLane('video-left', currentPage, '');
    }
  } else {
    const leftPage = currentPage;
    const leftType = getPageType(leftPage);
    if (leftType === 'audio') {
      tryAddMediaLane('audio-left', leftPage, 'L');
    } else {
      tryAddMediaLane('video-left', leftPage, 'L');
    }

    const hasRightPage =
      doublePageMode &&
      !isHtmlSpreadView &&
      !(splitCoverMode && currentPage === 0) &&
      currentPage + 1 < pagesLength;

    if (hasRightPage) {
      const rightPage = currentPage + 1;
      const rightType = getPageType(rightPage);
      if (rightType === 'audio') {
        tryAddMediaLane('audio-right', rightPage, 'R');
      } else {
        tryAddMediaLane('video-right', rightPage, 'R');
      }
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
