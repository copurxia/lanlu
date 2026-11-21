import {useCallback, useRef} from 'react';
import type {NativeScrollEvent, NativeSyntheticEvent} from 'react-native';

import {perfMark} from './perf';

type ScrollSample = {
  active: boolean;
  startedAt: number;
  lastAt: number;
  samples: number;
  totalGapMs: number;
  maxGapMs: number;
  slowFrames: number;
  offsetY: number;
};

/**
 * Records one summary per drag gesture: duration, sampled frame gaps and the
 * number of gaps over 50 ms. Attach the returned handlers to a ScrollView,
 * FlatList or SectionList; the overhead is two Date.now calls per scroll event.
 */
export function useScrollPerf(surface: string) {
  const sample = useRef<ScrollSample>({
    active: false,
    startedAt: 0,
    lastAt: 0,
    samples: 0,
    totalGapMs: 0,
    maxGapMs: 0,
    slowFrames: 0,
    offsetY: 0,
  });

  const onScrollBeginDrag = useCallback(() => {
    const now = Date.now();
    sample.current = {
      active: true,
      startedAt: now,
      lastAt: now,
      samples: 0,
      totalGapMs: 0,
      maxGapMs: 0,
      slowFrames: 0,
      offsetY: 0,
    };
  }, []);

  const onScroll = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      const current = sample.current;
      if (!current.active) return;
      const now = Date.now();
      const gap = now - current.lastAt;
      if (gap > 0) {
        current.samples += 1;
        current.totalGapMs += gap;
        current.maxGapMs = Math.max(current.maxGapMs, gap);
        if (gap > 50) current.slowFrames += 1;
      }
      current.lastAt = now;
      current.offsetY = event.nativeEvent.contentOffset?.y || 0;
    },
    [],
  );

  const endDrag = useCallback(() => {
    const current = sample.current;
    if (!current.active) return;
    current.active = false;
    const durationMs = Date.now() - current.startedAt;
    if (durationMs < 60 && current.samples < 2) return;
    perfMark(`scroll.${surface}`, {
      durationMs,
      samples: current.samples,
      avgGapMs: current.samples
        ? Math.round(current.totalGapMs / current.samples)
        : 0,
      maxGapMs: current.maxGapMs,
      slowFrames: current.slowFrames,
      offsetY: Math.round(current.offsetY),
    });
  }, [surface]);

  return {
    onScroll,
    onScrollBeginDrag,
    onScrollEndDrag: endDrag,
    onMomentumScrollEnd: endDrag,
    scrollEventThrottle: 16,
  };
}
