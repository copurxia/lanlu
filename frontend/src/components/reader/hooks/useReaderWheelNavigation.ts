'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { toast } from 'sonner';
import type { PageInfo } from '@/lib/services/archive-service';

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

  const scrollLongPageContainer = useCallback((target: 'top' | 'bottom') => {
    const startedAt = performance.now();
    let lastScrollHeight = 0;

    const tick = () => {
      const el = document.querySelector('.long-page-scroll-container') as HTMLElement | null;
      if (!el) {
        if (performance.now() - startedAt < 2000) requestAnimationFrame(tick);
        return;
      }

      if (target === 'top') {
        el.scrollTop = 0;
        return;
      }

      // For long images, scrollHeight often grows after the image finishes decoding.
      // Keep nudging to bottom until scrollHeight stabilizes (or timeout).
      const { scrollHeight, clientHeight } = el;
      el.scrollTop = scrollHeight;

      const canScroll = scrollHeight > clientHeight + 1;
      const changed = scrollHeight !== lastScrollHeight;
      lastScrollHeight = scrollHeight;

      if ((changed || !canScroll) && performance.now() - startedAt < 2000) {
        requestAnimationFrame(tick);
      }
    };

    requestAnimationFrame(tick);
  }, []);

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

      const targetEl = e.target as HTMLElement | null;

      // Long image page uses an internal scroll container. Like HTML pages, when the user keeps scrolling
      // near the top/bottom edges, start a countdown to flip pages.
      const longPageContainer = targetEl?.closest?.('.long-page-scroll-container') as HTMLElement | null;
      if (longPageContainer) {
        const scrollTop = longPageContainer.scrollTop;
        const scrollHeight = longPageContainer.scrollHeight;
        const clientHeight = longPageContainer.clientHeight;
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
                scrollLongPageContainer('bottom');
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
              scrollLongPageContainer('top');
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

        // Not at edges: allow normal scrolling inside the container (no wheel-flip).
        return;
      }

      const isHtmlPage = pages[currentPage]?.type === 'html';

      if (isHtmlPage) {
        const htmlContainer = targetEl?.closest?.('.html-content-container') as HTMLElement | null;

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
      scrollLongPageContainer,
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
