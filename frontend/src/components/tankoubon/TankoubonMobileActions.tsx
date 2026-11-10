'use client';

import { useEffect, useRef, useState } from 'react';
import { Edit, Heart, MoreHorizontal, Plus, Trash2, X } from 'lucide-react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import type { TankoubonMetadata } from '@/types/tankoubon';

type Props = {
  tankoubon: TankoubonMetadata;
  t: (key: string) => string;
  isAuthenticated: boolean;
  isAdmin: boolean;
  isFavorite: boolean;
  favoriteLoading: boolean;
  deleteLoading: boolean;
  onFavoriteClick: () => Promise<void> | void;
  onEdit: () => void;
  onDelete: () => Promise<void> | void;
  onAddArchive: () => void;
};

export function TankoubonMobileActions({
  tankoubon,
  t,
  isAuthenticated,
  isAdmin,
  isFavorite,
  favoriteLoading,
  deleteLoading,
  onFavoriteClick,
  onEdit,
  onDelete,
  onAddArchive,
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

  return (
    <div className="lg:hidden fixed inset-x-0 bottom-0 z-40 border-t border-border bg-background/82 backdrop-blur-lg">
      <div className="mx-auto max-w-[1400px] px-4 py-3 pb-[calc(env(safe-area-inset-bottom)+0.75rem)]">
        <div className="flex items-center gap-2.5">
          <Button className="flex-1 h-11 rounded-xl" onClick={onAddArchive}>
            <Plus className="w-4 h-4 mr-2" />
            {t('tankoubon.addArchive')}
          </Button>
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
            <div className="text-sm text-muted-foreground line-clamp-2">{tankoubon.title}</div>
          </SheetHeader>

          <div className="space-y-2">
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

            <Button
              variant="outline"
              className="w-full justify-start"
              onClick={() => {
                onEdit();
                setOpen(false);
              }}
              disabled={!ready}
            >
              <Edit className="w-4 h-4 mr-2" />
              {t('common.edit')}
            </Button>

            {isAdmin && (
              <Button
                variant="destructive"
                className="w-full justify-start"
                onClick={async () => {
                  await onDelete();
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
