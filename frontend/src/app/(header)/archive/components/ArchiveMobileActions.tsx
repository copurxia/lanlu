'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { BookOpen, CheckCircle, Download, Edit, FolderPlus, Heart, MoreHorizontal, RotateCcw, Trash2, X } from 'lucide-react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { AddToTankoubonDialog } from '@/components/tankoubon/AddToTankoubonDialog';
import type { ArchiveMetadata } from '@/types/archive';
import { ArchiveService } from '@/lib/services/archive-service';
import { SourcePluginService } from '@/lib/services/source-plugin-service';
import { CategoryService } from '@/lib/services/category-service';
import { buildReaderPath } from '@/lib/utils/reader';
import { useToast } from '@/hooks/use-toast';
import { useRouter } from 'next/navigation';

type Props = {
  metadata: ArchiveMetadata;
  t: (key: string) => string;
  isEditing: boolean;
  isAuthenticated: boolean;
  isAdmin: boolean;
  isFavorite: boolean;
  favoriteLoading: boolean;
  isNewStatusLoading: boolean;
  deleteLoading: boolean;
  isSourceMode?: boolean;
  sourceNamespace?: string | null;
  remoteId?: string | null;
  onFavoriteClick: () => Promise<void> | void;
  onMarkAsRead: () => Promise<void> | void;
  onMarkAsNew: () => Promise<void> | void;
  onStartEdit: () => void;
  onDeleteArchive: () => Promise<void> | void;
};

export function ArchiveMobileActions({
  metadata,
  t,
  isEditing,
  isAuthenticated,
  isAdmin,
  isFavorite,
  favoriteLoading,
  isNewStatusLoading,
  deleteLoading,
  isSourceMode = false,
  sourceNamespace,
  remoteId,
  onFavoriteClick,
  onMarkAsRead,
  onMarkAsNew,
  onStartEdit,
  onDeleteArchive,
}: Props) {
  const router = useRouter();
  const { success, error: showError } = useToast();
  const [open, setOpen] = useState(false);
  const [ready, setReady] = useState(true);
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [pendingAddDialog, setPendingAddDialog] = useState(false);
  const readyTimerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (readyTimerRef.current) window.clearTimeout(readyTimerRef.current);
    };
  }, []);

  // Open the add-to-collection dialog only after the actions sheet closes.
  useEffect(() => {
    // If the sheet is reopened, cancel any pending open.
    if (open) {
      if (pendingAddDialog) setPendingAddDialog(false);
      return;
    }
    if (!pendingAddDialog) return;
    setPendingAddDialog(false);
    setAddDialogOpen(true);
  }, [open, pendingAddDialog]);

  const handleOpenChange = (nextOpen: boolean) => {
    setOpen(nextOpen);
    if (readyTimerRef.current) window.clearTimeout(readyTimerRef.current);
    if (!nextOpen) {
      setReady(true);
      return;
    }
    setReady(false);
    readyTimerRef.current = window.setTimeout(() => setReady(true), 350);
  };

  if (isEditing) return null;

  return (
    <div className="sm:hidden fixed inset-x-0 bottom-0 z-40 border-t border-border bg-background/82 backdrop-blur-lg">
      <div className="mx-auto max-w-7xl px-4 py-3 pb-[calc(env(safe-area-inset-bottom)+0.75rem)]">
        <div className="flex items-center gap-2.5">
          <Link
            href={isSourceMode && sourceNamespace && remoteId
              ? `/reader?source=${encodeURIComponent(sourceNamespace)}&remote_id=${encodeURIComponent(remoteId)}`
              : buildReaderPath(metadata.arcid, metadata.progress)
            }
            className="flex-1"
          >
            <Button className="w-full h-11 rounded-xl">
              <BookOpen className="w-4 h-4 mr-2" />
              {t('archive.startReading')}
            </Button>
          </Link>
          <Button
            variant="outline"
            className="shrink-0 h-11 w-11 rounded-xl p-0"
            aria-label={t('common.actions')}
            onClick={() => handleOpenChange(true)}
          >
            <MoreHorizontal className="w-4 h-4" />
          </Button>
        </div>
      </div>

      <Sheet open={open} onOpenChange={handleOpenChange}>
        <SheetContent
          side="bottom"
          className="px-4 pt-3 pb-[calc(env(safe-area-inset-bottom)+1rem)] max-h-[85vh] overflow-y-auto rounded-t-xl"
        >
          <div className="mx-auto mb-3 h-1.5 w-12 rounded-full bg-muted" />
          <SheetHeader className="mb-3">
            <SheetTitle>{t('common.actions')}</SheetTitle>
            <div className="text-sm text-muted-foreground line-clamp-2">{metadata.title}</div>
          </SheetHeader>

          <div className="space-y-2">
            <Button
              variant="outline"
              className="w-full justify-start"
              onClick={async () => {
                if (isSourceMode && sourceNamespace && remoteId) {
                  try {
                    const sourceId = `source:${sourceNamespace}:${remoteId}`;
                    await ArchiveService.downloadArchive(sourceId);
                    success('下载任务已创建');
                    router.push('/settings/tasks');
                  } catch {
                    showError('创建下载任务失败');
                  }
                  setOpen(false);
                  return;
                }
                void ArchiveService.downloadArchive(metadata.arcid);
                setOpen(false);
              }}
              disabled={!ready}
            >
              <Download className="w-4 h-4 mr-2" />
              {t('archive.download')}
            </Button>

            <Button
              variant="outline"
              className={`w-full justify-start ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
              onClick={async () => {
                await onFavoriteClick();
                setOpen(false);
              }}
              disabled={!ready || favoriteLoading || isSourceMode}
            >
              <Heart className={`w-4 h-4 mr-2 ${isFavorite ? 'fill-current' : ''}`} />
              {favoriteLoading ? t('common.loading') : isFavorite ? t('common.unfavorite') : t('common.favorite')}
            </Button>

            {!isSourceMode && (
              metadata.isnew ? (
                <Button
                  variant="outline"
                  className="w-full justify-start"
                  onClick={async () => {
                    await onMarkAsRead();
                    setOpen(false);
                  }}
                  disabled={!ready || isNewStatusLoading}
                >
                  <CheckCircle className="w-4 h-4 mr-2" />
                  {isNewStatusLoading ? t('common.loading') : t('archive.markAsRead')}
                </Button>
              ) : (
                <Button
                  variant="outline"
                  className="w-full justify-start"
                  onClick={async () => {
                    await onMarkAsNew();
                    setOpen(false);
                  }}
                  disabled={!ready || isNewStatusLoading}
                >
                  <RotateCcw className="w-4 h-4 mr-2" />
                  {isNewStatusLoading ? t('common.loading') : t('archive.markAsNew')}
                </Button>
              )
            )}

            {!isSourceMode && (
              <Button
                variant="outline"
                className="w-full justify-start"
                disabled={!ready}
                onClick={() => {
                  setPendingAddDialog(true);
                  setOpen(false);
                }}
              >
                <FolderPlus className="w-4 h-4 mr-2" />
                {t('tankoubon.addToCollection')}
              </Button>
            )}

            {!isSourceMode && (
              isAuthenticated ? (
                <Button
                  variant="outline"
                  className="w-full justify-start"
                  onClick={() => {
                    onStartEdit();
                    setOpen(false);
                  }}
                  disabled={!ready}
                >
                  <Edit className="w-4 h-4 mr-2" />
                  {t('common.edit')}
                </Button>
              ) : (
                <Button variant="outline" className="w-full justify-start" disabled title="需要登录才能编辑">
                  <Edit className="w-4 h-4 mr-2" />
                  {t('common.edit')}
                </Button>
              )
            )}

            {!isSourceMode && isAdmin && (
              <Button
                variant="destructive"
                className="w-full justify-start"
                onClick={async () => {
                  await onDeleteArchive();
                  setOpen(false);
                }}
                disabled={!ready || deleteLoading}
              >
                <Trash2 className="w-4 h-4 mr-2" />
                {deleteLoading ? t('common.loading') : t('common.delete')}
              </Button>
            )}

            <Button variant="outline" className="w-full justify-start" onClick={() => setOpen(false)}>
              <X className="w-4 h-4 mr-2" />
              {t('common.close')}
            </Button>
          </div>
        </SheetContent>
      </Sheet>

      {/* Render outside the Sheet so it doesn't unmount during close animation. */}
      {!isSourceMode && (
        <AddToTankoubonDialog
          archiveId={metadata.arcid}
          open={addDialogOpen}
          onOpenChange={setAddDialogOpen}
          onAdded={() => setAddDialogOpen(false)}
        />
      )}
    </div>
  );
}
