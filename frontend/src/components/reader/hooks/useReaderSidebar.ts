import { useCallback, useEffect, useRef, useState } from 'react';
import type { PageInfo } from '@/lib/services/archive-service';

export function useReaderSidebar({
  pages,
  currentPage,
  loadedImages,
  imagesLoading,
  onSelectPage,
  resetTransform,
}: {
  pages: PageInfo[];
  currentPage: number;
  loadedImages: Set<number>;
  imagesLoading: Set<number>;
  onSelectPage: (pageIndex: number) => void;
  resetTransform: () => void;
}) {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [sidebarDisplayPages, setSidebarDisplayPages] = useState<PageInfo[]>([]);
  const [sidebarLoadedCount, setSidebarLoadedCount] = useState(20);
  const [sidebarLoading, setSidebarLoading] = useState(false);
  const [sidebarImagesLoading, setSidebarImagesLoading] = useState<Set<number>>(new Set());
  const [isEpub, setIsEpub] = useState(false);
  const sidebarScrollRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      const savedSidebarState = localStorage.getItem('reader_sidebar_open');
      if (savedSidebarState !== null) {
        setSidebarOpen(savedSidebarState === 'true');
      }
    }

    if (pages.length > 0) {
      setIsEpub(pages[0]?.type === 'html');
    }
  }, [pages]);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('reader_sidebar_open', sidebarOpen.toString());
    }
  }, [sidebarOpen]);

  useEffect(() => {
    if (pages.length > 0 && sidebarDisplayPages.length === 0) {
      setSidebarDisplayPages(pages.slice(0, sidebarLoadedCount));
      setSidebarLoading(false);
    }
  }, [pages, sidebarLoadedCount, sidebarDisplayPages.length]);

  useEffect(() => {
    if (currentPage >= sidebarLoadedCount && sidebarLoadedCount < pages.length && !sidebarLoading) {
      const targetCount = Math.min(pages.length, currentPage + 10);
      const newPages = pages.slice(sidebarLoadedCount, targetCount);

      if (newPages.length > 0) {
        setSidebarDisplayPages((prev) => [...prev, ...newPages]);
        setSidebarLoadedCount(targetCount);

        const newPageIndices: number[] = [];
        for (let i = sidebarLoadedCount; i < targetCount; i++) {
          if (!loadedImages.has(i) && !imagesLoading.has(i)) {
            newPageIndices.push(i);
          }
        }
        if (newPageIndices.length > 0) {
          setSidebarImagesLoading((prev) => {
            const updated = new Set(prev);
            newPageIndices.forEach((index) => updated.add(index));
            return updated;
          });
        }
      }
    }
  }, [currentPage, pages.length, sidebarLoadedCount, sidebarLoading, loadedImages, imagesLoading, pages]);

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

  const handleSidebarThumbLoaded = useCallback((pageIndex: number) => {
    setSidebarImagesLoading((prev) => {
      const next = new Set(prev);
      next.delete(pageIndex);
      return next;
    });
  }, []);

  const handleSidebarThumbError = useCallback((pageIndex: number) => {
    setSidebarImagesLoading((prev) => {
      const next = new Set(prev);
      next.delete(pageIndex);
      return next;
    });
  }, []);

  const handleLoadMoreSidebarPages = useCallback(() => {
    const scrollElement = sidebarScrollRef.current;
    const scrollTop = scrollElement?.scrollTop || 0;

    setSidebarLoading(true);
    const newCount = sidebarLoadedCount + 10;
    const newPages = pages.slice(sidebarLoadedCount, newCount);
    setSidebarDisplayPages((prev) => [...prev, ...newPages]);

    const newPageIndices: number[] = [];
    for (let i = sidebarLoadedCount; i < Math.min(newCount, pages.length); i++) {
      if (!loadedImages.has(i) && !imagesLoading.has(i)) {
        newPageIndices.push(i);
      }
    }
    if (newPageIndices.length > 0) {
      setSidebarImagesLoading((prev) => {
        const updated = new Set(prev);
        newPageIndices.forEach((index) => updated.add(index));
        return updated;
      });
    }

    setSidebarLoadedCount(newCount);
    setSidebarLoading(false);

    requestAnimationFrame(() => {
      if (scrollElement) {
        scrollElement.scrollTop = scrollTop;
      }
    });
  }, [pages, sidebarLoadedCount, loadedImages, imagesLoading]);

  return {
    sidebarOpen,
    setSidebarOpen,
    sidebarScrollRef,
    sidebarDisplayPages,
    sidebarLoadedCount,
    sidebarLoading,
    sidebarImagesLoading,
    isEpub,
    handleSidebarPageSelect,
    handleLoadMoreSidebarPages,
    handleSidebarThumbLoaded,
    handleSidebarThumbError,
  };
}

