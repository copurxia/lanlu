'use client';

import { Button } from '@/components/ui/button';
import { Check, Download, Heart, Pencil, RotateCcw, Trash2, X } from 'lucide-react';
import { BatchEditDialog } from '@/components/archive/BatchEditDialog';
import type { BatchEditPayload } from '@/components/archive/BatchEditDialog';

interface HomeBatchActionBarProps {
  visible: boolean;
  selectedTotal: number;
  selectedArchiveCount: number;
  selectedTankoubonCount: number;
  hasAnySelected: boolean;
  canBatchDownload: boolean;
  canBatchDelete: boolean;
  batchActionRunning: boolean;
  batchEditApplying: boolean;
  favoriteActionLabel: string;
  allSelectedArchiveIsNew: boolean;
  batchEditOpen: boolean;
  setBatchEditOpen: (open: boolean) => void;
  metadataPlugins: Array<{ namespace: string; name: string }>;
  onExit: () => void;
  onEdit: () => void;
  onFavorite: () => void;
  onDownload: () => void;
  onReadStatus: () => void;
  onDelete: () => void;
  onApplyBatchEdit: (payload: BatchEditPayload) => Promise<boolean>;
  t: (key: string, ...args: any[]) => string;
}

export function HomeBatchActionBar({
  visible,
  selectedTotal,
  selectedArchiveCount,
  selectedTankoubonCount,
  hasAnySelected,
  canBatchDownload,
  canBatchDelete,
  batchActionRunning,
  batchEditApplying,
  favoriteActionLabel,
  allSelectedArchiveIsNew,
  batchEditOpen,
  setBatchEditOpen,
  metadataPlugins,
  onExit,
  onEdit,
  onFavorite,
  onDownload,
  onReadStatus,
  onDelete,
  onApplyBatchEdit,
  t,
}: HomeBatchActionBarProps) {
  return (
    <>
      <div
        className={[
          "fixed left-1/2 z-50 flex -translate-x-1/2 items-center gap-2 transition-all duration-250 ease-out",
          "bottom-[calc(env(safe-area-inset-bottom)+4.25rem)] lg:bottom-6",
          visible ? "opacity-100 translate-y-0 pointer-events-auto" : "opacity-0 translate-y-4 pointer-events-none",
        ].join(" ")}
      >
        <div className="bg-background/95 backdrop-blur-xs border border-border rounded-full px-3 py-2 shadow-lg flex items-center gap-2">
          <span className="text-xs sm:text-sm whitespace-nowrap font-medium text-foreground px-1">
            {t('common.selected')}: {selectedTotal}
          </span>
        </div>

        <div className="bg-background/95 backdrop-blur-xs border border-border rounded-full p-1 shadow-lg flex items-center gap-1">
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3"
            disabled={!hasAnySelected || batchActionRunning || batchEditApplying}
            onClick={onEdit}
            title={t('common.edit')}
          >
            <Pencil className="mr-1 h-4 w-4" />
            <span className="hidden sm:inline">{t('common.edit')}</span>
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3"
            disabled={!hasAnySelected || batchActionRunning}
            onClick={() => void onFavorite()}
            title={favoriteActionLabel}
          >
            <Heart className="mr-1 h-4 w-4" />
            <span className="hidden sm:inline">{favoriteActionLabel}</span>
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3"
            disabled={!canBatchDownload || batchActionRunning}
            onClick={onDownload}
            title={t('archive.download')}
          >
            <Download className="mr-1 h-4 w-4" />
            <span className="hidden sm:inline">{t('archive.download')}</span>
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3"
            disabled={!canBatchDownload || batchActionRunning}
            onClick={() => void onReadStatus()}
            title={allSelectedArchiveIsNew ? t('archive.markAsRead') : t('archive.markAsNew')}
          >
            {allSelectedArchiveIsNew ? <Check className="mr-1 h-4 w-4" /> : <RotateCcw className="mr-1 h-4 w-4" />}
            <span className="hidden sm:inline">
              {allSelectedArchiveIsNew ? t('archive.markAsRead') : t('archive.markAsNew')}
            </span>
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3 text-destructive hover:text-destructive"
            disabled={!canBatchDelete || batchActionRunning}
            onClick={() => void onDelete()}
            title={t('common.delete')}
          >
            <Trash2 className="mr-1 h-4 w-4" />
            <span className="hidden sm:inline">{t('common.delete')}</span>
          </Button>
        </div>

        <div className="bg-background/95 backdrop-blur-xs border border-border rounded-full p-1 shadow-lg">
          <Button
            variant="ghost"
            size="sm"
            className="h-9 w-9 rounded-full p-0"
            onClick={onExit}
            title={t('home.exitMultiSelect')}
          >
            <X className="h-4 w-4" />
          </Button>
        </div>
      </div>

      <BatchEditDialog
        open={batchEditOpen}
        onOpenChange={setBatchEditOpen}
        totalSelected={selectedTotal}
        selectedArchiveCount={selectedArchiveCount}
        selectedTankoubonCount={selectedTankoubonCount}
        metadataPluginOptions={metadataPlugins}
        applying={batchEditApplying}
        t={t}
        onApply={onApplyBatchEdit}
      />
    </>
  );
}
