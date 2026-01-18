'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { BookOpen, CheckCircle, Download, Edit, Heart, MoreHorizontal, RotateCcw, Trash2, X } from 'lucide-react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { AddToTankoubonDialog } from '@/components/tankoubon/AddToTankoubonDialog';
import type { ArchiveMetadata } from '@/types/archive';
import { ArchiveService } from '@/lib/services/archive-service';

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
  onFavoriteClick,
  onMarkAsRead,
  onMarkAsNew,
  onStartEdit,
  onDeleteArchive,
}: Props) {
  const [open, setOpen] = useState(false);
  const [ready, setReady] = useState(true);
  const readyTimerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (readyTimerRef.current) window.clearTimeout(readyTimerRef.current);
    };
  }, []);

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
    <div className="sm:hidden fixed inset-x-0 bottom-0 z-40 border-t bg-background/85 backdrop-blur supports-[backdrop-filter]:bg-background/70">
      <div className="mx-auto max-w-7xl px-4 py-3 pb-[calc(env(safe-area-inset-bottom)+0.75rem)]">
        <div className="flex items-center gap-2">
          <Link href={`/reader?id=${metadata.arcid}`} className="flex-1">
            <Button className="w-full">
              <BookOpen className="w-4 h-4 mr-2" />
              {t('archive.startReading')}
            </Button>
          </Link>
          <Button
            variant="outline"
            className="shrink-0"
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
              onClick={() => {
                const downloadUrl = ArchiveService.getDownloadUrl(metadata.arcid);
                window.open(downloadUrl, '_blank');
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
              disabled={!ready || favoriteLoading}
            >
              <Heart className={`w-4 h-4 mr-2 ${isFavorite ? 'fill-current' : ''}`} />
              {favoriteLoading ? t('common.loading') : isFavorite ? t('common.unfavorite') : t('common.favorite')}
            </Button>

            {metadata.isnew ? (
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
            )}

            <AddToTankoubonDialog
              archiveId={metadata.arcid}
              trigger={
                <Button variant="outline" className="w-full justify-start" disabled={!ready}>
                  <BookOpen className="w-4 h-4 mr-2" />
                  {t('tankoubon.addToCollection')}
                </Button>
              }
              onAdded={() => setOpen(false)}
            />

            {isAuthenticated ? (
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
            )}

            {isAdmin && (
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
    </div>
  );
}
