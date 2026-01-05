'use client';

import { useLocalStorage } from './common-hooks';
import { useCallback } from 'react';

export type ReadingMode = 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';

/**
 * 阅读模式Hook - 自动同步localStorage
 * 包含条漫模式切换时自动关闭双页模式的逻辑
 */
export function useReadingMode() {
  const [readingMode, setReadingMode] = useLocalStorage<ReadingMode>('reader-reading-mode', 'single-ltr');
  const [doublePageMode, setDoublePageMode] = useLocalStorage<boolean>('reader-double-page-mode', false);

  const toggleReadingMode = useCallback(() => {
    setReadingMode(prev => {
      const modes: ReadingMode[] = ['single-ltr', 'single-rtl', 'single-ttb', 'webtoon'];
      const currentIndex = modes.indexOf(prev);
      const newMode = modes[(currentIndex + 1) % modes.length];

      // 如果切换到条漫模式，自动关闭双页模式
      if (newMode === 'webtoon' && doublePageMode) {
        setDoublePageMode(false);
      }

      return newMode;
    });
  }, [setReadingMode, doublePageMode, setDoublePageMode]);

  return [readingMode, toggleReadingMode] as const;
}

/**
 * 其他阅读设置hooks - 基于useLocalStorage的类型化版本
 */
export const useDoublePageMode = () => useLocalStorage<boolean>('reader-double-page-mode', false);
export const useAutoPlayMode = () => useLocalStorage<boolean>('reader-auto-play-mode', false);
export const useAutoPlayInterval = () => useLocalStorage<number>('reader-auto-play-interval', 3);
export const useSplitCoverMode = () => useLocalStorage<boolean>('reader-split-cover-mode', false);
export const useFullscreenMode = () => useLocalStorage<boolean>('reader-fullscreen-mode', false);
export const useDoubleTapZoom = () => useLocalStorage<boolean>('reader-double-tap-zoom', false);
export const useAutoHideEnabled = () => useLocalStorage<boolean>('reader-auto-hide-enabled', false);
export const useTapTurnPageEnabled = () => useLocalStorage<boolean>('reader-tap-turn-page-enabled', false);
