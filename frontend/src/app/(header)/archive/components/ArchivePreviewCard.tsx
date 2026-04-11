'use client';

import Link from 'next/link';
import { ChevronDown, ChevronRight, FileText, Film, Folder, ImageIcon, List, Music } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type React from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import type { ArchiveMetadata } from '@/types/archive';
import { ArchiveService, type PageInfo } from '@/lib/services/archive-service';
import { MasonryThumbnailGrid } from '@/components/ui/masonry-thumbnail-grid';
import { MemoizedImage } from '@/components/reader/components/MemoizedMedia';
import { useLocalStorage } from '@/hooks/common-hooks';
import { getPageReleaseAt } from '@/lib/utils/tv-media';

type ArchivePreviewViewMode = 'thumbnails' | 'list' | 'tree';

const ARCHIVE_PREVIEW_VIEW_MODE_STORAGE_KEY = 'archive_preview_view_mode';

function isArchivePreviewViewMode(value: unknown): value is ArchivePreviewViewMode {
  return value === 'thumbnails' || value === 'list' || value === 'tree';
}

function getPageCustomTitle(page: PageInfo): string {
  return ArchiveService.getPageDisplayTitle(page);
}

function getPageDisplayTitle(page: PageInfo, pageIndex: number, t: (key: string) => string, archivetype: string): string {
  const customTitle = getPageCustomTitle(page);
  if (customTitle) return customTitle;
  if (archivetype === 'epub') {
    return `${t('archive.chapter')} ${pageIndex + 1}`;
  }
  return t('reader.pageAlt').replace('{page}', String(pageIndex + 1));
}

function getPageDisplayDescription(page: PageInfo): string {
  const releaseAt = getPageReleaseAt(page);
  const description = ArchiveService.getPageDisplayMetadata(page)?.description?.trim() || '';
  if (!releaseAt) return description;
  return description ? `${releaseAt} · ${description}` : releaseAt;
}

function getPageDisplayThumb(page: PageInfo): string {
  return ArchiveService.getPageDisplayMetadata(page)?.thumb?.trim() || '';
}

function getPagePathSegments(path: string): string[] {
  return String(path || '')
    .split('/')
    .map((segment) => segment.trim())
    .filter(Boolean);
}

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
  children: FileTreeNode[];
};

type FileTreeNode = FileTreeFolderNode | FileTreeFileNode;

type MutableFileTreeFolderNode = {
  id: string;
  name: string;
  folders: Map<string, MutableFileTreeFolderNode>;
  files: FileTreeFileNode[];
};

type Props = {
  metadata: ArchiveMetadata;
  t: (key: string) => string;
  previewLoading: boolean;
  previewError: string | null;
  pages: PageInfo[];
};

export function ArchivePreviewCard({
  metadata,
  t,
  previewLoading,
  previewError,
  pages,
}: Props) {
  const [storedPreviewViewMode, setStoredPreviewViewMode] = useLocalStorage<ArchivePreviewViewMode>(
    ARCHIVE_PREVIEW_VIEW_MODE_STORAGE_KEY,
    'thumbnails'
  );
  const previewViewMode = isArchivePreviewViewMode(storedPreviewViewMode) ? storedPreviewViewMode : 'thumbnails';
  const treeScrollRef = useRef<HTMLDivElement | null>(null);
  const [expandedFolderIds, setExpandedFolderIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (storedPreviewViewMode !== previewViewMode) {
      setStoredPreviewViewMode(previewViewMode);
    }
  }, [previewViewMode, setStoredPreviewViewMode, storedPreviewViewMode]);

  const setPreviewViewMode = useCallback((nextMode: ArchivePreviewViewMode) => {
    setStoredPreviewViewMode(nextMode);
  }, [setStoredPreviewViewMode]);

  const fileTree = useMemo(() => {
    const root: MutableFileTreeFolderNode = {
      id: '',
      name: '',
      folders: new Map(),
      files: [],
    };
    const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });

    pages.forEach((page, pageIndex) => {
      const pathSegments = getPagePathSegments(ArchiveService.getPagePath(page));
      const fallbackName = getPageDisplayTitle(page, pageIndex, t, String(metadata.archivetype || ''));
      const segments = pathSegments.length > 0 ? [...pathSegments] : [fallbackName];
      const fileName = segments[segments.length - 1] || fallbackName;
      const folderSegments = segments.slice(0, -1);

      let folder = root;
      let folderPath = '';

      folderSegments.forEach((segment) => {
        const folderId = folderPath ? `${folderPath}/${segment}` : segment;
        let next = folder.folders.get(segment);
        if (!next) {
          next = {
            id: folderId,
            name: segment,
            folders: new Map(),
            files: [],
          };
          folder.folders.set(segment, next);
        }
        folder = next;
        folderPath = folderId;
      });

      const fileIdBase = folderPath ? `${folderPath}/${fileName}` : fileName;
      folder.files.push({
        kind: 'file',
        id: `${fileIdBase}#${pageIndex}`,
        name: fileName,
        pageIndex,
        pageType: page.type,
      });
    });

    const convertTree = (folder: MutableFileTreeFolderNode): FileTreeNode[] => {
      const folders = [...folder.folders.values()]
        .sort((a, b) => collator.compare(a.name, b.name))
        .map<FileTreeFolderNode>((child) => ({
          kind: 'folder',
          id: child.id,
          name: child.name,
          children: convertTree(child),
        }));
      const files = [...folder.files].sort((a, b) => collator.compare(a.name, b.name));
      return [...folders, ...files];
    };

    return { nodes: convertTree(root) };
  }, [metadata.archivetype, pages, t]);

  useEffect(() => {
    const validFolderIds = new Set<string>();
    const walk = (nodes: FileTreeNode[]) => {
      nodes.forEach((node) => {
        if (node.kind === 'folder') {
          validFolderIds.add(node.id);
          walk(node.children);
        }
      });
    };
    walk(fileTree.nodes);

    setExpandedFolderIds((prev) => {
      const next = new Set<string>();
      prev.forEach((folderId) => {
        if (validFolderIds.has(folderId)) next.add(folderId);
      });

      if (next.size === 0) {
        fileTree.nodes.forEach((node) => {
          if (node.kind === 'folder') next.add(node.id);
        });
      }

      if (next.size === prev.size) {
        let identical = true;
        prev.forEach((folderId) => {
          if (!next.has(folderId)) identical = false;
        });
        if (identical) return prev;
      }

      return next;
    });
  }, [fileTree]);

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

  function renderFileTreeNode(node: FileTreeNode, depth: number): React.ReactNode {
    if (node.kind === 'folder') {
      const isExpanded = expandedFolderIds.has(node.id);
      return (
        <div key={node.id}>
          <button
            type="button"
            onClick={() => toggleFolder(node.id)}
            className="flex h-7 w-full items-center gap-1 rounded-md text-left text-xs transition-colors hover:bg-muted/70"
            style={{ paddingLeft: `${6 + (depth * 14)}px` }}
            title={node.name}
          >
            {isExpanded ? (
              <ChevronDown className="h-3 w-3 shrink-0 text-muted-foreground" />
            ) : (
              <ChevronRight className="h-3 w-3 shrink-0 text-muted-foreground" />
            )}
            <Folder className="h-3.5 w-3.5 shrink-0 text-primary/80" />
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

    const pageIcon = node.pageType === 'video'
      ? <Film className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
      : node.pageType === 'audio'
        ? <Music className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
        : node.pageType === 'html'
          ? <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          : <ImageIcon className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />;

    return (
      <Link
        key={node.id}
        href={`/reader?id=${metadata.arcid}&page=${node.pageIndex + 1}`}
        className="flex h-7 w-full items-center gap-1.5 rounded-md text-left text-xs transition-colors hover:bg-muted/70"
        style={{ paddingLeft: `${6 + (depth * 14)}px` }}
        title={node.name}
      >
        {pageIcon}
        <span className="min-w-0 flex-1 truncate">{node.name}</span>
        <span className="shrink-0 pr-1 text-[10px] text-muted-foreground">{node.pageIndex + 1}</span>
      </Link>
    );
  }

  const renderPageListItem = useCallback((page: PageInfo, index: number) => {
    const displayTitle = getPageDisplayTitle(page, index, t, String(metadata.archivetype || ''));
    const description = getPageDisplayDescription(page);
    const metadataThumb = getPageDisplayThumb(page);
    const pageUrl = ArchiveService.getResolvedPageUrl(page);
    const thumbSrc = metadataThumb || (page.type === 'image' ? pageUrl : '');
    const pagePathSegments = getPagePathSegments(ArchiveService.getPagePath(page));
    const fileName = pagePathSegments[pagePathSegments.length - 1] || '';
    const subtitle = fileName && fileName !== displayTitle ? fileName : '';
    const pageIcon = page.type === 'video'
      ? <Film className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
      : page.type === 'audio'
        ? <Music className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
        : page.type === 'html'
          ? <FileText className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
          : <ImageIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />;

    return (
      <Link
        key={index}
        href={`/reader?id=${metadata.arcid}&page=${index + 1}`}
        className="flex items-center gap-3 rounded-lg p-3 text-left transition-colors group hover:bg-muted"
      >
        {thumbSrc ? (
          <MemoizedImage
            src={thumbSrc}
            alt={displayTitle}
            className="h-10 w-14 shrink-0 rounded-md bg-muted object-cover"
            decoding="async"
            loading="lazy"
            draggable={false}
          />
        ) : (
          <span className="flex h-10 w-14 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
            {page.type === 'video' ? <Film className="h-4 w-4" /> : null}
            {page.type === 'audio' ? <Music className="h-4 w-4" /> : null}
            {page.type === 'html' ? <FileText className="h-4 w-4" /> : null}
            {page.type === 'image' ? <ImageIcon className="h-4 w-4" /> : null}
          </span>
        )}
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm transition-colors group-hover:text-primary">
            {displayTitle}
          </span>
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
      </Link>
    );
  }, [metadata.arcid, metadata.archivetype, t]);

  return (
    <Card className="border-none bg-transparent shadow-none dark:bg-transparent">
      {/* When collapsed, default CardHeader padding makes the row feel a bit low; tighten it. */}
      <CardHeader className="!p-0">
        <div className="flex items-center gap-2">
          <CardTitle className="text-lg font-semibold lg:text-xl">
            {t('archive.paginationInfo')}
          </CardTitle>
          <div className="inline-flex items-center gap-1 rounded-md bg-muted/60 p-0.5">
            <button
              type="button"
              onClick={() => setPreviewViewMode('thumbnails')}
              title={t('archive.switchToThumbnailsView')}
              aria-label={t('archive.switchToThumbnailsView')}
              aria-pressed={previewViewMode === 'thumbnails'}
              className={`inline-flex h-8 w-8 items-center justify-center rounded-md transition-colors ${
                previewViewMode === 'thumbnails'
                  ? 'bg-primary/20 text-primary ring-1 ring-primary/55 shadow-xs shadow-primary/20'
                  : 'text-muted-foreground/80 hover:bg-background/35 hover:text-foreground'
              }`}
            >
              <ImageIcon className={`h-4 w-4 ${previewViewMode === 'thumbnails' ? 'opacity-100' : 'opacity-70'}`} />
            </button>
            <button
              type="button"
              onClick={() => setPreviewViewMode('list')}
              title={t('archive.switchToListView')}
              aria-label={t('archive.switchToListView')}
              aria-pressed={previewViewMode === 'list'}
              className={`inline-flex h-8 w-8 items-center justify-center rounded-md transition-colors ${
                previewViewMode === 'list'
                  ? 'bg-primary/20 text-primary ring-1 ring-primary/55 shadow-xs shadow-primary/20'
                  : 'text-muted-foreground/80 hover:bg-background/35 hover:text-foreground'
              }`}
            >
              <List className={`h-4 w-4 ${previewViewMode === 'list' ? 'opacity-100' : 'opacity-70'}`} />
            </button>
            <button
              type="button"
              onClick={() => setPreviewViewMode('tree')}
              title={t('archive.switchToTreeView')}
              aria-label={t('archive.switchToTreeView')}
              aria-pressed={previewViewMode === 'tree'}
              className={`inline-flex h-8 w-8 items-center justify-center rounded-md transition-colors ${
                previewViewMode === 'tree'
                  ? 'bg-primary/20 text-primary ring-1 ring-primary/55 shadow-xs shadow-primary/20'
                  : 'text-muted-foreground/80 hover:bg-background/35 hover:text-foreground'
              }`}
            >
              <Folder className={`h-4 w-4 ${previewViewMode === 'tree' ? 'opacity-100' : 'opacity-70'}`} />
            </button>
          </div>
        </div>
      </CardHeader>

      <CardContent className="!p-0 mt-3 space-y-4">
        {previewLoading ? (
          <div className="flex items-center justify-center py-0">
            <p className="text-muted-foreground">{t('common.loading')}</p>
          </div>
        ) : previewError ? (
          <div className="flex items-center justify-center py-0">
            <p className="text-red-500">{previewError}</p>
          </div>
        ) : pages.length === 0 ? (
          <div className="flex items-center justify-center py-0">
            <p className="text-muted-foreground">{t('archive.noPreviewPages')}</p>
          </div>
        ) : (
          <div className="space-y-4">
            {previewViewMode === 'thumbnails' ? (
              <MasonryThumbnailGrid
                pages={pages}
                archiveId={metadata.arcid}
                isLink={true}
                t={t}
                className="h-[500px]"
                contentClassName="p-0"
              />
            ) : previewViewMode === 'tree' ? (
              <div ref={treeScrollRef} className="max-h-[500px] space-y-0.5 overflow-y-auto pr-1">
                {fileTree.nodes.length > 0 ? (
                  <div className="space-y-0.5">
                    {fileTree.nodes.map((node) => renderFileTreeNode(node, 0))}
                  </div>
                ) : (
                  <p className="py-3 text-xs text-muted-foreground">{t('reader.fileTreeEmpty')}</p>
                )}
              </div>
            ) : (
              <div className="max-h-[500px] space-y-1 overflow-y-auto pr-1">
                {pages.map((page, index) => renderPageListItem(page, index))}
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
