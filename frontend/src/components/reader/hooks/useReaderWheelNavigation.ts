'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { toast } from 'sonner';
import type { PageInfo } from '@/lib/archive-service';

const COUNTDOWN_DURATION = 3;

export function useReaderWheelNavigation({
  pages,
  currentPage,
  readingMode,
  autoHideEnabled,
  showToolbar,
  hideToolbar,
  onPrevPage,
  onNextPage,
}: {
  pages: PageInfo[];
  currentPage: number;
  readingMode: 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';
  autoHideEnabled: boolean;
  showToolbar: boolean;
  hideToolbar: () => void;
  onPrevPage: () => void;
  onNextPage: () => void;
}) {
  const [showAutoNextCountdown, setShowAutoNextCountdown] = useState(false);
  const countdownSecondsRef = useRef(COUNTDOWN_DURATION);
  const countdownTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const countdownToastId = useRef<string | number | null>(null);

  const clearCountdown = useCallback(() => {
    if (countdownTimeoutRef.current) {
      clearInterval(countdownTimeoutRef.current);
      countdownTimeoutRef.current = null;
    }
    if (countdownToastId.current !== null) {
      toast.dismiss(countdownToastId.current);
      countdownToastId.current = null;
    }
    setShowAutoNextCountdown(false);
    countdownSecondsRef.current = COUNTDOWN_DURATION;
  }, []);

  useEffect(() => {
    if (readingMode === 'webtoon' && showAutoNextCountdown) {
      clearCountdown();
    }
  }, [readingMode, showAutoNextCountdown, clearCountdown]);

  useEffect(() => {
    return () => {
      clearCountdown();
    };
  }, [clearCountdown]);

  const handleWheel = useCallback(
    (e: WheelEvent) => {
      if (e.target instanceof HTMLInputElement) return;

      if (autoHideEnabled && showToolbar) {
        hideToolbar();
      }

      if (readingMode === 'webtoon') {
        if (showAutoNextCountdown) {
          clearCountdown();
        }
        return;
      }

      const isHtmlPage = pages[currentPage]?.type === 'html';

      if (isHtmlPage) {
        const target = e.target as HTMLElement;
        const htmlContainer = target.closest('.html-content-container') as HTMLElement | null;

        if (htmlContainer) {
          const scrollTop = htmlContainer.scrollTop;
          const scrollHeight = htmlContainer.scrollHeight;
          const clientHeight = htmlContainer.clientHeight;
          const isAtTop = scrollTop <= 5;
          const isNearTop = scrollTop <= 150;
          const isNearBottom = scrollTop >= scrollHeight - clientHeight - 150;
          const isAtBottom = scrollTop >= scrollHeight - clientHeight - 5;

          const deltaY = e.deltaY;

          if (showAutoNextCountdown) {
            e.preventDefault();
            if (!((isAtTop && deltaY < 0) || (isAtBottom && deltaY > 0))) {
              clearCountdown();
            }
            return;
          }

          if (isNearTop && deltaY < 0) {
            e.preventDefault();
            setShowAutoNextCountdown(true);
            countdownSecondsRef.current = COUNTDOWN_DURATION;

            countdownToastId.current = toast.loading(`即将跳转到上一页（${COUNTDOWN_DURATION}秒后）`, {
              duration: COUNTDOWN_DURATION * 1000,
              action: { label: '取消', onClick: () => clearCountdown() },
            });

            countdownTimeoutRef.current = setInterval(() => {
              countdownSecondsRef.current -= 1;
              if (countdownSecondsRef.current <= 0) {
                clearCountdown();
                onPrevPage();
                setTimeout(() => {
                  const el = document.querySelector('.html-content-container') as HTMLElement | null;
                  if (el) el.scrollTop = el.scrollHeight;
                }, 100);
                return;
              }

              if (countdownToastId.current !== null) {
                toast.loading(`即将跳转到上一页（${countdownSecondsRef.current}秒后）`, {
                  id: countdownToastId.current,
                  duration: countdownSecondsRef.current * 1000,
                  action: { label: '取消', onClick: () => clearCountdown() },
                });
              }
            }, 1000);
          } else if (isNearBottom && deltaY > 0) {
            e.preventDefault();
            setShowAutoNextCountdown(true);
            countdownSecondsRef.current = COUNTDOWN_DURATION;

            countdownToastId.current = toast.loading(`即将跳转到下一页（${COUNTDOWN_DURATION}秒后）`, {
              duration: COUNTDOWN_DURATION * 1000,
              action: { label: '取消', onClick: () => clearCountdown() },
            });

            countdownTimeoutRef.current = setInterval(() => {
              countdownSecondsRef.current -= 1;
              if (countdownSecondsRef.current <= 0) {
                clearCountdown();
                onNextPage();
                setTimeout(() => {
                  const el = document.querySelector('.html-content-container') as HTMLElement | null;
                  if (el) el.scrollTop = 0;
                }, 100);
                return;
              }

              if (countdownToastId.current !== null) {
                toast.loading(`即将跳转到下一页（${countdownSecondsRef.current}秒后）`, {
                  id: countdownToastId.current,
                  duration: countdownSecondsRef.current * 1000,
                  action: { label: '取消', onClick: () => clearCountdown() },
                });
              }
            }, 1000);
          }

          return;
        }
      }

      const deltaX = e.deltaX;
      const deltaY = e.deltaY;

      if (readingMode === 'single-rtl') {
        if (deltaX > 0 || deltaY > 0) {
          onPrevPage();
        } else if (deltaX < 0 || deltaY < 0) {
          onNextPage();
        }
      } else if (readingMode === 'single-ttb') {
        if (deltaY > 0) {
          onNextPage();
        } else if (deltaY < 0) {
          onPrevPage();
        }
      } else {
        if (deltaX > 0 || deltaY > 0) {
          onNextPage();
        } else if (deltaX < 0 || deltaY < 0) {
          onPrevPage();
        }
      }
    },
    [
      autoHideEnabled,
      showToolbar,
      hideToolbar,
      readingMode,
      showAutoNextCountdown,
      clearCountdown,
      pages,
      currentPage,
      onPrevPage,
      onNextPage,
    ]
  );

  useEffect(() => {
    window.addEventListener('wheel', handleWheel, { passive: false });
    return () => {
      window.removeEventListener('wheel', handleWheel);
    };
  }, [handleWheel]);
}
