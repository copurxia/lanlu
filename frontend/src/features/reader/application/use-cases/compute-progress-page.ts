import { supportsSplitCoverProgressAdjustment } from "@/features/reader/domain/rules/reader-item-capabilities";
import type { ReaderItemType } from "@/features/reader/domain/models/reader-item";

export type ComputeProgressPageInput = {
  currentPage: number;
  pagesLength: number;
  doublePageMode: boolean;
  splitCoverMode: boolean;
  currentItemType?: ReaderItemType | null;
};

export function clampReaderPageIndex(currentPage: number, pagesLength: number): number {
  return Math.max(0, Math.min(currentPage, Math.max(0, pagesLength - 1)));
}

export function computeProgressPage({
  currentPage,
  pagesLength,
  doublePageMode,
  splitCoverMode,
  currentItemType,
}: ComputeProgressPageInput): number {
  const clampedPage = clampReaderPageIndex(currentPage, pagesLength);

  if (!doublePageMode || !splitCoverMode || !supportsSplitCoverProgressAdjustment(currentItemType)) {
    return clampedPage;
  }

  if (clampedPage === 0) return 0;
  if (clampedPage === 1) return 2;
  return clampedPage + 1;
}
