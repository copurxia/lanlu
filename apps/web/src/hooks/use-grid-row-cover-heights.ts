'use client';

import * as React from 'react';
import { useGridColumnCount } from '@/hooks/common-hooks';

const DEFAULT_COVER_ASPECT_RATIO = 3 / 4;
const GRID_GAP_PX = 16;

function normalizeAspectRatio(value?: number): number {
  if (!Number.isFinite(value) || (value ?? 0) <= 0) {
    return DEFAULT_COVER_ASPECT_RATIO;
  }
  return value as number;
}

export function useGridRowCoverHeights(itemKeys: string[]) {
  const columnCount = useGridColumnCount();
  const containerRef = React.useRef<HTMLDivElement | null>(null);
  const [containerWidth, setContainerWidth] = React.useState(0);
  const [aspectRatios, setAspectRatios] = React.useState<Record<string, number>>({});

  React.useEffect(() => {
    const element = containerRef.current;
    if (!element) return;

    const updateWidth = () => {
      const nextWidth = element.getBoundingClientRect().width;
      setContainerWidth((current) => (Math.abs(current - nextWidth) < 0.5 ? current : nextWidth));
    };

    updateWidth();

    const observer = new ResizeObserver(() => {
      updateWidth();
    });

    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  React.useEffect(() => {
    setAspectRatios((current) => {
      const next: Record<string, number> = {};

      for (const key of itemKeys) {
        if (current[key] != null) {
          next[key] = current[key];
        }
      }

      const currentKeys = Object.keys(current);
      const nextKeys = Object.keys(next);
      if (currentKeys.length !== nextKeys.length) {
        return next;
      }

      for (const key of currentKeys) {
        if (!(key in next)) {
          return next;
        }
      }

      return current;
    });
  }, [itemKeys]);

  const reportCoverAspectRatio = React.useCallback((key: string, aspectRatio: number) => {
    const normalized = normalizeAspectRatio(aspectRatio);
    setAspectRatios((current) => {
      if (Math.abs((current[key] ?? DEFAULT_COVER_ASPECT_RATIO) - normalized) < 0.001) {
        return current;
      }
      return {
        ...current,
        [key]: normalized,
      };
    });
  }, []);

  const coverHeights = React.useMemo(() => {
    if (itemKeys.length === 0 || containerWidth <= 0 || columnCount <= 0) {
      return {} as Record<string, number>;
    }

    const totalGapWidth = GRID_GAP_PX * Math.max(columnCount - 1, 0);
    const itemWidth = Math.max((containerWidth - totalGapWidth) / columnCount, 0);
    if (itemWidth <= 0) {
      return {} as Record<string, number>;
    }

    const nextHeights: Record<string, number> = {};

    for (let start = 0; start < itemKeys.length; start += columnCount) {
      const rowKeys = itemKeys.slice(start, start + columnCount);
      let rowMaxHeight = 0;

      for (const key of rowKeys) {
        const ratio = normalizeAspectRatio(aspectRatios[key]);
        rowMaxHeight = Math.max(rowMaxHeight, itemWidth / ratio);
      }

      const normalizedHeight = Math.round(rowMaxHeight);
      for (const key of rowKeys) {
        nextHeights[key] = normalizedHeight;
      }
    }

    return nextHeights;
  }, [aspectRatios, columnCount, containerWidth, itemKeys]);

  return {
    containerRef,
    coverHeights,
    reportCoverAspectRatio,
  };
}
