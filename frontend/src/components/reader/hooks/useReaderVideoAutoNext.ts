'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { toast } from '@/lib/ui/feedback';

const COUNTDOWN_DURATION = 3;

export function useReaderVideoAutoNext({
  currentPage,
  pagesLength,
  doublePageMode,
  splitCoverMode,
  onNextPage,
}: {
  currentPage: number;
  pagesLength: number;
  doublePageMode: boolean;
  splitCoverMode: boolean;
  onNextPage: () => void;
}) {
  const [showAutoNextCountdown, setShowAutoNextCountdown] = useState(false);
  const countdownSecondsRef = useRef(COUNTDOWN_DURATION);
  const countdownTimeoutRef = useRef<ReturnType<typeof setInterval> | null>(null);
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

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      clearCountdown();
    };
  }, [clearCountdown]);

  // Clear countdown when page changes
  useEffect(() => {
    clearCountdown();
  }, [currentPage, clearCountdown]);

  const handleVideoEnded = useCallback(
    (pageIndex: number) => {
      // Only handle video ended for the current page (or current + 1 in double page mode)
      const isCurrentPage = pageIndex === currentPage;
      const isNextPageInDoubleMode =
        doublePageMode &&
        !splitCoverMode &&
        currentPage === 0 &&
        pageIndex === currentPage + 1;

      if (!isCurrentPage && !isNextPageInDoubleMode) {
        return;
      }

      // Check if there's a next page
      if (doublePageMode) {
        if (currentPage >= pagesLength - (splitCoverMode && currentPage === 0 ? 1 : 2)) {
          return;
        }
      } else {
        if (currentPage >= pagesLength - 1) {
          return;
        }
      }

      // If already showing countdown, don't start another
      if (showAutoNextCountdown) {
        return;
      }

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
    },
    [
      currentPage,
      pagesLength,
      doublePageMode,
      splitCoverMode,
      showAutoNextCountdown,
      clearCountdown,
      onNextPage,
    ]
  );

  return {
    handleVideoEnded,
    showAutoNextCountdown,
    clearVideoAutoNextCountdown: clearCountdown,
  };
}
