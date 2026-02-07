import { useCallback, useRef, useState } from 'react';

const TAP_MOVE_THRESHOLD_PX = 10;
const TAP_MAX_DURATION_MS = 350;
const IGNORE_CLICK_AFTER_TOUCH_MS = 800;

function getDistance(touch1: Touch, touch2: Touch) {
  const dx = touch1.clientX - touch2.clientX;
  const dy = touch1.clientY - touch2.clientY;
  return Math.sqrt(dx * dx + dy * dy);
}

function isInteractiveTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false;
  return Boolean(
    target.closest('a,button,input,textarea,select,option,[role="button"],[role="link"],[data-no-reader-tap]')
  );
}

function isHtmlContentTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false;
  return Boolean(target.closest('.html-content-container'));
}

export function getTapTurnAction(readerAreaEl: HTMLDivElement | null, clientX: number, clientY: number) {
  if (!readerAreaEl) return 'none' as const;
  const rect = readerAreaEl.getBoundingClientRect();
  const x = clientX - rect.left;
  const y = clientY - rect.top;
  if (x < 0 || y < 0 || x > rect.width || y > rect.height) return 'none' as const;

  const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));
  const edgeW = clamp(rect.width * 0.22, 72, Math.min(320, rect.width * 0.45));
  const edgeH = clamp(rect.height * 0.22, 72, Math.min(320, rect.height * 0.45));

  const inLeft = x <= edgeW;
  const inRight = x >= rect.width - edgeW;
  const inTop = y <= edgeH;
  const inBottom = y >= rect.height - edgeH;

  if (!(inLeft || inRight || inTop || inBottom)) return 'none' as const;

  const leftDist = x;
  const rightDist = rect.width - x;
  const topDist = y;
  const bottomDist = rect.height - y;
  const minDist = Math.min(leftDist, rightDist, topDist, bottomDist);

  if (minDist === rightDist || minDist === bottomDist) return 'next' as const;
  return 'prev' as const;
}

export function useReaderInteractionHandlers({
  readerAreaRef,
  readingMode,
  tapTurnPageEnabled,
  autoHideEnabled,
  showToolbar,
  onToggleToolbar,
  onHideToolbar,
  onPrevPage,
  onNextPage,
  onWebtoonEndNext,
  currentPage,
  setCurrentPage,
  pagesLength,
  webtoonContainerRef,
  imageHeights,
  containerHeight,
  setScale,
}: {
  readerAreaRef: React.RefObject<HTMLDivElement | null>;
  readingMode: 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';
  tapTurnPageEnabled: boolean;
  autoHideEnabled: boolean;
  showToolbar: boolean;
  onToggleToolbar: () => void;
  onHideToolbar: () => void;
  onPrevPage: () => void;
  onNextPage: () => void;
  onWebtoonEndNext?: () => void;
  currentPage: number;
  setCurrentPage: (page: number) => void;
  pagesLength: number;
  webtoonContainerRef: React.RefObject<HTMLDivElement | null>;
  imageHeights: number[];
  containerHeight: number;
  setScale: React.Dispatch<React.SetStateAction<number>>;
}) {
  const [touchStart, setTouchStart] = useState<{ x: number; y: number } | null>(null);
  const [touchEnd, setTouchEnd] = useState<{ x: number; y: number } | null>(null);
  const [lastTouchDistance, setLastTouchDistance] = useState(0);

  const tapStartRef = useRef<{ x: number; y: number; time: number } | null>(null);
  const tapMovedRef = useRef(false);
  const lastTouchAtRef = useRef(0);

  const runTapTurnAction = useCallback(
    (action: 'prev' | 'next') => {
      if (autoHideEnabled && showToolbar) {
        onHideToolbar();
      }

      if (readingMode === 'webtoon' && webtoonContainerRef.current) {
        if (action === 'next' && currentPage >= pagesLength - 1 && onWebtoonEndNext) {
          onWebtoonEndNext();
          return;
        }

        const nextPage =
          action === 'prev'
            ? Math.max(0, currentPage - 1)
            : Math.min(pagesLength - 1, currentPage + 1);

        setCurrentPage(nextPage);

        requestAnimationFrame(() => {
          const container = webtoonContainerRef.current;
          if (!container) return;
          let accumulatedHeight = 0;
          for (let i = 0; i < nextPage; i++) {
            accumulatedHeight += imageHeights[i] || containerHeight || window.innerHeight * 0.7;
          }
          container.scrollTop = accumulatedHeight;
        });

        return;
      }

      if (action === 'prev') {
        onPrevPage();
      } else {
        onNextPage();
      }
    },
    [
      autoHideEnabled,
      showToolbar,
      onHideToolbar,
      readingMode,
      webtoonContainerRef,
      currentPage,
      pagesLength,
      onWebtoonEndNext,
      setCurrentPage,
      imageHeights,
      containerHeight,
      onPrevPage,
      onNextPage,
    ]
  );

  const onTouchStart = useCallback(
    (e: React.TouchEvent) => {
      lastTouchAtRef.current = Date.now();

      if (e.touches.length === 1) {
        tapStartRef.current = {
          x: e.touches[0].clientX,
          y: e.touches[0].clientY,
          time: Date.now(),
        };
        tapMovedRef.current = false;
      } else {
        tapStartRef.current = null;
        tapMovedRef.current = true;
      }

      if (readingMode === 'webtoon') return;

      if (e.touches.length === 1) {
        setTouchEnd(null);
        setTouchStart({ x: e.touches[0].clientX, y: e.touches[0].clientY });
      } else if (e.touches.length === 2) {
        const distance = getDistance(e.touches[0] as Touch, e.touches[1] as Touch);
        setLastTouchDistance(distance);
        setTouchStart(null);
      }
    },
    [readingMode]
  );

  const onTouchMove = useCallback(
    (e: React.TouchEvent) => {
      lastTouchAtRef.current = Date.now();

      if (e.touches.length === 1 && tapStartRef.current) {
        const dx = e.touches[0].clientX - tapStartRef.current.x;
        const dy = e.touches[0].clientY - tapStartRef.current.y;
        if (Math.abs(dx) > TAP_MOVE_THRESHOLD_PX || Math.abs(dy) > TAP_MOVE_THRESHOLD_PX) {
          tapMovedRef.current = true;
        }
      } else if (e.touches.length > 1) {
        tapMovedRef.current = true;
      }

      if (readingMode === 'webtoon') return;

      if (e.touches.length === 1 && touchStart) {
        setTouchEnd({ x: e.touches[0].clientX, y: e.touches[0].clientY });
      } else if (e.touches.length === 2) {
        e.preventDefault();
        const distance = getDistance(e.touches[0] as Touch, e.touches[1] as Touch);
        if (lastTouchDistance > 0) {
          const scaleChange = distance / lastTouchDistance;
          setScale((prev) => Math.min(Math.max(prev * scaleChange, 0.5), 3));
        }
        setLastTouchDistance(distance);
      }
    },
    [readingMode, touchStart, lastTouchDistance, setScale]
  );

  const onTouchEnd = useCallback(
    (e: React.TouchEvent) => {
      lastTouchAtRef.current = Date.now();

      const start = tapStartRef.current;
      const now = Date.now();
      const duration = start ? now - start.time : Infinity;
      const endTouch = e.changedTouches?.[0];
      const movedByEnd =
        Boolean(start && endTouch) &&
        (Math.abs(endTouch.clientX - start!.x) > TAP_MOVE_THRESHOLD_PX ||
          Math.abs(endTouch.clientY - start!.y) > TAP_MOVE_THRESHOLD_PX);
      const moved = tapMovedRef.current || movedByEnd;
      const isTap = Boolean(start && !moved && duration <= TAP_MAX_DURATION_MS);

      if (isTap) {
        if (isHtmlContentTarget(e.target) || isInteractiveTarget(e.target)) {
          tapStartRef.current = null;
          tapMovedRef.current = false;
          return;
        }

        if (tapTurnPageEnabled && endTouch) {
          const action = getTapTurnAction(readerAreaRef.current, endTouch.clientX, endTouch.clientY);
          if (action === 'prev' || action === 'next') {
            runTapTurnAction(action);
            tapStartRef.current = null;
            tapMovedRef.current = false;
            setTouchStart(null);
            setTouchEnd(null);
            setLastTouchDistance(0);
            return;
          }
        }

        onToggleToolbar();
        tapStartRef.current = null;
        tapMovedRef.current = false;
        setTouchStart(null);
        setTouchEnd(null);
        setLastTouchDistance(0);
        return;
      }

      if (autoHideEnabled && showToolbar && moved) {
        onHideToolbar();
      }

      tapStartRef.current = null;
      tapMovedRef.current = false;

      if (!touchStart || !touchEnd) {
        setLastTouchDistance(0);
        return;
      }

      if (readingMode === 'webtoon') {
        setTouchStart(null);
        setTouchEnd(null);
        setLastTouchDistance(0);
        return;
      }

      const deltaX = touchStart.x - touchEnd.x;
      const deltaY = touchStart.y - touchEnd.y;
      const isHorizontalSwipe = Math.abs(deltaX) > Math.abs(deltaY);
      const isSwipe = Math.abs(deltaX) > 50 || Math.abs(deltaY) > 50;

      if (isSwipe) {
        if (isHorizontalSwipe) {
          if (readingMode === 'single-rtl') {
            if (deltaX > 50) {
              onPrevPage();
            } else if (deltaX < -50) {
              onNextPage();
            }
          } else {
            if (deltaX > 50) {
              onNextPage();
            } else if (deltaX < -50) {
              onPrevPage();
            }
          }
        } else {
          if (readingMode === 'single-ttb') {
            if (deltaY > 50) {
              onNextPage();
            } else if (deltaY < -50) {
              onPrevPage();
            }
          }
        }
      }

      setTouchStart(null);
      setTouchEnd(null);
      setLastTouchDistance(0);
    },
    [
      readerAreaRef,
      onToggleToolbar,
      onHideToolbar,
      onPrevPage,
      onNextPage,
      autoHideEnabled,
      showToolbar,
      touchStart,
      touchEnd,
      readingMode,
      tapTurnPageEnabled,
      runTapTurnAction,
    ]
  );

  const onClick = useCallback(
    (e: React.MouseEvent) => {
      if (isHtmlContentTarget(e.target) || isInteractiveTarget(e.target)) return;
      if (Date.now() - lastTouchAtRef.current < IGNORE_CLICK_AFTER_TOUCH_MS) return;

      if (tapTurnPageEnabled) {
        const action = getTapTurnAction(readerAreaRef.current, e.clientX, e.clientY);
        if (action === 'prev' || action === 'next') {
          runTapTurnAction(action);
          return;
        }
      }

      onToggleToolbar();
    },
    [readerAreaRef, tapTurnPageEnabled, onToggleToolbar, runTapTurnAction]
  );

  return {
    onClick,
    onTouchStart,
    onTouchMove,
    onTouchEnd,
  };
}
