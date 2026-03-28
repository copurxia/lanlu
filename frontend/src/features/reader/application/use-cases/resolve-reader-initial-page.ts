import type { ReaderItemType } from '@/features/reader/domain/models/reader-item';
import { supportsSplitCoverProgressAdjustment } from '@/features/reader/domain/rules/reader-item-capabilities';

export type ResolveReaderInitialPageInput = {
  pageParam?: string | null;
  pagesLength: number;
  doublePageMode: boolean;
  splitCoverMode: boolean;
  initialPageType?: ReaderItemType | null;
};

export type ResolveReaderInitialPageResult = {
  initialPage: number;
  pendingUrlPageRaw: number | null;
  pendingUrlPageIndex: number | null;
  pendingWebtoonScrollEdge: 'top' | 'bottom' | null;
};

function clampPage(page: number, pagesLength: number) {
  return Math.max(0, Math.min(page, Math.max(0, pagesLength - 1)));
}

function adjustRestoredPageForSplitCover(
  page: number,
  doublePageMode: boolean,
  splitCoverMode: boolean,
  pageType?: ReaderItemType | null
) {
  if (!doublePageMode || !splitCoverMode || !supportsSplitCoverProgressAdjustment(pageType)) {
    return page;
  }

  if (page <= 1) return page;
  if (page === 2) return 1;
  return Math.max(0, page - 2);
}

export function resolveReaderInitialPage({
  pageParam,
  pagesLength,
  doublePageMode,
  splitCoverMode,
  initialPageType,
}: ResolveReaderInitialPageInput): ResolveReaderInitialPageResult {
  let initialPage = 0;
  let pendingUrlPageRaw: number | null = null;
  let pendingUrlPageIndex: number | null = null;
  let pendingWebtoonScrollEdge: 'top' | 'bottom' | null = null;

  if (pageParam) {
    const urlPage = Number.parseInt(pageParam, 10);
    if (!Number.isNaN(urlPage) && urlPage > 0) {
      pendingUrlPageRaw = urlPage;
      pendingUrlPageIndex = urlPage - 1;

      if (urlPage - 1 >= 0 && urlPage - 1 < pagesLength) {
        initialPage = urlPage - 1;
      } else {
        initialPage = Math.max(0, pagesLength - 1);
        pendingWebtoonScrollEdge = 'bottom';
      }
    }
  }

  initialPage = adjustRestoredPageForSplitCover(
    clampPage(initialPage, pagesLength),
    doublePageMode,
    splitCoverMode,
    initialPageType
  );

  return {
    initialPage,
    pendingUrlPageRaw,
    pendingUrlPageIndex,
    pendingWebtoonScrollEdge,
  };
}
