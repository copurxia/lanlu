import { useCallback, useEffect, useRef, useState } from 'react';
import type { PageInfo } from '@/lib/services/archive-service';

const INITIAL_SIDEBAR_PAGE_COUNT = 20;
const SIDEBAR_LOAD_MORE_STEP = 10;
const SIDEBAR_AUTO_EXPAND_AHEAD = 10;

export function useReaderSidebar({
  pages,
  currentPage,
  resetKey,
  loading,
  onSelectPage,
  resetTransform,
}: {
  pages: PageInfo[];
  currentPage: number;
  resetKey?: string | null;
  loading: boolean;
  onSelectPage: (pageIndex: number) => void;
  resetTransform: () => void;
}) {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [sidebarDisplayPages, setSidebarDisplayPages] = useState<PageInfo[]>([]);
  const [sidebarLoadedCount, setSidebarLoadedCount] = useState(INITIAL_SIDEBAR_PAGE_COUNT);
  const [sidebarLoading, setSidebarLoading] = useState(false);
  const [isEpub, setIsEpub] = useState(false);
  const sidebarScrollRef = useRef<HTMLDivElement | null>(null);
  const previousResetKeyRef = useRef<string | null | undefined>(resetKey);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      const savedSidebarState = localStorage.getItem('reader_sidebar_open');
      if (savedSidebarState !== null) {
        setSidebarOpen(savedSidebarState === 'true');
      }
    }
  }, []);

  useEffect(() => {
    setIsEpub(pages.length > 0 && pages[0]?.type === 'html');
  }, [pages]);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('reader_sidebar_open', sidebarOpen.toString());
    }
  }, [sidebarOpen]);

  useEffect(() => {
    if (previousResetKeyRef.current !== resetKey) {
      previousResetKeyRef.current = resetKey;
      setSidebarDisplayPages([]);
      setSidebarLoadedCount(INITIAL_SIDEBAR_PAGE_COUNT);
      setSidebarLoading(false);
      return;
    }

    if (loading) return;

    if (pages.length > 0 && sidebarDisplayPages.length === 0) {
      const initialCount = Math.min(pages.length, sidebarLoadedCount);
      setSidebarDisplayPages(pages.slice(0, initialCount));
      setSidebarLoading(false);
      return;
    }

    if (sidebarLoadedCount > pages.length) {
      setSidebarLoadedCount(pages.length);
    }
    if (sidebarDisplayPages.length > pages.length) {
      setSidebarDisplayPages((prev) => prev.slice(0, pages.length));
    }
  }, [loading, pages, resetKey, sidebarDisplayPages.length, sidebarLoadedCount]);

  useEffect(() => {
    if (!sidebarOpen || loading || sidebarLoading) return;
    if (currentPage < sidebarLoadedCount || sidebarLoadedCount >= pages.length) return;

    const targetCount = Math.min(pages.length, currentPage + SIDEBAR_AUTO_EXPAND_AHEAD);
    if (targetCount <= sidebarLoadedCount) return;

    setSidebarDisplayPages(pages.slice(0, targetCount));
    setSidebarLoadedCount(targetCount);
  }, [currentPage, loading, pages, sidebarLoadedCount, sidebarLoading, sidebarOpen]);

  const handleSidebarPageSelect = useCallback(
    (pageIndex: number) => {
      onSelectPage(pageIndex);
      resetTransform();

      if (typeof window !== 'undefined' && window.innerWidth < 768) {
        setSidebarOpen(false);
      }
    },
    [onSelectPage, resetTransform]
  );

  const handleLoadMoreSidebarPages = useCallback(() => {
    const scrollElement = sidebarScrollRef.current;
    const scrollTop = scrollElement?.scrollTop || 0;

    if (sidebarLoadedCount >= pages.length) return;

    setSidebarLoading(true);
    const newCount = Math.min(pages.length, sidebarLoadedCount + SIDEBAR_LOAD_MORE_STEP);
    setSidebarDisplayPages(pages.slice(0, newCount));

    setSidebarLoadedCount(newCount);
    setSidebarLoading(false);

    requestAnimationFrame(() => {
      if (scrollElement) {
        scrollElement.scrollTop = scrollTop;
      }
    });
  }, [pages, sidebarLoadedCount]);

  return {
    sidebarOpen,
    setSidebarOpen,
    sidebarScrollRef,
    sidebarDisplayPages,
    sidebarLoadedCount,
    sidebarLoading,
    isEpub,
    handleSidebarPageSelect,
    handleLoadMoreSidebarPages,
  };
}
