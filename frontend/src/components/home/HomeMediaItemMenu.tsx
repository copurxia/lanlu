'use client';

import type { ChangeEvent, MouseEvent as ReactMouseEvent, ReactNode } from 'react';
import { useCallback, useEffect, useState } from 'react';
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
import { ArchiveMetadataEditDialog } from '@/components/archive/ArchiveMetadataEditDialog';
import { useAuth } from '@/contexts/AuthContext';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { useLanguage } from '@/contexts/LanguageContext';
import { useToast } from '@/hooks/use-toast';
import { ArchiveService } from '@/lib/services/archive-service';
import { ChunkedUploadService } from '@/lib/services/chunked-upload-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { appEvents, AppEvents } from '@/lib/utils/events';
import { getCoverAssetId } from '@/lib/utils/archive-assets';
import { buildMetadataAssetInputs } from '@/lib/utils/metadata';
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

function toTagList(raw?: string): string[] {
  return String(raw || '')
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean);
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

  const [menuOpen, setMenuOpen] = useState(false);
  const [menuPosition, setMenuPosition] = useState({ x: 0, y: 0 });
  const [displayTitle, setDisplayTitle] = useState(title);
  const [displayDescription, setDisplayDescription] = useState(description || '');
  const [displayTags, setDisplayTags] = useState(tags || '');
  const [isFavorite, setIsFavorite] = useState(Boolean(initialFavorite));
  const [isNew, setIsNew] = useState(Boolean(initialIsNew));
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const [isNewStatusLoading, setIsNewStatusLoading] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [editSaving, setEditSaving] = useState(false);
  const [editTitle, setEditTitle] = useState(title);
  const [editSummary, setEditSummary] = useState(description || '');
  const [editTags, setEditTags] = useState<string[]>(toTagList(tags));
  const [editCover, setEditCover] = useState('');
  const [editBackdrop, setEditBackdrop] = useState('');
  const [editClearlogo, setEditClearlogo] = useState('');
  const [editAssetCoverId, setEditAssetCoverId] = useState('');
  const [editAssetBackdropId, setEditAssetBackdropId] = useState('');
  const [editAssetClearlogoId, setEditAssetClearlogoId] = useState('');
  const [coverUploading, setCoverUploading] = useState(false);
  const [backdropUploading, setBackdropUploading] = useState(false);
  const [clearlogoUploading, setClearlogoUploading] = useState(false);

  const isAdmin = user?.isAdmin === true;
  const canEdit = isAuthenticated;
  const canDelete = type === 'archive' ? isAdmin : isAuthenticated;
  const detailPath = type === 'archive' ? `/archive?id=${id}` : `/tankoubon?id=${id}`;
  const readerPath = readerTargetId
    ? buildReaderPath(readerTargetId, type === 'archive' ? progress : undefined)
    : detailPath;
  const menuActionDisabled = deleting || editSaving;

  useEffect(() => {
    setDisplayTitle(title);
  }, [title]);

  useEffect(() => {
    setDisplayDescription(description || '');
  }, [description]);

  useEffect(() => {
    setDisplayTags(tags || '');
  }, [tags]);

  useEffect(() => {
    setIsFavorite(Boolean(initialFavorite));
  }, [initialFavorite]);

  useEffect(() => {
    setIsNew(Boolean(initialIsNew));
  }, [initialIsNew]);

  useEffect(() => {
    if (!editOpen || !canEdit) return;

    const fallbackCoverId = typeof thumbnailAssetId === 'number' && Number.isFinite(thumbnailAssetId) && thumbnailAssetId > 0
      ? String(Math.trunc(thumbnailAssetId))
      : '';

    setEditCover('');
    setEditBackdrop('');
    setEditClearlogo('');
    setEditAssetCoverId(fallbackCoverId);
    setEditAssetBackdropId('');
    setEditAssetClearlogoId('');

    let cancelled = false;

    void (async () => {
      try {
        if (type === 'archive') {
          const meta = await ArchiveService.getMetadata(id);
          if (cancelled) return;
          setEditAssetCoverId(String(getCoverAssetId(meta) || ''));
          setEditAssetBackdropId(String(meta.assets?.backdrop || ''));
          setEditAssetClearlogoId(String(meta.assets?.clearlogo || ''));
          return;
        }

        const meta = await TankoubonService.getMetadata(id);
        if (cancelled) return;
        setEditAssetCoverId(String(getCoverAssetId(meta) || ''));
        setEditAssetBackdropId(String(meta.assets?.backdrop || ''));
        setEditAssetClearlogoId(String(meta.assets?.clearlogo || ''));
      } catch {
        // Keep fallback asset ids when detail loading fails.
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [canEdit, editOpen, id, thumbnailAssetId, type]);

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
        ? await FavoriteService.toggleFavorite(id, isFavorite)
        : await FavoriteService.toggleTankoubonFavorite(id, isFavorite);
      if (success) {
        setIsFavorite((current) => !current);
      }
    } catch (error) {
      logger.operationFailed('toggle favorite from home menu', error, { id, type });
    } finally {
      setFavoriteLoading(false);
    }
  }, [favoriteLoading, id, isFavorite, type]);

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
    window.open(ArchiveService.getDownloadUrl(id), '_blank');
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
      setIsNew((current) => !current);
      emitRefresh();
    } catch (error) {
      logger.operationFailed('toggle archive read status from home menu', error, { id });
      showError(isNew ? t('archive.markAsReadFailed') : t('archive.markAsNewFailed'));
    } finally {
      setIsNewStatusLoading(false);
    }
  }, [emitRefresh, id, isNew, isNewStatusLoading, showError, t, type]);

  const handleOpenEdit = useCallback(() => {
    if (!canEdit) {
      showError(t('library.loginRequired'));
      return;
    }

    const fallbackCoverId = typeof thumbnailAssetId === 'number' && Number.isFinite(thumbnailAssetId) && thumbnailAssetId > 0
      ? String(Math.trunc(thumbnailAssetId))
      : '';

    setEditTitle(displayTitle);
    setEditSummary(displayDescription);
    setEditTags(toTagList(displayTags));
    setEditCover('');
    setEditBackdrop('');
    setEditClearlogo('');
    setEditAssetCoverId(fallbackCoverId);
    setEditAssetBackdropId('');
    setEditAssetClearlogoId('');
    setEditOpen(true);
  }, [canEdit, displayDescription, displayTags, displayTitle, showError, t, thumbnailAssetId]);

  const uploadMetadataAsset = useCallback((slot: 'cover' | 'backdrop' | 'clearlogo') => {
    if (!canEdit || editSaving) return;

    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.style.display = 'none';

    const setUploading = (next: boolean) => {
      if (slot === 'cover') {
        setCoverUploading(next);
        return;
      }
      if (slot === 'backdrop') {
        setBackdropUploading(next);
        return;
      }
      setClearlogoUploading(next);
    };

    input.onchange = async (nativeEvent) => {
      const event = nativeEvent as unknown as ChangeEvent<HTMLInputElement>;
      const file = event.target.files?.[0];
      if (!file) {
        document.body.removeChild(input);
        return;
      }

      setUploading(true);
      try {
        const result = await ChunkedUploadService.uploadWithChunks(
          file,
          {
            targetType: 'metadata_asset',
            overwrite: true,
            contentType: file.type || 'application/octet-stream',
          },
          {
            onProgress: () => {},
            onChunkComplete: () => {},
            onError: () => {},
          }
        );

        if (!result.success) {
          throw new Error(result.error || t('archive.assetUploadFailed'));
        }

        const assetId = Number(result.data?.assetId ?? 0);
        if (!Number.isFinite(assetId) || assetId <= 0) {
          throw new Error(t('archive.assetUploadFailed'));
        }

        const normalizedAssetId = String(Math.trunc(assetId));
        if (slot === 'cover') {
          setEditAssetCoverId(normalizedAssetId);
          setEditCover('');
        } else if (slot === 'backdrop') {
          setEditAssetBackdropId(normalizedAssetId);
          setEditBackdrop('');
        } else {
          setEditAssetClearlogoId(normalizedAssetId);
          setEditClearlogo('');
        }
      } catch (error: any) {
        logger.operationFailed('upload metadata asset from home menu', error, { id, slot, type });
        showError(error?.response?.data?.message || error?.message || t('archive.assetUploadFailed'));
      } finally {
        setUploading(false);
        document.body.removeChild(input);
      }
    };

    document.body.appendChild(input);
    input.click();
  }, [canEdit, editSaving, id, showError, t, type]);

  const handleSaveEdit = useCallback(async () => {
    if (editSaving) return;
    if (!canEdit) {
      showError(t('library.loginRequired'));
      return;
    }

    const nextTitle = editTitle.trim();
    if (type === 'tankoubon' && !nextTitle) {
      showError(t('tankoubon.nameRequired'));
      return;
    }

    const parseAssetId = (raw: string): number | undefined => {
      const value = Number(raw.trim());
      if (!Number.isFinite(value)) return undefined;
      const parsedId = Math.trunc(value);
      return parsedId > 0 ? parsedId : undefined;
    };

    setEditSaving(true);
    try {
      const nextTags = editTags.map((tag) => tag.trim()).filter(Boolean);
      const nextSummary = editSummary.trim();
      const assetIds = {
        backdrop: parseAssetId(editAssetBackdropId),
        clearlogo: parseAssetId(editAssetClearlogoId),
        cover: parseAssetId(editAssetCoverId),
      };

      if (type === 'archive') {
        await ArchiveService.updateMetadata(id, {
          title: nextTitle || displayTitle,
          type: 0,
          description: nextSummary,
          tags: nextTags,
          assets: buildMetadataAssetInputs(
            {
              cover: editCover || undefined,
              backdrop: editBackdrop || undefined,
              clearlogo: editClearlogo || undefined,
            },
            assetIds
          ),
        });
      } else {
        await TankoubonService.updateMetadata(id, {
          title: nextTitle,
          type: 1,
          description: nextSummary,
          tags: nextTags,
          assets: buildMetadataAssetInputs(
            {
              cover: editCover || undefined,
              backdrop: editBackdrop || undefined,
              clearlogo: editClearlogo || undefined,
            },
            assetIds
          ),
        });
      }

      if (nextTitle) setDisplayTitle(nextTitle);
      setDisplayDescription(nextSummary);
      setDisplayTags(nextTags.join(', '));
      setEditOpen(false);
      emitRefresh();
    } catch (error) {
      logger.operationFailed('save home menu edit', error, { id, type });
      showError(type === 'archive' ? t('archive.updateFailed') : t('common.error'));
    } finally {
      setEditSaving(false);
    }
  }, [
    canEdit,
    displayTitle,
    editAssetBackdropId,
    editAssetClearlogoId,
    editAssetCoverId,
    editBackdrop,
    editClearlogo,
    editCover,
    editSaving,
    editSummary,
    editTags,
    editTitle,
    emitRefresh,
    id,
    showError,
    t,
    type,
  ]);

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

      <ArchiveMetadataEditDialog
        open={editOpen}
        onOpenChange={setEditOpen}
        t={t}
        title={editTitle}
        onTitleChange={setEditTitle}
        summary={editSummary}
        onSummaryChange={setEditSummary}
        assetCoverId={editAssetCoverId}
        onAssetCoverIdChange={setEditAssetCoverId}
        assetBackdropId={editAssetBackdropId}
        onAssetBackdropIdChange={setEditAssetBackdropId}
        assetClearlogoId={editAssetClearlogoId}
        onAssetClearlogoIdChange={setEditAssetClearlogoId}
        assetCoverValue={editCover}
        assetBackdropValue={editBackdrop}
        assetClearlogoValue={editClearlogo}
        onUploadAssetCover={() => {
          uploadMetadataAsset('cover');
        }}
        onUploadAssetBackdrop={() => {
          uploadMetadataAsset('backdrop');
        }}
        onUploadAssetClearlogo={() => {
          uploadMetadataAsset('clearlogo');
        }}
        uploadingAssetCover={coverUploading}
        uploadingAssetBackdrop={backdropUploading}
        uploadingAssetClearlogo={clearlogoUploading}
        tags={editTags}
        onTagsChange={setEditTags}
        isSaving={editSaving}
        onSave={handleSaveEdit}
        showMetadataPlugin={false}
      />
    </>
  );
}
