'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useWindowSize } from '@/hooks/common-hooks';

export const DEFAULT_SCROLLABLE_CARD_COVER_ASPECT_RATIO = 3 / 4;

export function getScrollableCardWidth(viewportWidth: number): number {
  if (viewportWidth < 640) return 128;
  if (viewportWidth < 768) return 144;
  if (viewportWidth < 1024) return 160;
  if (viewportWidth < 1280) return 176;
  return 192;
}

export function useScrollableCardCoverHeight(itemKeys: string[]) {
  const { width } = useWindowSize();
  const [aspectRatios, setAspectRatios] = useState<Record<string, number>>({});

  useEffect(() => {
    setAspectRatios((current) => {
      const next: Record<string, number> = {};
      for (const key of itemKeys) {
        if (current[key] != null) {
          next[key] = current[key];
        }
      }

      const currentKeys = Object.keys(current);
      if (currentKeys.length !== Object.keys(next).length) {
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

  const reportAspectRatio = useCallback((key: string, aspectRatio: number) => {
    const normalized = Number.isFinite(aspectRatio) && aspectRatio > 0
      ? aspectRatio
      : DEFAULT_SCROLLABLE_CARD_COVER_ASPECT_RATIO;

    setAspectRatios((current) => {
      if (Math.abs((current[key] ?? DEFAULT_SCROLLABLE_CARD_COVER_ASPECT_RATIO) - normalized) < 0.001) {
        return current;
      }
      return {
        ...current,
        [key]: normalized,
      };
    });
  }, []);

  const sharedCoverHeight = useMemo(() => {
    if (itemKeys.length === 0) return undefined;

    const itemWidth = getScrollableCardWidth(width);
    const knownAspectRatios = itemKeys
      .map((key) => aspectRatios[key])
      .filter((aspectRatio): aspectRatio is number => Number.isFinite(aspectRatio) && aspectRatio > 0);

    if (knownAspectRatios.length === 0) return undefined;

    let maxHeight = 0;

    for (const aspectRatio of knownAspectRatios) {
      maxHeight = Math.max(maxHeight, itemWidth / aspectRatio);
    }

    return Math.round(maxHeight);
  }, [aspectRatios, itemKeys, width]);

  return {
    reportAspectRatio,
    sharedCoverHeight,
  };
}
