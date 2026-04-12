'use client';

import { useMemo } from 'react';

export type VirtualMasonryLayoutItem<T> = {
  item: T;
  index: number;
  key: string;
  top: number;
  left: number;
  width: number;
  height: number;
};

type BuildVirtualMasonryLayoutInput<T> = {
  items: T[];
  containerWidth: number;
  gap: number;
  getColumns: (containerWidth: number) => number;
  getItemKey: (item: T, index: number) => string;
  getItemHeight: (item: T, index: number, itemWidth: number) => number;
};

type BuildVirtualMasonryLayoutOutput<T> = {
  layoutItems: VirtualMasonryLayoutItem<T>[];
  totalHeight: number;
  columns: number;
  itemWidth: number;
};

type BuildVisibleItemsInput<T> = {
  layoutItems: VirtualMasonryLayoutItem<T>[];
  scrollTop: number;
  viewportHeight: number;
  overscan: number;
};

export function buildVirtualMasonryLayout<T>(
  input: BuildVirtualMasonryLayoutInput<T>,
): BuildVirtualMasonryLayoutOutput<T> {
  const { items, containerWidth, gap, getColumns, getItemKey, getItemHeight } = input;
  const columns = Math.max(1, getColumns(containerWidth));
  const totalGaps = gap * Math.max(0, columns - 1);
  const itemWidth = Math.max(0, Math.floor((containerWidth - totalGaps) / columns));
  if (!items.length || itemWidth <= 0) {
    return { layoutItems: [], totalHeight: 0, columns, itemWidth };
  }

  const columnHeights = Array.from({ length: columns }, () => 0);
  const layoutItems: VirtualMasonryLayoutItem<T>[] = [];

  for (let index = 0; index < items.length; index += 1) {
    const item = items[index];
    let column = 0;
    for (let i = 1; i < columnHeights.length; i += 1) {
      if (columnHeights[i] < columnHeights[column]) column = i;
    }

    const height = Math.max(1, Math.round(getItemHeight(item, index, itemWidth)));
    const top = columnHeights[column];
    const left = column * (itemWidth + gap);
    const key = getItemKey(item, index);
    layoutItems.push({ item, index, key, top, left, width: itemWidth, height });
    columnHeights[column] += height + gap;
  }

  const totalHeight = Math.max(0, ...columnHeights) - gap;
  return { layoutItems, totalHeight, columns, itemWidth };
}

export function buildVisibleMasonryItems<T>(
  input: BuildVisibleItemsInput<T>,
): VirtualMasonryLayoutItem<T>[] {
  const { layoutItems, scrollTop, viewportHeight, overscan } = input;
  if (!layoutItems.length) return [];
  if (viewportHeight <= 0) return layoutItems;

  const minTop = Math.max(0, scrollTop - overscan);
  const maxBottom = scrollTop + viewportHeight + overscan;
  return layoutItems.filter(
    (item) => item.top + item.height >= minTop && item.top <= maxBottom,
  );
}

type UseVirtualMasonryLayoutInput<T> = {
  items: T[];
  containerWidth: number;
  scrollTop: number;
  viewportHeight: number;
  gap?: number;
  overscan?: number;
  getColumns: (containerWidth: number) => number;
  getItemKey: (item: T, index: number) => string;
  getItemHeight: (item: T, index: number, itemWidth: number) => number;
};

type UseVirtualMasonryLayoutOutput<T> = BuildVirtualMasonryLayoutOutput<T> & {
  visibleItems: VirtualMasonryLayoutItem<T>[];
};

export function useVirtualMasonryLayout<T>(
  input: UseVirtualMasonryLayoutInput<T>,
): UseVirtualMasonryLayoutOutput<T> {
  const {
    items,
    containerWidth,
    scrollTop,
    viewportHeight,
    gap = 8,
    overscan = 480,
    getColumns,
    getItemKey,
    getItemHeight,
  } = input;

  const layout = useMemo(
    () => buildVirtualMasonryLayout({
      items,
      containerWidth,
      gap,
      getColumns,
      getItemKey,
      getItemHeight,
    }),
    [containerWidth, gap, getColumns, getItemHeight, getItemKey, items],
  );

  const visibleItems = useMemo(
    () => buildVisibleMasonryItems({
      layoutItems: layout.layoutItems,
      scrollTop,
      viewportHeight,
      overscan,
    }),
    [layout.layoutItems, overscan, scrollTop, viewportHeight],
  );

  return {
    ...layout,
    visibleItems,
  };
}
