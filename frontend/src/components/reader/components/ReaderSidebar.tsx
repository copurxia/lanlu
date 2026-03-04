import { Book, ChevronDown, ChevronRight, FileText, Film, Folder, ImageIcon, List } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Sheet, SheetContent } from '@/components/ui/sheet';
import { Spinner } from '@/components/ui/spinner';
import { MemoizedImage } from '@/components/reader/components/MemoizedMedia';
import type { PageInfo } from '@/lib/services/archive-service';
import type React from 'react';

const SIDEBAR_HORIZONTAL_PADDING_PX = 24;
const SIDEBAR_GRID_GAP_PX = 8;
const SIDEBAR_GRID_OVERSCAN_ROWS = 3;
const SIDEBAR_IMAGE_HEIGHT_RATIO = 4 / 3; // `aspect-[3/4]`
const SIDEBAR_THUMB_IMAGE_CLASS = 'absolute inset-0 h-full w-full object-contain object-center transition-opacity duration-200';
const SIDEBAR_CONTENT_PADDING_CLASS = 'px-3 pb-2 pt-2';
const FILE_TREE_ROW_LEFT_PADDING_PX = 6;
const FILE_TREE_DEPTH_INDENT_PX = 14;

type FileTreeFileNode = {
  kind: 'file';
  id: string;
  name: string;
  pageIndex: number;
  pageType: PageInfo['type'];
};

type FileTreeFolderNode = {
  kind: 'folder';
  id: string;
  name: string;
  firstPageIndex: number;
  children: FileTreeNode[];
};

type FileTreeNode = FileTreeFolderNode | FileTreeFileNode;

type MutableFileTreeFolderNode = {
  id: string;
  name: string;
  firstPageIndex: number;
  folders: Map<string, MutableFileTreeFolderNode>;
  files: FileTreeFileNode[];
};

type SidebarTab = 'thumbnails' | 'list' | 'tree';

function getPageArchiveId(page: PageInfo): string {
  const archiveId = (page as { archiveId?: string }).archiveId;
  return typeof archiveId === 'string' ? archiveId : '';
}

function getPagePathSegments(path: string): string[] {
  return String(path || '')
    .split('/')
    .map((segment) => segment.trim())
    .filter(Boolean);
}

function getPageDisplayTitle(page: PageInfo, pageIndex: number, t: (key: string) => string): string {
  const metaTitle = page.metadata?.title?.trim();
  if (metaTitle) return metaTitle;
  const pageTitle = page.title?.trim();
  if (pageTitle) return pageTitle;
  return t('reader.pageAlt').replace('{page}', String(pageIndex + 1));
}

function getPageDisplayDescription(page: PageInfo): string {
  return page.metadata?.description?.trim() || '';
}

function getPageDisplayThumb(page: PageInfo): string {
  return page.metadata?.thumb?.trim() || '';
}

export function ReaderSidebar({
  open,
  allPages,
  sidebarScrollRef,
  sidebarLoading,
  isEpub,
  sidebarDisplayPages,
  currentPage,
  pagesLength,
  canLoadMore,
  onSelectPage,
  onLoadMore,
  onOpenChange,
  t,
}: {
  open: boolean;
  allPages: PageInfo[];
  sidebarScrollRef: React.RefObject<HTMLDivElement | null>;
  sidebarLoading: boolean;
  isEpub: boolean;
  sidebarDisplayPages: PageInfo[];
  currentPage: number;
  pagesLength: number;
  canLoadMore: boolean;
  onSelectPage: (pageIndex: number) => void;
  onLoadMore: () => void;
  onOpenChange: (nextOpen: boolean) => void;
  t: (key: string) => string;
}) {
  const [sidebarScrollTop, setSidebarScrollTop] = useState(0);
  const [sidebarViewportHeight, setSidebarViewportHeight] = useState(0);
  const [sidebarContentWidth, setSidebarContentWidth] = useState(0);
  const [isMobileViewport, setIsMobileViewport] = useState(false);
  const [activeTab, setActiveTab] = useState<SidebarTab>('thumbnails');
  const [expandedFolderIds, setExpandedFolderIds] = useState<Set<string>>(new Set());
  const fileTreeScrollRef = useRef<HTMLDivElement | null>(null);
  const wasOpenRef = useRef(false);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    const mediaQuery = window.matchMedia('(max-width: 767px)');
    const updateViewport = () => setIsMobileViewport(mediaQuery.matches);
    updateViewport();

    if (typeof mediaQuery.addEventListener === 'function') {
      mediaQuery.addEventListener('change', updateViewport);
      return () => mediaQuery.removeEventListener('change', updateViewport);
    }

    mediaQuery.addListener(updateViewport);
    return () => mediaQuery.removeListener(updateViewport);
  }, []);

  const updateSidebarViewport = useCallback(() => {
    const sidebarElement = sidebarScrollRef.current;
    if (!sidebarElement) return;

    setSidebarViewportHeight(sidebarElement.clientHeight);
    setSidebarContentWidth(Math.max(0, sidebarElement.clientWidth - SIDEBAR_HORIZONTAL_PADDING_PX));
  }, [sidebarScrollRef]);

  useEffect(() => {
    if (!open || isEpub || activeTab !== 'thumbnails') return;

    const sidebarElement = sidebarScrollRef.current;
    if (!sidebarElement) return;

    updateSidebarViewport();
    setSidebarScrollTop(sidebarElement.scrollTop);

    if (typeof ResizeObserver === 'undefined') {
      window.addEventListener('resize', updateSidebarViewport);
      return () => {
        window.removeEventListener('resize', updateSidebarViewport);
      };
    }

    const observer = new ResizeObserver(updateSidebarViewport);
    observer.observe(sidebarElement);
    window.addEventListener('resize', updateSidebarViewport);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', updateSidebarViewport);
    };
  }, [activeTab, isEpub, open, sidebarScrollRef, updateSidebarViewport]);

  const sidebarColumns = useMemo(() => (sidebarContentWidth >= 768 ? 3 : 2), [sidebarContentWidth]);

  const thumbWidth = useMemo(() => {
    if (sidebarColumns <= 0) return 0;
    const totalGaps = SIDEBAR_GRID_GAP_PX * (sidebarColumns - 1);
    const width = Math.floor((sidebarContentWidth - totalGaps) / sidebarColumns);
    return Math.max(0, width);
  }, [sidebarColumns, sidebarContentWidth]);

  const thumbHeight = thumbWidth > 0 ? Math.round(thumbWidth * SIDEBAR_IMAGE_HEIGHT_RATIO) : 0;
  const rowHeight = thumbHeight + SIDEBAR_GRID_GAP_PX;
  const totalRows = sidebarColumns > 0 ? Math.ceil(sidebarDisplayPages.length / sidebarColumns) : 0;
  const totalHeight = totalRows > 0 ? totalRows * rowHeight - SIDEBAR_GRID_GAP_PX : 0;
  const canVirtualizeGrid = !isEpub && thumbWidth > 0 && rowHeight > 0 && sidebarViewportHeight > 0;

  const startRow = canVirtualizeGrid
    ? Math.max(0, Math.floor(sidebarScrollTop / rowHeight) - SIDEBAR_GRID_OVERSCAN_ROWS)
    : 0;
  const endRow = canVirtualizeGrid
    ? Math.min(
        totalRows - 1,
        Math.ceil((sidebarScrollTop + sidebarViewportHeight) / rowHeight) + SIDEBAR_GRID_OVERSCAN_ROWS
      )
    : totalRows - 1;

  const visibleStartIndex = Math.max(0, startRow * sidebarColumns);
  const visibleEndIndex = Math.max(
    -1,
    Math.min(sidebarDisplayPages.length - 1, ((endRow + 1) * sidebarColumns) - 1)
  );

  const visibleThumbs = useMemo(() => {
    if (!canVirtualizeGrid || visibleEndIndex < visibleStartIndex) return [] as Array<{
      page: PageInfo;
      index: number;
      top: number;
      left: number;
    }>;

    const items: Array<{ page: PageInfo; index: number; top: number; left: number }> = [];
    for (let i = visibleStartIndex; i <= visibleEndIndex; i += 1) {
      const page = sidebarDisplayPages[i];
      if (!page) continue;

      const row = Math.floor(i / sidebarColumns);
      const column = i % sidebarColumns;
      items.push({
        page,
        index: i,
        top: row * rowHeight,
        left: column * (thumbWidth + SIDEBAR_GRID_GAP_PX),
      });
    }

    return items;
  }, [
    canVirtualizeGrid,
    rowHeight,
    sidebarColumns,
    sidebarDisplayPages,
    thumbWidth,
    visibleEndIndex,
    visibleStartIndex,
  ]);

  const fileTree = useMemo(() => {
    const defaultPageLabel = (pageIndex: number) =>
      t('reader.pageAlt').replace('{page}', String(pageIndex + 1));

    const parsedPages = allPages.map((page, pageIndex) => {
      const pathSegments = getPagePathSegments(page.path);
      const fallbackName = getPageDisplayTitle(page, pageIndex, t) || defaultPageLabel(pageIndex);
      return {
        archiveId: getPageArchiveId(page),
        pageIndex,
        pageType: page.type,
        segments: pathSegments,
        fileName: pathSegments[pathSegments.length - 1] || fallbackName,
      };
    });

    const hasMultipleArchives = new Set(parsedPages.map((page) => page.archiveId).filter(Boolean)).size > 1;
    const root: MutableFileTreeFolderNode = {
      id: '',
      name: '',
      firstPageIndex: 0,
      folders: new Map(),
      files: [],
    };
    const pageAncestors: Record<number, string[]> = {};
    const topLevelFolderIds = new Set<string>();
    const allFolderIds = new Set<string>();

    parsedPages.forEach((page) => {
      const segments = page.segments.length > 0 ? [...page.segments] : [page.fileName];
      if (hasMultipleArchives) {
        segments.unshift(page.archiveId || t('reader.unknownArchive'));
      }

      const fileName = segments[segments.length - 1] || page.fileName;
      const folderSegments = segments.slice(0, -1);

      let folder = root;
      let folderPath = '';
      const ancestors: string[] = [];

      folderSegments.forEach((segment, depth) => {
        const folderId = folderPath ? `${folderPath}/${segment}` : segment;
        let next = folder.folders.get(segment);
        if (!next) {
          next = {
            id: folderId,
            name: segment,
            firstPageIndex: page.pageIndex,
            folders: new Map(),
            files: [],
          };
          folder.folders.set(segment, next);
          allFolderIds.add(folderId);
          if (depth === 0) {
            topLevelFolderIds.add(folderId);
          }
        } else if (page.pageIndex < next.firstPageIndex) {
          next.firstPageIndex = page.pageIndex;
        }

        folder = next;
        folderPath = folderId;
        ancestors.push(folderId);
      });

      const fileIdBase = folderPath ? `${folderPath}/${fileName}` : fileName;
      folder.files.push({
        kind: 'file',
        id: `${fileIdBase}#${page.pageIndex}`,
        name: fileName,
        pageIndex: page.pageIndex,
        pageType: page.pageType,
      });
      pageAncestors[page.pageIndex] = ancestors;
    });

    const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });
    const convertTree = (folder: MutableFileTreeFolderNode): FileTreeNode[] => {
      const folders = [...folder.folders.values()]
        .sort((a, b) => collator.compare(a.name, b.name))
        .map<FileTreeFolderNode>((child) => ({
          kind: 'folder',
          id: child.id,
          name: child.name,
          firstPageIndex: child.firstPageIndex,
          children: convertTree(child),
        }));

      const files = [...folder.files].sort((a, b) => collator.compare(a.name, b.name));
      return [...folders, ...files];
    };

    return {
      nodes: convertTree(root),
      allFolderIds: [...allFolderIds],
      topLevelFolderIds: [...topLevelFolderIds],
      pageAncestors,
    };
  }, [allPages, t]);

  const toggleFolder = useCallback((folderId: string) => {
    setExpandedFolderIds((prev) => {
      const next = new Set(prev);
      if (next.has(folderId)) {
        next.delete(folderId);
      } else {
        next.add(folderId);
      }
      return next;
    });
  }, []);

  useEffect(() => {
    const validFolders = new Set(fileTree.allFolderIds);
    if (validFolders.size === 0) {
      setExpandedFolderIds((prev) => (prev.size === 0 ? prev : new Set()));
      return;
    }

    setExpandedFolderIds((prev) => {
      const next = new Set<string>();
      prev.forEach((folderId) => {
        if (validFolders.has(folderId)) {
          next.add(folderId);
        }
      });

      if (next.size === 0) {
        fileTree.topLevelFolderIds.forEach((folderId) => next.add(folderId));
      }

      const activeAncestors = fileTree.pageAncestors[currentPage] || [];
      activeAncestors.forEach((folderId) => {
        if (validFolders.has(folderId)) {
          next.add(folderId);
        }
      });

      if (next.size === prev.size) {
        let identical = true;
        prev.forEach((folderId) => {
          if (!next.has(folderId)) {
            identical = false;
          }
        });
        if (identical) return prev;
      }
      return next;
    });
  }, [currentPage, fileTree]);

  useEffect(() => {
    if (!open || activeTab !== 'tree') return;
    const scrollElement = fileTreeScrollRef.current;
    if (!scrollElement) return;

    const activeElement = scrollElement.querySelector(`[data-file-tree-page-index="${currentPage}"]`) as HTMLElement | null;
    if (!activeElement) return;

    const elementTop = activeElement.offsetTop;
    const elementBottom = elementTop + activeElement.offsetHeight;
    const viewTop = scrollElement.scrollTop;
    const viewBottom = viewTop + scrollElement.clientHeight;

    if (elementTop >= viewTop + 20 && elementBottom <= viewBottom - 20) return;

    scrollElement.scrollTop = Math.max(
      0,
      elementTop - Math.max(0, (scrollElement.clientHeight - activeElement.offsetHeight) / 2)
    );
  }, [activeTab, currentPage, expandedFolderIds, open]);

  function renderFileTreeNode(node: FileTreeNode, depth: number): React.ReactNode {
    if (node.kind === 'folder') {
      const isExpanded = expandedFolderIds.has(node.id);
      return (
        <div key={node.id}>
          <button
            type="button"
            onClick={() => toggleFolder(node.id)}
            className="w-full h-7 rounded-md hover:bg-muted/70 transition-colors flex items-center gap-1 text-xs text-left"
            style={{ paddingLeft: `${FILE_TREE_ROW_LEFT_PADDING_PX + (depth * FILE_TREE_DEPTH_INDENT_PX)}px` }}
            title={node.name}
          >
            {isExpanded ? <ChevronDown className="w-3 h-3 text-muted-foreground" /> : <ChevronRight className="w-3 h-3 text-muted-foreground" />}
            <Folder className="w-3.5 h-3.5 text-primary/80 shrink-0" />
            <span className="truncate">{node.name}</span>
          </button>
          {isExpanded ? (
            <div>
              {node.children.map((child) => renderFileTreeNode(child, depth + 1))}
            </div>
          ) : null}
        </div>
      );
    }

    const isActive = node.pageIndex === currentPage;
    const fileIcon = node.pageType === 'video'
      ? <Film className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
      : node.pageType === 'html'
        ? <FileText className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
        : <ImageIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />;

    return (
      <button
        key={node.id}
        type="button"
        data-file-tree-page-index={node.pageIndex}
        onClick={() => onSelectPage(node.pageIndex)}
        className={`w-full h-7 rounded-md transition-colors flex items-center gap-1.5 text-xs text-left ${
          isActive ? 'bg-accent text-accent-foreground' : 'hover:bg-muted/70'
        }`}
        style={{ paddingLeft: `${FILE_TREE_ROW_LEFT_PADDING_PX + (depth * FILE_TREE_DEPTH_INDENT_PX)}px` }}
        title={node.name}
      >
        {fileIcon}
        <span className="truncate flex-1">{node.name}</span>
        <span className="text-[10px] text-muted-foreground shrink-0 pr-1">{node.pageIndex + 1}</span>
      </button>
    );
  }

  useEffect(() => {
    const isScrollableSidebarTab = activeTab === 'thumbnails' || activeTab === 'list';
    if (!open || !isScrollableSidebarTab) {
      wasOpenRef.current = false;
      return;
    }

    const sidebarElement = sidebarScrollRef.current;
    if (!sidebarElement) return;
    if (currentPage < 0 || currentPage >= sidebarDisplayPages.length) return;

    const openingNow = !wasOpenRef.current;
    wasOpenRef.current = true;

    const rafId = requestAnimationFrame(() => {
      const container = sidebarScrollRef.current;
      if (!container) return;

      const viewTop = container.scrollTop;
      const viewBottom = viewTop + container.clientHeight;
      const maxScrollTop = Math.max(0, container.scrollHeight - container.clientHeight);

      let itemTop = 0;
      let itemHeight = 0;

      if (activeTab === 'thumbnails' && !isEpub && canVirtualizeGrid) {
        const rowIndex = Math.floor(currentPage / sidebarColumns);
        itemTop = rowIndex * rowHeight;
        itemHeight = thumbHeight || rowHeight || 1;
      } else {
        const itemEl = container.querySelector(`[data-sidebar-item-index="${currentPage}"]`) as HTMLElement | null;
        if (!itemEl) return;
        itemTop = itemEl.offsetTop;
        itemHeight = itemEl.offsetHeight || 1;
      }

      const itemBottom = itemTop + itemHeight;
      const keepVisiblePadding = isEpub ? 96 : Math.max(64, rowHeight);
      const outsideViewport =
        itemTop < viewTop + keepVisiblePadding ||
        itemBottom > viewBottom - keepVisiblePadding;

      if (!openingNow && !outsideViewport) return;

      const targetScrollTop = Math.max(
        0,
        Math.min(maxScrollTop, itemTop - Math.max(0, (container.clientHeight - itemHeight) / 2))
      );

      if (Math.abs(targetScrollTop - viewTop) <= 2) return;
      container.scrollTop = targetScrollTop;
      setSidebarScrollTop(targetScrollTop);
    });

    return () => cancelAnimationFrame(rafId);
  }, [
    canVirtualizeGrid,
    currentPage,
    isEpub,
    activeTab,
    open,
    rowHeight,
    sidebarColumns,
    sidebarDisplayPages.length,
    sidebarScrollRef,
    thumbHeight,
  ]);

  if (!open) return null;

  const renderListItem = (page: PageInfo, index: number) => {
    const displayTitle = getPageDisplayTitle(page, index, t);
    const description = getPageDisplayDescription(page);
    const metadataThumb = getPageDisplayThumb(page);
    const pagePathSegments = getPagePathSegments(page.path);
    const fileName = pagePathSegments[pagePathSegments.length - 1] || '';
    const subtitle = fileName && fileName !== displayTitle ? fileName : '';
    const pageIcon = page.type === 'video'
      ? <Film className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
      : page.type === 'html'
        ? <FileText className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
        : <ImageIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />;

    return (
      <button
        key={index}
        data-sidebar-item-index={index}
        onClick={() => onSelectPage(index)}
        className={`w-full flex items-center gap-2 p-2 rounded-lg transition-colors text-left ${
          currentPage === index ? 'bg-accent text-accent-foreground' : 'hover:bg-muted'
        }`}
      >
        {metadataThumb ? (
          <MemoizedImage
            src={metadataThumb}
            alt={displayTitle}
            className="w-14 h-10 rounded-md object-cover bg-muted shrink-0"
            decoding="async"
            loading="lazy"
            draggable={false}
          />
        ) : (
          <span className="flex-shrink-0 w-7 h-7 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-medium">
            {index + 1}
          </span>
        )}
        <span className="min-w-0 flex-1">
          <span className="block truncate text-xs sm:text-sm">{displayTitle}</span>
          {description ? (
            <span className="block truncate text-[11px] text-muted-foreground">
              {description}
            </span>
          ) : subtitle ? (
            <span className="block truncate text-[11px] text-muted-foreground">
              {subtitle}
            </span>
          ) : null}
        </span>
        <span className="shrink-0 opacity-80">{pageIcon}</span>
      </button>
    );
  };

  const showListMode = activeTab === 'list' || isEpub;

  const sidebarHeader = (
    <div className="px-3 pt-2 pb-2">
      <div className="flex items-center justify-between gap-3 rounded-lg border border-border/60 bg-background/55 px-2 py-1.5 backdrop-blur-md shadow-sm shadow-black/10">
        <div className="min-w-0 text-xs text-muted-foreground font-medium truncate">
          {t('reader.sidebarItemsCount').replace('{count}', String(allPages.length))}
        </div>
        <div className="inline-flex items-center gap-1 rounded-md bg-muted/60 p-0.5">
          <button
            type="button"
            onClick={() => setActiveTab('thumbnails')}
            title={t('reader.sidebarThumbnails')}
            aria-label={t('reader.sidebarThumbnails')}
            aria-pressed={activeTab === 'thumbnails'}
            className={`h-9 w-9 sm:h-7 sm:w-7 rounded-md transition-colors flex items-center justify-center touch-manipulation ${
              activeTab === 'thumbnails'
                ? 'bg-primary/20 text-primary ring-1 ring-primary/55 shadow-sm shadow-primary/20'
                : 'text-muted-foreground/80 hover:text-foreground hover:bg-background/35'
            }`}
          >
            <ImageIcon className={`w-3.5 h-3.5 ${activeTab === 'thumbnails' ? 'opacity-100' : 'opacity-70'}`} />
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('list')}
            title={t('reader.sidebarList')}
            aria-label={t('reader.sidebarList')}
            aria-pressed={activeTab === 'list'}
            className={`h-9 w-9 sm:h-7 sm:w-7 rounded-md transition-colors flex items-center justify-center touch-manipulation ${
              activeTab === 'list'
                ? 'bg-primary/20 text-primary ring-1 ring-primary/55 shadow-sm shadow-primary/20'
                : 'text-muted-foreground/80 hover:text-foreground hover:bg-background/35'
            }`}
          >
            <List className={`w-3.5 h-3.5 ${activeTab === 'list' ? 'opacity-100' : 'opacity-70'}`} />
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('tree')}
            title={t('reader.fileTree')}
            aria-label={t('reader.fileTree')}
            aria-pressed={activeTab === 'tree'}
            className={`h-9 w-9 sm:h-7 sm:w-7 rounded-md transition-colors flex items-center justify-center touch-manipulation ${
              activeTab === 'tree'
                ? 'bg-primary/20 text-primary ring-1 ring-primary/55 shadow-sm shadow-primary/20'
                : 'text-muted-foreground/80 hover:text-foreground hover:bg-background/35'
            }`}
          >
            <Folder className={`w-3.5 h-3.5 ${activeTab === 'tree' ? 'opacity-100' : 'opacity-70'}`} />
          </button>
        </div>
      </div>
    </div>
  );

  const sidebarMainContent = activeTab === 'tree' ? (
    <div ref={fileTreeScrollRef} className={`flex-1 overflow-y-auto ${SIDEBAR_CONTENT_PADDING_CLASS}`}>
      {fileTree.nodes.length > 0 ? (
        <div className="space-y-0.5">
          {fileTree.nodes.map((node) => renderFileTreeNode(node, 0))}
        </div>
      ) : (
        <p className="py-3 text-xs text-muted-foreground">{t('reader.fileTreeEmpty')}</p>
      )}
    </div>
  ) : (
    <div
      ref={sidebarScrollRef}
      className="flex-1 overflow-y-auto"
      onScroll={(e) => setSidebarScrollTop(e.currentTarget.scrollTop)}
    >
      <div className={SIDEBAR_CONTENT_PADDING_CLASS}>
        {sidebarLoading ? (
          <div className="flex items-center justify-center py-12">
            <Spinner />
          </div>
        ) : showListMode ? (
          <div className="space-y-1">
            {sidebarDisplayPages.map((page, index) => (
              isEpub ? (
                <button
                  key={index}
                  data-sidebar-item-index={index}
                  onClick={() => onSelectPage(index)}
                  className={`w-full flex items-center gap-3 p-3 rounded-lg hover:bg-muted transition-colors group text-left ${
                    currentPage === index ? 'bg-accent text-accent-foreground' : ''
                  }`}
                >
                  <span className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 text-primary flex items-center justify-center text-sm font-medium">
                    {index + 1}
                  </span>
                  <span className="flex-1 truncate text-sm group-hover:text-primary transition-colors">
                    {page.title || `${t('archive.chapter')} ${index + 1}`}
                  </span>
                  <Book className="w-4 h-4 text-muted-foreground group-hover:text-primary transition-colors" />
                </button>
              ) : (
                renderListItem(page, index)
              )
            ))}
          </div>
        ) : (
          <>
            {canVirtualizeGrid ? (
              <div className="relative" style={{ height: `${totalHeight}px` }}>
                {visibleThumbs.map(({ page, index, top, left }) => {
                  const isCurrentPage = currentPage === index;
                  const metadataThumb = getPageDisplayThumb(page);
                  const showVideoPreview = page.type === 'video' && !metadataThumb;
                  const thumbSrc = metadataThumb || page.url;
                  const thumbAlt = getPageDisplayTitle(page, index, t);
                  return (
                    <button
                      key={index}
                      data-sidebar-item-index={index}
                      onClick={() => onSelectPage(index)}
                      className={`group absolute bg-muted rounded-lg overflow-hidden hover:ring-2 hover:ring-primary transition-all duration-200 ${
                        isCurrentPage ? 'ring-2 ring-primary' : ''
                      }`}
                      style={{
                        top,
                        left,
                        width: `${thumbWidth}px`,
                        height: `${thumbHeight}px`,
                      }}
                    >
                      {isCurrentPage && (
                        <div className="absolute inset-0 bg-primary/10 z-10 flex items-center justify-center">
                          <div className="bg-primary text-primary-foreground text-xs px-2 py-1 rounded-full font-medium">
                            {index + 1}
                          </div>
                        </div>
                      )}

                      <div className="relative w-full h-full">
                        {showVideoPreview ? (
                          <video
                            src={page.url}
                            className="w-full h-full object-cover"
                            muted
                            loop
                            playsInline
                            onMouseEnter={(e) => {
                              const video = e.target as HTMLVideoElement;
                              video.play().catch(() => {});
                            }}
                            onMouseLeave={(e) => {
                              const video = e.target as HTMLVideoElement;
                              video.pause();
                              video.currentTime = 0;
                            }}
                          />
                        ) : (
                          <MemoizedImage
                            src={thumbSrc}
                            alt={thumbAlt || t('archive.previewPage')
                              .replace('{current}', String(index + 1))
                              .replace('{total}', String(pagesLength))}
                            className={SIDEBAR_THUMB_IMAGE_CLASS}
                            decoding="async"
                            loading="lazy"
                            draggable={false}
                          />
                        )}
                      </div>

                      <div className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-xs py-1 px-1 text-center truncate">
                        {index + 1}
                        {page.type === 'video' ? ' 🎬' : ''}
                      </div>
                    </button>
                  );
                })}
              </div>
            ) : (
              <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
                {sidebarDisplayPages.map((page, index) => {
                  const isCurrentPage = currentPage === index;
                  const metadataThumb = getPageDisplayThumb(page);
                  const showVideoPreview = page.type === 'video' && !metadataThumb;
                  const thumbSrc = metadataThumb || page.url;
                  const thumbAlt = getPageDisplayTitle(page, index, t);

                  return (
                    <button
                      key={index}
                      data-sidebar-item-index={index}
                      onClick={() => onSelectPage(index)}
                      className={`group relative aspect-[3/4] bg-muted rounded-lg overflow-hidden hover:ring-2 hover:ring-primary transition-all duration-200 ${
                        isCurrentPage ? 'ring-2 ring-primary' : ''
                      }`}
                    >
                      {isCurrentPage && (
                        <div className="absolute inset-0 bg-primary/10 z-10 flex items-center justify-center">
                          <div className="bg-primary text-primary-foreground text-xs px-2 py-1 rounded-full font-medium">
                            {index + 1}
                          </div>
                        </div>
                      )}

                      <div className="relative w-full h-full">
                        {showVideoPreview ? (
                          <video
                            src={page.url}
                            className="w-full h-full object-cover"
                            muted
                            loop
                            playsInline
                            onMouseEnter={(e) => {
                              const video = e.target as HTMLVideoElement;
                              video.play().catch(() => {});
                            }}
                            onMouseLeave={(e) => {
                              const video = e.target as HTMLVideoElement;
                              video.pause();
                              video.currentTime = 0;
                            }}
                          />
                        ) : (
                          <MemoizedImage
                            src={thumbSrc}
                            alt={thumbAlt || t('archive.previewPage')
                              .replace('{current}', String(index + 1))
                              .replace('{total}', String(pagesLength))}
                            className={SIDEBAR_THUMB_IMAGE_CLASS}
                            decoding="async"
                            loading="lazy"
                            draggable={false}
                          />
                        )}
                      </div>

                      <div className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-xs py-1 px-1 text-center truncate">
                        {index + 1}
                        {page.type === 'video' ? ' 🎬' : ''}
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </>
        )}

        {!isEpub && canLoadMore && (
          <div className="mt-3 text-center">
            <Button variant="outline" onClick={onLoadMore} disabled={sidebarLoading} className="w-full">
              {sidebarLoading ? <Spinner className="mr-2" /> : null}
              {t('archive.loadMore')}
            </Button>
          </div>
        )}
      </div>
    </div>
  );

  if (isMobileViewport) {
    return (
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent
          side="bottom"
          showCloseButton={false}
          className="h-[82dvh] p-0 rounded-t-2xl border-t border-border/70 bg-background"
        >
          <div className="h-full flex flex-col" onWheel={(e) => e.stopPropagation()}>
            <div className="flex justify-center pt-2">
              <div className="h-1.5 w-10 rounded-full bg-muted-foreground/40" />
            </div>
            {sidebarHeader}
            {sidebarMainContent}
          </div>
        </SheetContent>
      </Sheet>
    );
  }

  return (
    <div
      className="absolute left-0 top-0 bottom-0 hidden md:flex w-[280px] lg:w-[320px] bg-background/95 backdrop-blur-sm border-r border-border z-40 flex-col"
      onWheel={(e) => e.stopPropagation()}
    >
      {sidebarHeader}
      {sidebarMainContent}
    </div>
  );
}
