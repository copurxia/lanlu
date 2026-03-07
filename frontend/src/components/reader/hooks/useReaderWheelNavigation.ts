'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import type React from 'react';
import { toast } from 'sonner';
import type { PageInfo } from '@/lib/services/archive-service';
import { getHtmlSpreadMetrics, getHtmlSpreadSlotOffset, stepHtmlSpread } from '@/components/reader/utils/html-spread';

const COUNTDOWN_DURATION = 3;
const EDGE_THRESHOLD_PX = 8;
const SPREAD_WHEEL_TRIGGER = 36;
const SPREAD_WHEEL_LOCK_MS = 380;

function isScrollable(el: HTMLElement | null): el is HTMLElement {
  if (!el) return false;
  return el.scrollHeight > el.clientHeight + 1 || el.scrollWidth > el.clientWidth + 1;
}

function resolveActiveHtmlContainer(targetEl: HTMLElement | null): HTMLElement | null {
  const inner = targetEl?.closest?.('.html-content-container') as HTMLElement | null;
  const outer = targetEl?.closest?.('.reader-html-page-container') as HTMLElement | null;

  if (outer?.classList.contains('reader-html-spread-container')) return outer;
  if (isScrollable(inner)) return inner;
  if (isScrollable(outer)) return outer;
  return inner || outer;
}

export function useReaderWheelNavigation({
  pages,
  currentPage,
  readingMode,
  autoHideEnabled,
  showToolbar,
  hideToolbar,
  onPrevPage,
  onNextPage,
  webtoonContainerRef,
  isCollectionEndPage,
  onWebtoonStartPrev,
  onWebtoonEndNext,
}: {
  pages: PageInfo[];
  currentPage: number;
  readingMode: 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';
  autoHideEnabled: boolean;
  showToolbar: boolean;
  hideToolbar: () => void;
  onPrevPage: () => void;
  onNextPage: () => void;
  webtoonContainerRef?: React.RefObject<HTMLDivElement | null>;
  isCollectionEndPage?: boolean;
  onWebtoonStartPrev?: () => void;
  onWebtoonEndNext?: () => void;
}) {
  const [showAutoNextCountdown, setShowAutoNextCountdown] = useState(false);
  const countdownSecondsRef = useRef(COUNTDOWN_DURATION);
  const countdownTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const countdownToastId = useRef<string | number | null>(null);
  const spreadWheelAccumRef = useRef(0);
  const spreadWheelLockUntilRef = useRef(0);

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
    spreadWheelAccumRef.current = 0;
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

      const targetEl = e.target as HTMLElement | null;
      if (targetEl?.closest?.('[data-reader-overlay="true"]')) return;

      if (autoHideEnabled && showToolbar) {
        hideToolbar();
      }

      if (readingMode === 'webtoon') {
        if (showAutoNextCountdown) clearCountdown();

        const container = webtoonContainerRef?.current;
        if (!container) return;
        const atTop = container.scrollTop <= 5;
        const atBottom = container.scrollTop + container.clientHeight >= container.scrollHeight - 5;

        if (currentPage <= 0 && atTop && e.deltaY < 0 && onWebtoonStartPrev) {
          e.preventDefault();
          onWebtoonStartPrev();
          return;
        }

        if (isCollectionEndPage && onWebtoonEndNext) {
          if (atBottom && e.deltaY > 0) {
            e.preventDefault();
            onWebtoonEndNext();
          }
        }
        return;
      }

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
          return;
        }

        if (isNearBottom && deltaY > 0) {
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

        return;
      }

      const isHtmlPage = pages[currentPage]?.type === 'html';

      if (isHtmlPage) {
        const htmlContainer = resolveActiveHtmlContainer(targetEl);

        if (htmlContainer) {
          const startCountdown = (direction: 'prev' | 'next', onDone: () => void) => {
            setShowAutoNextCountdown(true);
            countdownSecondsRef.current = COUNTDOWN_DURATION;
            spreadWheelAccumRef.current = 0;

            const label = direction === 'next' ? '下一页' : '上一页';
            countdownToastId.current = toast.loading(`即将跳转到${label}（${COUNTDOWN_DURATION}秒后）`, {
              duration: COUNTDOWN_DURATION * 1000,
              action: { label: '取消', onClick: () => clearCountdown() },
            });

            countdownTimeoutRef.current = setInterval(() => {
              countdownSecondsRef.current -= 1;
              if (countdownSecondsRef.current <= 0) {
                clearCountdown();
                onDone();
                return;
              }

              if (countdownToastId.current !== null) {
                toast.loading(`即将跳转到${label}（${countdownSecondsRef.current}秒后）`, {
                  id: countdownToastId.current,
                  duration: countdownSecondsRef.current * 1000,
                  action: { label: '取消', onClick: () => clearCountdown() },
                });
              }
            }, 1000);
          };

          const isHorizontalSpread = htmlContainer.classList.contains('reader-html-spread-container');
          const primaryDelta = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;

          if (isHorizontalSpread) {
            const metrics = getHtmlSpreadMetrics(htmlContainer);
            const isAtStart = metrics.scrollLeft <= EDGE_THRESHOLD_PX;
            const isAtEnd = metrics.scrollLeft >= metrics.maxScrollLeft - EDGE_THRESHOLD_PX;
            const now = performance.now();
            const direction = primaryDelta < 0 ? 'prev' : primaryDelta > 0 ? 'next' : null;

            if (showAutoNextCountdown) {
              e.preventDefault();
              if (!((isAtStart && primaryDelta < 0) || (isAtEnd && primaryDelta > 0))) {
                clearCountdown();
              }
              return;
            }

            if (!direction) return;

            e.preventDefault();

            if (now < spreadWheelLockUntilRef.current) {
              return;
            }

            const prevAccum = spreadWheelAccumRef.current;
            spreadWheelAccumRef.current = prevAccum !== 0 && Math.sign(prevAccum) !== Math.sign(primaryDelta)
              ? primaryDelta
              : prevAccum + primaryDelta;

            if (Math.abs(spreadWheelAccumRef.current) < SPREAD_WHEEL_TRIGGER) {
              return;
            }

            spreadWheelAccumRef.current = 0;

            if ((direction === 'prev' && isAtStart) || (direction === 'next' && isAtEnd)) {
              startCountdown(direction, () => {
                if (direction === 'prev') {
                  onPrevPage();
                  setTimeout(() => {
                    const el = document.querySelector('.reader-html-spread-container') as HTMLElement | null;
                    if (el) {
                      const endMetrics = getHtmlSpreadMetrics(el);
                      el.scrollLeft = getHtmlSpreadSlotOffset(
                        endMetrics.maxScrollLeft,
                        endMetrics.step,
                        endMetrics.maxSlot
                      );
                    }
                  }, 100);
                } else {
                  onNextPage();
                  setTimeout(() => {
                    const el = document.querySelector('.reader-html-spread-container') as HTMLElement | null;
                    if (el) el.scrollLeft = 0;
                  }, 100);
                }
              });
              return;
            }

            if (stepHtmlSpread(htmlContainer, direction)) {
              spreadWheelLockUntilRef.current = now + SPREAD_WHEEL_LOCK_MS;
            }
            return;
          }

          const scrollTop = htmlContainer.scrollTop;
          const scrollHeight = htmlContainer.scrollHeight;
          const clientHeight = htmlContainer.clientHeight;
          const isAtTop = scrollTop <= EDGE_THRESHOLD_PX;
          const isAtBottom = scrollTop >= scrollHeight - clientHeight - EDGE_THRESHOLD_PX;
          const deltaY = e.deltaY;

          if (showAutoNextCountdown) {
            e.preventDefault();
            if (!((isAtTop && deltaY < 0) || (isAtBottom && deltaY > 0))) {
              clearCountdown();
            }
            return;
          }

          if (isAtTop && deltaY < 0) {
            e.preventDefault();
            startCountdown('prev', () => {
              onPrevPage();
              setTimeout(() => {
                const el = document.querySelector('.reader-html-page-container, .html-content-container') as HTMLElement | null;
                if (el) el.scrollTop = el.scrollHeight;
              }, 100);
            });
          } else if (isAtBottom && deltaY > 0) {
            e.preventDefault();
            startCountdown('next', () => {
              onNextPage();
              setTimeout(() => {
                const el = document.querySelector('.reader-html-page-container, .html-content-container') as HTMLElement | null;
                if (el) el.scrollTop = 0;
              }, 100);
            });
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
      webtoonContainerRef,
      isCollectionEndPage,
      onWebtoonStartPrev,
      onWebtoonEndNext,
    ]
  );

  useEffect(() => {
    window.addEventListener('wheel', handleWheel, { passive: false });
    return () => {
      window.removeEventListener('wheel', handleWheel);
    };
  }, [handleWheel]);
}
