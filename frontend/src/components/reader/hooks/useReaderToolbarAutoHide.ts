'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

export function useReaderToolbarAutoHide({
  autoHideEnabled,
  delayMs = 3000,
  edgeThreshold = 80,
}: {
  autoHideEnabled: boolean;
  delayMs?: number;
  edgeThreshold?: number;
}) {
  const [showToolbar, setShowToolbar] = useState(true);
  const autoHideTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mouseMoveHandlerRef = useRef<((e: MouseEvent) => void) | null>(null);

  const clearAutoHideTimers = useCallback(() => {
    if (autoHideTimeoutRef.current) {
      clearTimeout(autoHideTimeoutRef.current);
      autoHideTimeoutRef.current = null;
    }
  }, []);

  const scheduleAutoHide = useCallback(() => {
    if (!autoHideEnabled) return;
    if (autoHideTimeoutRef.current) {
      clearTimeout(autoHideTimeoutRef.current);
    }
    autoHideTimeoutRef.current = setTimeout(() => {
      setShowToolbar(false);
    }, delayMs);
  }, [autoHideEnabled, delayMs]);

  const hideToolbar = useCallback(() => {
    setShowToolbar(false);
    clearAutoHideTimers();
  }, [clearAutoHideTimers]);

  const showToolbarAndSchedule = useCallback(() => {
    if (!autoHideEnabled) return;
    setShowToolbar(true);
    scheduleAutoHide();
  }, [autoHideEnabled, scheduleAutoHide]);

  const toggleToolbar = useCallback(() => {
    if (!autoHideEnabled) return;
    setShowToolbar((prev) => {
      const next = !prev;
      if (next) {
        scheduleAutoHide();
      } else {
        clearAutoHideTimers();
      }
      return next;
    });
  }, [autoHideEnabled, scheduleAutoHide, clearAutoHideTimers]);

  useEffect(() => {
    clearAutoHideTimers();

    if (!autoHideEnabled) {
      setShowToolbar(true);
      return;
    }

    if (showToolbar) {
      scheduleAutoHide();
    }

    return () => {
      clearAutoHideTimers();
    };
  }, [autoHideEnabled, showToolbar, scheduleAutoHide, clearAutoHideTimers]);

  // 鼠标靠近底部边缘时自动显示工具栏
  useEffect(() => {
    if (!autoHideEnabled || typeof window === 'undefined') return;

    const handleMouseMove = (e: MouseEvent) => {
      const windowHeight = window.innerHeight;
      const mouseY = e.clientY;
      
      // 当鼠标靠近底部边缘时显示工具栏
      if (mouseY >= windowHeight - edgeThreshold) {
        if (!showToolbar) {
          showToolbarAndSchedule();
        }
      }
    };

    mouseMoveHandlerRef.current = handleMouseMove;
    document.addEventListener('mousemove', handleMouseMove);

    return () => {
      if (mouseMoveHandlerRef.current) {
        document.removeEventListener('mousemove', mouseMoveHandlerRef.current);
      }
    };
  }, [autoHideEnabled, showToolbar, edgeThreshold, showToolbarAndSchedule]);

  return { showToolbar, setShowToolbar, hideToolbar, toggleToolbar } as const;
}

