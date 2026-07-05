'use client';

import type { MouseEvent as ReactMouseEvent, ReactNode } from 'react';
import { useCallback, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  BookOpen,
  CheckCircle,
  Download,
  Edit,
  Heart,
  RotateCcw,
  Square,
  Trash2,
} from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu';
import { BaseMediaCardEditController } from '@/components/ui/base-media-card-edit-controller';
import { useAuth } from '@/contexts/AuthContext';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { useLanguage } from '@/contexts/LanguageContext';
import { useToast } from '@/hooks/use-toast';
import { ArchiveService } from '@/lib/services/archive-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { appEvents, AppEvents } from '@/lib/utils/events';
import { logger } from '@/lib/utils/logger';
import { buildReaderPath } from '@/lib/utils/reader';

type HomeMediaItemType = 'archive' | 'tankoubon';

type RenderState = {
  displayDescription: string;
  displayTags: string;
  displayTitle: string;
  favoriteLoading: boolean;
  handleContextMenu: (event: ReactMouseEvent<HTMLElement>) => void;
  handleContextMenuCapture: (event: ReactMouseEvent<HTMLElement>) => void;
  isFavorite: boolean;
  isNew: boolean;
  navigateToReader: () => void;
  toggleFavorite: () => Promise<void>;
  toggleSelected: (nextSelected?: boolean) => void;
};

type SyncedValue<T> = {
  source: T;
  value: T;
} | null;

type Props = {
  children: (state: RenderState) => ReactNode;
  description: string;
  id: string;
  isFavorite?: boolean;
  isNew?: boolean;
  progress?: number;
  readerTargetId?: string;
  selectable?: boolean;
  selected?: boolean;
  selectionMode?: boolean;
  tags: string;
  thumbnailAssetId?: number;
  title: string;
  type: HomeMediaItemType;
  onRequestEnterSelection?: () => void;
  onToggleSelect?: (selected: boolean) => void;
};

function resolveSyncedValue<T>(state: SyncedValue<T>, source: T): T {
  return state !== null && Object.is(state.source, source) ? state.value : source;
}

export function HomeMediaItemMenu({
  children,
  description,
  id,
  isFavorite: initialFavorite = false,
  isNew: initialIsNew = false,
  progress,
  readerTargetId,
  selectable = false,
  selected = false,
  selectionMode = false,
  tags,
  thumbnailAssetId,
  title,
  type,
  onRequestEnterSelection,
  onToggleSelect,
}: Props) {
  const router = useRouter();
  const { t } = useLanguage();
  const { isAuthenticated, user } = useAuth();
  const { error: showError } = useToast();
  const { confirm } = useConfirmContext();
  const baseDescription = description || '';
  const baseTags = tags || '';
  const baseFavorite = Boolean(initialFavorite);
  const baseIsNew = Boolean(initialIsNew);

  const [menuOpen, setMenuOpen] = useState(false);
  const [menuPosition, setMenuPosition] = useState({ x: 0, y: 0 });
  const [displayTitleState, setDisplayTitleState] = useState<SyncedValue<string>>(null);
  const [displayDescriptionState, setDisplayDescriptionState] = useState<SyncedValue<string>>(null);
  const [displayTagsState, setDisplayTagsState] = useState<SyncedValue<string>>(null);
  const [favoriteState, setFavoriteState] = useState<SyncedValue<boolean>>(null);
  const [isNewState, setIsNewState] = useState<SyncedValue<boolean>>(null);
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const [isNewStatusLoading, setIsNewStatusLoading] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [editOpen, setEditOpen] = useState(false);

  const isAdmin = user?.isAdmin === true;
  const canEdit = isAuthenticated;
  const canDelete = type === 'archive' ? isAdmin : isAuthenticated;
  const detailPath = type === 'archive' ? `/archive?id=${id}` : `/tankoubon?id=${id}`;
  const readerPath = readerTargetId
    ? buildReaderPath(readerTargetId, type === 'archive' ? progress : undefined, type !== 'archive' ? id : undefined)
    : detailPath;
  const menuActionDisabled = deleting;
  const displayTitle = resolveSyncedValue(displayTitleState, title);
  const displayDescription = resolveSyncedValue(displayDescriptionState, baseDescription);
  const displayTags = resolveSyncedValue(displayTagsState, baseTags);
  const isFavorite = resolveSyncedValue(favoriteState, baseFavorite);
  const isNew = resolveSyncedValue(isNewState, baseIsNew);

  const emitRefresh = useCallback(() => {
    appEvents.emit(AppEvents.ARCHIVES_REFRESH);
  }, []);

  const navigateToReader = useCallback(() => {
    router.push(readerPath);
  }, [readerPath, router]);

  const toggleSelected = useCallback((nextSelected?: boolean) => {
    if (!selectable || !onToggleSelect) return;
    const value = typeof nextSelected === 'boolean' ? nextSelected : !selected;
    if (value && !selectionMode) onRequestEnterSelection?.();
    onToggleSelect(value);
  }, [onRequestEnterSelection, onToggleSelect, selectable, selected, selectionMode]);

  const toggleFavorite = useCallback(async () => {
    if (favoriteLoading) return;
    setFavoriteLoading(true);
    try {
      const success = type === 'archive'
        ? await FavoriteService.setFavorite('archive', id, !isFavorite)
        : await FavoriteService.setFavorite('tankoubon', id, !isFavorite);
      if (success) {
        setFavoriteState({ source: baseFavorite, value: !isFavorite });
      }
    } catch (error) {
      logger.operationFailed('toggle favorite from home menu', error, { id, type });
    } finally {
      setFavoriteLoading(false);
    }
  }, [baseFavorite, favoriteLoading, id, isFavorite, type]);

  const handleContextMenuCapture = useCallback((event: ReactMouseEvent<HTMLElement>) => {
    event.preventDefault();
  }, []);

  const handleContextMenu = useCallback((event: ReactMouseEvent<HTMLElement>) => {
    event.preventDefault();
    event.stopPropagation();
    if (selectionMode) return;
    setMenuPosition({ x: event.clientX, y: event.clientY });
    setMenuOpen(true);
  }, [selectionMode]);

  const handleDownload = useCallback(() => {
    if (type !== 'archive') return;
    void ArchiveService.downloadArchive(id);
  }, [id, type]);

  const handleToggleReadStatus = useCallback(async () => {
    if (type !== 'archive' || isNewStatusLoading) return;
    setIsNewStatusLoading(true);
    try {
      if (isNew) {
        await ArchiveService.clearIsNew(id);
      } else {
        await ArchiveService.setIsNew(id);
      }
      setIsNewState({ source: baseIsNew, value: !isNew });
      emitRefresh();
    } catch (error) {
      logger.operationFailed('toggle archive read status from home menu', error, { id });
      showError(isNew ? t('archive.markAsReadFailed') : t('archive.markAsNewFailed'));
    } finally {
      setIsNewStatusLoading(false);
    }
  }, [baseIsNew, emitRefresh, id, isNew, isNewStatusLoading, showError, t, type]);

  const handleOpenEdit = useCallback(() => {
    if (!canEdit) {
      showError(t('library.loginRequired'));
      return;
    }
    setEditOpen(true);
  }, [canEdit, showError, t]);

  // Optimistically update the card display after the shared edit controller saves.
  // The controller itself handles metadata fetching, uploads, saving and emits
  // ARCHIVES_REFRESH, so here we only mirror the saved values onto the card.
  const handleEditSaved = useCallback(
    (next: { summary: string; tags: string; title: string }) => {
      if (next.title) setDisplayTitleState({ source: title, value: next.title });
      setDisplayDescriptionState({ source: baseDescription, value: next.summary });
      setDisplayTagsState({ source: baseTags, value: next.tags });
    },
    [baseDescription, baseTags, title]
  );

  const handleDelete = useCallback(async () => {
    if (!canDelete) {
      showError(type === 'archive' ? t('common.accessDenied') : t('library.loginRequired'));
      return;
    }
    if (deleting) return;

    const confirmed = await confirm({
      title: type === 'archive' ? t('common.delete') : t('tankoubon.deleteConfirmTitle'),
      description: type === 'archive'
        ? `${t('common.delete')} ${t('archive.archiveLabel')}: "${displayTitle}"`
        : t('tankoubon.deleteConfirmMessage'),
      confirmText: t('common.delete'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    });
    if (!confirmed) return;

    setDeleting(true);
    try {
      if (type === 'archive') {
        await ArchiveService.deleteArchive(id);
      } else {
        await TankoubonService.deleteTankoubon(id);
      }
      emitRefresh();
    } catch (error) {
      logger.operationFailed('delete from home menu', error, { id, type });
      showError(t('common.error'));
    } finally {
      setDeleting(false);
    }
  }, [canDelete, confirm, deleting, displayTitle, emitRefresh, id, showError, t, type]);

  const readStatusLabel = isNew ? t('archive.markAsRead') : t('archive.markAsNew');

  return (
    <>
      <DropdownMenu open={menuOpen} onOpenChange={setMenuOpen}>
        <DropdownMenuContent
          align="start"
          side="bottom"
          className="w-52"
          style={{
            position: 'fixed',
            left: menuPosition.x,
            top: menuPosition.y,
          }}
        >
          {selectable && !selectionMode ? (
            <>
              <DropdownMenuItem
                onSelect={() => {
                  toggleSelected(true);
                }}
              >
                <Square className="mr-2 h-4 w-4" />
                {t('home.useMultiSelect')}
              </DropdownMenuItem>
              <DropdownMenuSeparator />
            </>
          ) : null}

          <DropdownMenuItem disabled={!readerTargetId} onSelect={() => navigateToReader()}>
            <BookOpen className="mr-2 h-4 w-4" />
            {t('archive.startReading')}
          </DropdownMenuItem>

          {type === 'archive' ? (
            <>
              <DropdownMenuItem onSelect={handleDownload}>
                <Download className="mr-2 h-4 w-4" />
                {t('archive.download')}
              </DropdownMenuItem>
              <DropdownMenuItem
                disabled={menuActionDisabled || isNewStatusLoading}
                onSelect={() => {
                  void handleToggleReadStatus();
                }}
              >
                {isNew ? <CheckCircle className="mr-2 h-4 w-4" /> : <RotateCcw className="mr-2 h-4 w-4" />}
                {isNewStatusLoading ? t('common.loading') : readStatusLabel}
              </DropdownMenuItem>
            </>
          ) : null}

          <DropdownMenuItem
            disabled={menuActionDisabled || favoriteLoading}
            onSelect={() => {
              void toggleFavorite();
            }}
          >
            <Heart className={`mr-2 h-4 w-4 ${isFavorite ? 'fill-current text-red-500' : ''}`} />
            {favoriteLoading ? t('common.loading') : isFavorite ? t('common.unfavorite') : t('common.favorite')}
          </DropdownMenuItem>

          <DropdownMenuSeparator />

          <DropdownMenuItem disabled={menuActionDisabled || !canEdit} onSelect={handleOpenEdit}>
            <Edit className="mr-2 h-4 w-4" />
            {t('common.edit')}
          </DropdownMenuItem>
          <DropdownMenuItem
            disabled={menuActionDisabled || !canDelete}
            className="text-destructive focus:text-destructive"
            onSelect={() => {
              void handleDelete();
            }}
          >
            <Trash2 className="mr-2 h-4 w-4" />
            {deleting ? t('common.loading') : t('common.delete')}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      {children({
        displayDescription,
        displayTags,
        displayTitle,
        favoriteLoading,
        handleContextMenu,
        handleContextMenuCapture,
        isFavorite,
        isNew,
        navigateToReader,
        toggleFavorite,
        toggleSelected,
      })}

      {editOpen ? (
        <BaseMediaCardEditController
          id={id}
          type={type}
          initialTitle={displayTitle}
          initialSummary={displayDescription}
          initialTags={displayTags}
          thumbnailAssetId={thumbnailAssetId}
          onOpenChange={setEditOpen}
          onSaved={handleEditSaved}
        />
      ) : null}
    </>
  );
}
