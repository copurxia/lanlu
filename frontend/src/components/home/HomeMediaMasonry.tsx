'use client';

import { memo, useCallback, useEffect, useRef, useState, type RefObject } from 'react';
import { ArchiveCard } from '@/components/archive/ArchiveCard';
import { TankoubonCard } from '@/components/tankoubon/TankoubonCard';
import { useVirtualMasonryLayout } from '@/components/ui/hooks/useVirtualMasonryLayout';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

const ITEM_GAP_PX = 16;
const OVERSCAN_PX = 640;
const DEFAULT_ASPECT_RATIO = 3 / 4;
const DEFAULT_TEXT_HEIGHT = 88;
const ENABLE_HOME_MASONRY_VIRTUALIZATION =
  process.env.NEXT_PUBLIC_HOME_MASONRY_VIRTUALIZATION !== 'false';

type HomeMediaMasonryProps = {
  items: Array<Archive | Tankoubon>;
  selectionMode: boolean;
  selectedArchiveIds: Set<string>;
  selectedTankoubonIds: Set<string>;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
  scrollContainerRef?: RefObject<HTMLElement | null>;
};

function isTankoubonItem(item: Archive | Tankoubon): item is Tankoubon {
  return 'tankoubon_id' in item;
}

function getItemKey(item: Archive | Tankoubon): string {
  return isTankoubonItem(item)
    ? `tankoubon:${item.tankoubon_id}`
    : `archive:${item.arcid}`;
}

function getColumnCount(containerWidth: number): number {
  if (containerWidth < 640) return 2;
  if (containerWidth < 1024) return 3;
  if (containerWidth < 1280) return 4;
  if (containerWidth < 1536) return 5;
  return 6;
}

const HomeTankoubonMasonryCard = memo(function HomeTankoubonMasonryCard({
  index,
  onRequestEnterSelection,
  onToggleTankoubonSelect,
  selectionMode,
  selected,
  tankoubon,
}: {
  index: number;
  onRequestEnterSelection: () => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
  selectionMode: boolean;
  selected: boolean;
  tankoubon: Tankoubon;
}) {
  return (
    <TankoubonCard
      tankoubon={tankoubon}
      priority={index < 4}
      selectable
      selectionMode={selectionMode}
      selected={selected}
      onRequestEnterSelection={onRequestEnterSelection}
      onToggleSelect={(nextSelected) => onToggleTankoubonSelect(tankoubon.tankoubon_id, nextSelected)}
    />
  );
});

const HomeArchiveMasonryCard = memo(function HomeArchiveMasonryCard({
  archive,
  index,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  selectionMode,
  selected,
}: {
  archive: Archive;
  index: number;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
  selectionMode: boolean;
  selected: boolean;
}) {
  return (
    <ArchiveCard
      archive={archive}
      index={index}
      priority={index < 4}
      selectable
      selectionMode={selectionMode}
      selected={selected}
      onRequestEnterSelection={onRequestEnterSelection}
      onToggleSelect={(nextSelected) => onToggleArchiveSelect(archive.arcid, nextSelected)}
    />
  );
});

export const HomeMediaMasonry = memo(function HomeMediaMasonry({
  items,
  selectionMode,
  selectedArchiveIds,
  selectedTankoubonIds,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  onToggleTankoubonSelect,
  scrollContainerRef,
}: HomeMediaMasonryProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const resizeObserverRef = useRef<ResizeObserver | null>(null);
  const observedElementsRef = useRef(new Map<string, HTMLElement>());
  const [containerWidth, setContainerWidth] = useState(0);
  const [containerOffsetTop, setContainerOffsetTop] = useState(0);
  const [scrollTop, setScrollTop] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(0);
  const [viewportWidth, setViewportWidth] = useState(0);
  const [measuredHeights, setMeasuredHeights] = useState<Record<string, number>>({});

  const refreshViewportMetrics = useCallback(() => {
    const container = containerRef.current;
    if (!container) return;
    setContainerWidth(container.clientWidth);
    setViewportWidth(window.innerWidth || 0);

    const scrollRoot = scrollContainerRef?.current;
    if (scrollRoot) {
      const containerRect = container.getBoundingClientRect();
      const rootRect = scrollRoot.getBoundingClientRect();
      setContainerOffsetTop(containerRect.top - rootRect.top + scrollRoot.scrollTop);
      setScrollTop(scrollRoot.scrollTop);
      setViewportHeight(scrollRoot.clientHeight);
      return;
    }

    const windowScrollTop = window.scrollY || 0;
    setContainerOffsetTop(container.getBoundingClientRect().top + windowScrollTop);
    setScrollTop(windowScrollTop);
    setViewportHeight(window.innerHeight || 0);
  }, [scrollContainerRef]);

  useEffect(() => {
    refreshViewportMetrics();

    const scrollRoot = scrollContainerRef?.current;
    const handleScroll = () => {
      if (scrollRoot) {
        setScrollTop(scrollRoot.scrollTop);
      } else {
        setScrollTop(window.scrollY || 0);
      }
    };

    const attachTarget: EventTarget = scrollRoot || window;
    attachTarget.addEventListener('scroll', handleScroll, { passive: true });
    window.addEventListener('resize', refreshViewportMetrics);

    if (typeof ResizeObserver !== 'undefined' && containerRef.current) {
      const observer = new ResizeObserver(refreshViewportMetrics);
      observer.observe(containerRef.current);
      if (scrollRoot) observer.observe(scrollRoot);
      return () => {
        attachTarget.removeEventListener('scroll', handleScroll);
        window.removeEventListener('resize', refreshViewportMetrics);
        observer.disconnect();
      };
    }

    return () => {
      attachTarget.removeEventListener('scroll', handleScroll);
      window.removeEventListener('resize', refreshViewportMetrics);
    };
  }, [refreshViewportMetrics, scrollContainerRef]);

  useEffect(() => {
    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver((entries) => {
      setMeasuredHeights((prev) => {
        let changed = false;
        const next = { ...prev };
        for (const entry of entries) {
          const key = (entry.target as HTMLElement).dataset.masonryKey || '';
          if (!key) continue;
          const height = Math.max(1, Math.round(entry.contentRect.height));
          if (next[key] && Math.abs(next[key] - height) < 1) continue;
          next[key] = height;
          changed = true;
        }
        return changed ? next : prev;
      });
    });
    resizeObserverRef.current = observer;
    observedElementsRef.current.forEach((element) => observer.observe(element));
    return () => {
      observer.disconnect();
      resizeObserverRef.current = null;
    };
  }, []);

  const bindMeasureRef = useCallback((itemKey: string) => {
    return (node: HTMLDivElement | null) => {
      const prev = observedElementsRef.current.get(itemKey);
      if (prev && resizeObserverRef.current) {
        resizeObserverRef.current.unobserve(prev);
      }
      if (!node) {
        observedElementsRef.current.delete(itemKey);
        return;
      }
      node.dataset.masonryKey = itemKey;
      observedElementsRef.current.set(itemKey, node);
      if (resizeObserverRef.current) {
        resizeObserverRef.current.observe(node);
      }
    };
  }, []);

  const getEstimatedHeight = useCallback((item: Archive | Tankoubon, index: number, itemWidth: number) => {
    const key = getItemKey(item);
    const measured = measuredHeights[key];
    if (measured) return measured;
    return Math.round(itemWidth / Math.max(DEFAULT_ASPECT_RATIO, 0.05)) + DEFAULT_TEXT_HEIGHT;
  }, [measuredHeights]);

  const relativeScrollTop = Math.max(0, scrollTop - containerOffsetTop);
  const effectiveViewportWidth = viewportWidth > 0 ? viewportWidth : containerWidth;
  const masonry = useVirtualMasonryLayout({
    items,
    containerWidth,
    scrollTop: relativeScrollTop,
    viewportHeight,
    gap: ITEM_GAP_PX,
    overscan: OVERSCAN_PX,
    getColumns: () => getColumnCount(effectiveViewportWidth),
    getItemKey: (item) => getItemKey(item),
    getItemHeight: getEstimatedHeight,
  });

  if (!ENABLE_HOME_MASONRY_VIRTUALIZATION) {
    return (
      <div className="columns-2 gap-4 sm:columns-3 lg:columns-4 xl:columns-5 2xl:columns-6">
        {items.map((item, index) => {
          if (isTankoubonItem(item)) {
            return (
              <div key={getItemKey(item)} className="mb-4 break-inside-avoid">
                <HomeTankoubonMasonryCard
                  index={index}
                  onRequestEnterSelection={onRequestEnterSelection}
                  onToggleTankoubonSelect={onToggleTankoubonSelect}
                  selectionMode={selectionMode}
                  selected={selectedTankoubonIds.has(item.tankoubon_id)}
                  tankoubon={item}
                />
              </div>
            );
          }

          return (
            <div key={getItemKey(item)} className="mb-4 break-inside-avoid">
              <HomeArchiveMasonryCard
                archive={item}
                index={index}
                onRequestEnterSelection={onRequestEnterSelection}
                onToggleArchiveSelect={onToggleArchiveSelect}
                selectionMode={selectionMode}
                selected={selectedArchiveIds.has(item.arcid)}
              />
            </div>
          );
        })}
      </div>
    );
  }

  return (
    <div ref={containerRef}>
      <div className="relative" style={{ height: `${masonry.totalHeight}px` }}>
        {masonry.visibleItems.map((layoutItem) => {
          const { item, index, key, top, left, width } = layoutItem;
          const style = {
            top: `${top}px`,
            left: `${left}px`,
            width: `${width}px`,
          };
          if (isTankoubonItem(item)) {
            return (
              <div key={key} ref={bindMeasureRef(key)} className="absolute" style={style}>
                <HomeTankoubonMasonryCard
                  index={index}
                  onRequestEnterSelection={onRequestEnterSelection}
                  onToggleTankoubonSelect={onToggleTankoubonSelect}
                  selectionMode={selectionMode}
                  selected={selectedTankoubonIds.has(item.tankoubon_id)}
                  tankoubon={item}
                />
              </div>
            );
          }

          return (
            <div key={key} ref={bindMeasureRef(key)} className="absolute" style={style}>
              <HomeArchiveMasonryCard
                archive={item}
                index={index}
                onRequestEnterSelection={onRequestEnterSelection}
                onToggleArchiveSelect={onToggleArchiveSelect}
                selectionMode={selectionMode}
                selected={selectedArchiveIds.has(item.arcid)}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
});
