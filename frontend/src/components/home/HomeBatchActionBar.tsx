'use client';

import type { ReactNode } from 'react';
import { Button } from '@/components/ui/button';
import { Check, Download, Heart, Pencil, RotateCcw, Trash2, X } from 'lucide-react';
import { BatchEditDialog } from '@/components/archive/BatchEditDialog';
import type { BatchEditPayload } from '@/components/archive/BatchEditDialog';
type TranslationParams = Record<string, string | number | boolean | null | undefined>;

export interface BatchActionBarItem {
  id: string;
  label: string;
  title?: string;
  icon: ReactNode;
  disabled?: boolean;
  destructive?: boolean;
  onClick: () => void | Promise<void>;
}

interface HomeBatchActionBarProps {
  visible: boolean;
  selectedTotal: number;
  selectedArchiveCount?: number;
  selectedTankoubonCount?: number;
  hasAnySelected: boolean;
  canBatchDownload?: boolean;
  canBatchDelete?: boolean;
  batchActionRunning?: boolean;
  batchEditApplying?: boolean;
  favoriteActionLabel?: string;
  allSelectedArchiveIsNew?: boolean;
  batchEditOpen?: boolean;
  setBatchEditOpen?: (open: boolean) => void;
  metadataPlugins?: Array<{ namespace: string; name: string }>;
  actions?: BatchActionBarItem[];
  showBatchEditDialog?: boolean;
  onExit: () => void;
  onEdit?: () => void;
  onFavorite?: () => void;
  onDownload?: () => void;
  onReadStatus?: () => void;
  onDelete?: () => void;
  onApplyBatchEdit?: (payload: BatchEditPayload) => Promise<boolean>;
  t: (key: string, params?: TranslationParams) => string;
}

export function HomeBatchActionBar({
  visible,
  selectedTotal,
  selectedArchiveCount = 0,
  selectedTankoubonCount = 0,
  hasAnySelected,
  canBatchDownload = false,
  canBatchDelete = false,
  batchActionRunning = false,
  batchEditApplying = false,
  favoriteActionLabel,
  allSelectedArchiveIsNew = false,
  batchEditOpen = false,
  setBatchEditOpen,
  metadataPlugins = [],
  actions,
  showBatchEditDialog,
  onExit,
  onEdit,
  onFavorite,
  onDownload,
  onReadStatus,
  onDelete,
  onApplyBatchEdit,
  t,
}: HomeBatchActionBarProps) {
  const resolvedActions = actions ?? [
    {
      id: 'edit',
      label: t('common.edit'),
      title: t('common.edit'),
      icon: <Pencil className="mr-1 h-4 w-4" />,
      disabled: !hasAnySelected || batchActionRunning || batchEditApplying,
      onClick: () => onEdit?.(),
    },
    {
      id: 'favorite',
      label: favoriteActionLabel || t('common.favorite'),
      title: favoriteActionLabel || t('common.favorite'),
      icon: <Heart className="mr-1 h-4 w-4" />,
      disabled: !hasAnySelected || batchActionRunning,
      onClick: () => void onFavorite?.(),
    },
    {
      id: 'download',
      label: t('archive.download'),
      title: t('archive.download'),
      icon: <Download className="mr-1 h-4 w-4" />,
      disabled: !canBatchDownload || batchActionRunning,
      onClick: () => onDownload?.(),
    },
    {
      id: 'read-status',
      label: allSelectedArchiveIsNew ? t('archive.markAsRead') : t('archive.markAsNew'),
      title: allSelectedArchiveIsNew ? t('archive.markAsRead') : t('archive.markAsNew'),
      icon: allSelectedArchiveIsNew
        ? <Check className="mr-1 h-4 w-4" />
        : <RotateCcw className="mr-1 h-4 w-4" />,
      disabled: !canBatchDownload || batchActionRunning,
      onClick: () => void onReadStatus?.(),
    },
    {
      id: 'delete',
      label: t('common.delete'),
      title: t('common.delete'),
      icon: <Trash2 className="mr-1 h-4 w-4" />,
      disabled: !canBatchDelete || batchActionRunning,
      destructive: true,
      onClick: () => void onDelete?.(),
    },
  ];
  const shouldShowBatchEditDialog = showBatchEditDialog ?? !actions;

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
          {resolvedActions.map((action) => (
            <Button
              key={action.id}
              variant="ghost"
              size="sm"
              className={[
                'h-9 rounded-full px-3',
                action.destructive ? 'text-destructive hover:text-destructive' : '',
              ].join(' ').trim()}
              disabled={action.disabled}
              onClick={() => void action.onClick()}
              title={action.title || action.label}
            >
              {action.icon}
              <span className="hidden sm:inline">{action.label}</span>
            </Button>
          ))}
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

      {shouldShowBatchEditDialog && setBatchEditOpen && onApplyBatchEdit ? (
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
      ) : null}
    </>
  );
}
