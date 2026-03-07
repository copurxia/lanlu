import type { ReaderItemType, ReaderSegment } from '@/features/reader/domain/models/reader-item';

export type ComputeCollectionEndReturnPageInput = {
  activeSegment: ReaderSegment | null;
  readingMode: 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';
  doublePageMode: boolean;
  splitCoverMode: boolean;
  tailPageType?: ReaderItemType | null;
};

export type ComputeCollectionEndNextActionInput = {
  seamlessEnabled: boolean;
  isTailCollectionEndPage: boolean;
  currentPage: number;
  totalPages: number;
  hasNextArchive: boolean;
};

export type CollectionEndNextAction =
  | { type: 'append' }
  | { type: 'advance'; page: number }
  | { type: 'jump-next-chapter' }
  | { type: 'none' };

export type PrevBoundaryAction =
  | { type: 'jump-prev-chapter' }
  | { type: 'none' };

export function computeCollectionEndReturnRealPage({
  activeSegment,
  readingMode,
  doublePageMode,
  splitCoverMode,
  tailPageType,
}: ComputeCollectionEndReturnPageInput): number | null {
  if (!activeSegment || activeSegment.count <= 0) return null;

  let targetReal = activeSegment.start + activeSegment.count - 1;
  if (readingMode !== 'webtoon' && doublePageMode && tailPageType !== 'html') {
    const segmentLength = activeSegment.count;
    if (splitCoverMode) {
      if (segmentLength % 2 === 1 && segmentLength >= 2) targetReal -= 1;
    } else if (segmentLength % 2 === 0 && segmentLength >= 2) {
      targetReal -= 1;
    }
  }

  return Math.max(0, targetReal);
}

export function computeCollectionEndNextAction({
  seamlessEnabled,
  isTailCollectionEndPage,
  currentPage,
  totalPages,
  hasNextArchive,
}: ComputeCollectionEndNextActionInput): CollectionEndNextAction {
  if (seamlessEnabled) {
    if (isTailCollectionEndPage) return { type: 'append' };
    if (currentPage < totalPages - 1) return { type: 'advance', page: currentPage + 1 };
    return { type: 'none' };
  }

  if (hasNextArchive) return { type: 'jump-next-chapter' };
  return { type: 'none' };
}

export function computePrevBoundaryAction({
  currentPage,
  hasTankoubonContext,
  hasPrevArchive,
  seamlessEnabled,
}: {
  currentPage: number;
  hasTankoubonContext: boolean;
  hasPrevArchive: boolean;
  seamlessEnabled: boolean;
}): PrevBoundaryAction {
  if (currentPage <= 0 && hasTankoubonContext && hasPrevArchive && !seamlessEnabled) {
    return { type: 'jump-prev-chapter' };
  }
  return { type: 'none' };
}
