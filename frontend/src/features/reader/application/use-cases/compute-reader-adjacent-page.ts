export type ComputeReaderAdjacentPageInput = {
  direction: 'prev' | 'next';
  currentPage: number;
  totalPages: number;
  doublePageMode: boolean;
  splitCoverMode: boolean;
  isHtmlSpreadView: boolean;
};

export function computeReaderAdjacentPage({
  direction,
  currentPage,
  totalPages,
  doublePageMode,
  splitCoverMode,
  isHtmlSpreadView,
}: ComputeReaderAdjacentPageInput): number | null {
  if (direction === 'prev') {
    if (currentPage <= 0) return null;
    if (isHtmlSpreadView) return currentPage - 1;

    if (doublePageMode && splitCoverMode) {
      if (currentPage === 1) return 0;
      if (currentPage === 2) return 1;
      if (currentPage > 2) return currentPage - 2;
      return null;
    }

    if (doublePageMode) {
      return Math.max(0, currentPage - 2);
    }

    return currentPage - 1;
  }

  if (currentPage >= totalPages - 1) return null;
  if (isHtmlSpreadView) return currentPage + 1;

  if (doublePageMode && splitCoverMode) {
    if (currentPage === 0) return Math.min(1, totalPages - 1);
    if (currentPage === 1) return Math.min(3, totalPages - 1);
    return Math.min(currentPage + 2, totalPages - 1);
  }

  if (doublePageMode) {
    return currentPage + 2 < totalPages ? currentPage + 2 : totalPages - 1;
  }

  return currentPage + 1;
}
