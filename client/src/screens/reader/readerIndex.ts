export type IndexableReaderItem = {
  progressPage: number;
  pages: Array<{ pageNumber: number }>;
};

/** Index of the paged reader item that shows `page`, or the first item. */
export function readerItemIndexForPage(
  items: IndexableReaderItem[],
  page: number,
): number {
  if (!items.length) return 0;
  const index = items.findIndex(
    item =>
      item.progressPage === page ||
      item.pages.some(itemPage => itemPage.pageNumber === page),
  );
  return index < 0 ? 0 : index;
}

/** Index of the webtoon item for `page`, clamped to the available items. */
export function webtoonIndexForPage(page: number, itemCount: number): number {
  if (itemCount <= 0) return 0;
  return Math.max(0, Math.min(page - 1, itemCount - 1));
}
