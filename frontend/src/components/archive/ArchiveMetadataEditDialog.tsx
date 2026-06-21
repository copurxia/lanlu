'use client';

import { useMemo, useState } from 'react';
import { Play } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { TagInput } from '@/components/ui/tag-input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { MetadataAssetsEditor } from '@/components/archive/MetadataAssetsEditor';
import { RawImage } from '@/components/ui/raw-image';
import { TankoubonArchiveListItem } from '@/components/tankoubon/TankoubonArchiveListItem';
import { PageListItem } from '@/components/archive/PageListItem';
import { useMediaQuery } from '@/components/ui/unified-menu/hooks/use-media-query';
import type { Plugin } from '@/lib/services/plugin-service';
import type { RpcSelectRequest } from '@/types/metadata-plugin';
import type { Archive } from '@/types/archive';
import type { MetadataPagePatch } from '@/types/archive';
import type { TankoubonMemberMetadataPatch } from '@/types/tankoubon';
export type { RpcSelectOption, RpcSelectRequest } from '@/types/metadata-plugin';

type RpcSelectState = {
  request: RpcSelectRequest | null;
  selectedIndex: number | null;
  remainingSeconds: number | null;
  onSelectIndex: (index: number) => void;
  onAbort: () => void | Promise<void>;
  onSubmit: () => void | Promise<void>;
};

type Props = {
  open: boolean;
  onOpenChange: (next: boolean) => void;
  t: (key: string) => string;
  titleLabel?: string;
  summaryLabel?: string;
  tagsLabel?: string;
  summaryPlaceholder?: string;
  tagsPlaceholder?: string;
  title: string;
  onTitleChange: (next: string) => void;
  summary: string;
  onSummaryChange: (next: string) => void;
  assetCoverId?: string;
  onAssetCoverIdChange?: (next: string) => void;
  assetBackdropId?: string;
  onAssetBackdropIdChange?: (next: string) => void;
  assetClearlogoId?: string;
  onAssetClearlogoIdChange?: (next: string) => void;
  assetCoverValue?: string;
  assetBackdropValue?: string;
  assetClearlogoValue?: string;
  onUploadAssetCover?: () => void | Promise<void>;
  onUploadAssetBackdrop?: () => void | Promise<void>;
  onUploadAssetClearlogo?: () => void | Promise<void>;
  uploadingAssetCover?: boolean;
  uploadingAssetBackdrop?: boolean;
  uploadingAssetClearlogo?: boolean;
  showAssetFields?: boolean;
  tags: string[];
  onTagsChange: (next: string[]) => void;
  isSaving: boolean;
  saveDisabled?: boolean;
  onSave: () => void | Promise<void>;
  showMetadataPlugin?: boolean;
  metadataPlugins?: Plugin[];
  selectedMetadataPlugin?: string;
  onSelectedMetadataPluginChange?: (next: string) => void;
  metadataPluginParam?: string;
  onMetadataPluginParamChange?: (next: string) => void;
  isMetadataPluginRunning?: boolean;
  metadataPluginProgress?: number | null;
  metadataPluginMessage?: string;
  onRunMetadataPlugin?: () => void | Promise<void>;
  rpcSelect?: RpcSelectState;
  archives?: Archive[];
  onArchiveEdit?: (archive: Archive) => void;
  onArchiveRemove?: (archive: Archive) => void;
  isRemovingArchiveId?: string | null;
  archiveMetadataPatches?: TankoubonMemberMetadataPatch[];
  pages?: MetadataPagePatch[];
  previewPages?: MetadataPagePatch[];
  onPageEdit?: (page: MetadataPagePatch) => void;
  onPageRemove?: (page: MetadataPagePatch) => void;
};

const MOBILE_BREAKPOINT = '(max-width: 767px)';

export function ArchiveMetadataEditDialog({
  open,
  onOpenChange,
  t,
  titleLabel,
  summaryLabel,
  tagsLabel,
  summaryPlaceholder,
  tagsPlaceholder,
  title,
  onTitleChange,
  summary,
  onSummaryChange,
  assetCoverId = '',
  onAssetCoverIdChange,
  assetBackdropId = '',
  onAssetBackdropIdChange,
  assetClearlogoId = '',
  onAssetClearlogoIdChange,
  assetCoverValue = '',
  assetBackdropValue = '',
  assetClearlogoValue = '',
  onUploadAssetCover,
  onUploadAssetBackdrop,
  onUploadAssetClearlogo,
  uploadingAssetCover = false,
  uploadingAssetBackdrop = false,
  uploadingAssetClearlogo = false,
  showAssetFields = true,
  tags,
  onTagsChange,
  isSaving,
  saveDisabled = false,
  onSave,
  showMetadataPlugin = true,
  metadataPlugins = [],
  selectedMetadataPlugin = '',
  onSelectedMetadataPluginChange,
  metadataPluginParam = '',
  onMetadataPluginParamChange,
  isMetadataPluginRunning = false,
  metadataPluginProgress = null,
  metadataPluginMessage = '',
  onRunMetadataPlugin,
  rpcSelect,
  archives,
  onArchiveEdit,
  onArchiveRemove,
  isRemovingArchiveId,
  archiveMetadataPatches = [],
  pages,
  previewPages,
  onPageEdit,
  onPageRemove,
}: Props) {
  const isMobile = useMediaQuery(MOBILE_BREAKPOINT);
  const [mobileView, setMobileView] = useState<'list' | 'form'>('form');
  const showArchiveSidebar = Boolean(
    archives && archives.length > 0 && (onArchiveEdit || onArchiveRemove)
  );
  const showPagesSidebar = Boolean(pages && pages.length > 0 && !archives);
  const showSidebar = showArchiveSidebar || showPagesSidebar;

  const displayedArchives = useMemo(() => {
    if (!archives || archives.length === 0) return archives;
    if (!archiveMetadataPatches || archiveMetadataPatches.length === 0) return archives;

    const patchMap = new Map(
      archiveMetadataPatches
        .filter((patch) => patch.entity_id)
        .map((patch) => [patch.entity_id!, patch])
    );

    return archives.map((archive) => {
      const patch = patchMap.get(archive.arcid);
      if (!patch) return archive;

      const patchedTags = Array.isArray(patch.tags)
        ? patch.tags.join(',')
        : typeof patch.tags === 'string'
          ? patch.tags
          : archive.tags;

      const merged: Archive = {
        ...archive,
        title: patch.title || archive.title,
        description: patch.description || archive.description,
        tags: patchedTags,
      };

      if (patch.assets && !Array.isArray(patch.assets)) {
        merged.assets = { ...archive.assets, ...patch.assets };
      }

      return merged;
    });
  }, [archives, archiveMetadataPatches]);
  const dialogSize = showSidebar ? 'xl' : 'md';

  const archiveSidebarContent = showArchiveSidebar ? (
    <div className="flex h-full flex-col">
      <div className="border-b px-4 py-3">
        <h3 className="font-semibold">{t('tankoubon.archiveList')}</h3>
        <p className="text-xs text-muted-foreground">
          {t('tankoubon.archiveCount')}: {displayedArchives!.length}
        </p>
      </div>
      <div className="flex-1 overflow-y-auto p-2">
        <div className="space-y-1">
          {displayedArchives!.map((archive) => (
            <TankoubonArchiveListItem
              key={archive.arcid}
              archive={archive}
              isRemoving={isRemovingArchiveId === archive.arcid}
              onEdit={onArchiveEdit!}
              onRemove={onArchiveRemove!}
            />
          ))}
        </div>
      </div>
    </div>
  ) : null;

  const pageSidebarContent = showPagesSidebar ? (
    <div className="flex h-full flex-col">
      <div className="border-b px-4 py-3">
        <h3 className="font-semibold">{t('archive.pageMetadata')}</h3>
        <p className="text-xs text-muted-foreground">
          {pages!.length} {t('archive.pages').replace('{count}', '')}
        </p>
      </div>
      <div className="flex-1 overflow-y-auto p-2">
        <div className="space-y-1">
          {(() => {
            const source = previewPages && previewPages.length > 0 ? previewPages : pages!;
            const sorted = [...source].sort((a, b) => {
              const aOrder = typeof a.order_index === 'number' ? a.order_index : 999999;
              const bOrder = typeof b.order_index === 'number' ? b.order_index : 999999;
              if (aOrder !== bOrder) return aOrder - bOrder;
              const aNum = typeof a.page_number === 'number' ? a.page_number : 999999;
              const bNum = typeof b.page_number === 'number' ? b.page_number : 999999;
              return aNum - bNum;
            });
            return sorted.map((page, i) => (
              <PageListItem key={`${page.page_number ?? i}`} page={page} index={i} onEdit={onPageEdit} onRemove={onPageRemove} />
            ));
          })()}
        </div>
      </div>
    </div>
  ) : null;

  const sidebarContent = showArchiveSidebar ? archiveSidebarContent : pageSidebarContent;
  const sidebarLabel = showArchiveSidebar ? t('tankoubon.archiveList') : t('archive.pageMetadata');
  const mobileToggle = showSidebar && isMobile ? (
    <Tabs
      value={mobileView}
      onValueChange={(v) => setMobileView(v as 'list' | 'form')}
      className="w-full border-b"
    >
      <TabsList className="mx-3 my-2 h-9 w-full gap-0 rounded-md bg-muted p-0.5">
        <TabsTrigger
          value="list"
          className="h-full flex-1 rounded-sm px-4 text-xs font-medium data-[state=active]:bg-background data-[state=active]:shadow-xs"
        >
          {sidebarLabel}
        </TabsTrigger>
        <TabsTrigger
          value="form"
          className="h-full flex-1 rounded-sm px-4 text-xs font-medium data-[state=active]:bg-background data-[state=active]:shadow-xs"
        >
          {t('common.edit')}
        </TabsTrigger>
      </TabsList>
    </Tabs>
  ) : null;

  const formContent = (
    <div className="space-y-4">
      {showAssetFields ? (
        <MetadataAssetsEditor
          t={t}
          title={title}
          disabled={isSaving || isMetadataPluginRunning}
          coverAssetId={assetCoverId}
          onCoverAssetIdChange={onAssetCoverIdChange}
          backdropAssetId={assetBackdropId}
          onBackdropAssetIdChange={onAssetBackdropIdChange}
          clearlogoAssetId={assetClearlogoId}
          onClearlogoAssetIdChange={onAssetClearlogoIdChange}
          coverValue={assetCoverValue}
          backdropValue={assetBackdropValue}
          clearlogoValue={assetClearlogoValue}
          onUploadCover={() => {
            void onUploadAssetCover?.();
          }}
          onUploadBackdrop={() => {
            void onUploadAssetBackdrop?.();
          }}
          onUploadClearlogo={() => {
            void onUploadAssetClearlogo?.();
          }}
          uploadingCover={uploadingAssetCover}
          uploadingBackdrop={uploadingAssetBackdrop}
          uploadingClearlogo={uploadingAssetClearlogo}
        />
      ) : null}
      <div>
        <label className="text-sm font-medium">{titleLabel || t('archive.titleField')}</label>
        <Input value={title} onChange={(e) => onTitleChange(e.target.value)} disabled={isSaving} />
      </div>
      <div>
        <label className="text-sm font-medium">{summaryLabel || t('archive.summary')}</label>
        <Textarea
          value={summary}
          onChange={(e) => onSummaryChange(e.target.value)}
          placeholder={summaryPlaceholder || t('archive.summaryPlaceholder')}
          rows={3}
          disabled={isSaving}
        />
      </div>
      {showMetadataPlugin ? (
        <div>
          <label className="text-sm font-medium">{t('tankoubon.metadataPluginLabel')}</label>
          <div className="mt-2 flex flex-col gap-2">
            <div className="flex flex-col sm:flex-row gap-2">
              <div className="sm:w-[220px]">
                <Select value={selectedMetadataPlugin} onValueChange={(next) => onSelectedMetadataPluginChange?.(next)}>
                  <SelectTrigger disabled={isSaving || isMetadataPluginRunning || metadataPlugins.length === 0}>
                    <SelectValue placeholder={t('archive.metadataPluginSelectPlaceholder')} />
                  </SelectTrigger>
                  <SelectContent>
                    {metadataPlugins.map((p) => (
                      <SelectItem key={p.namespace} value={p.namespace}>
                        {p.name} ({p.namespace})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <Input
                value={metadataPluginParam}
                onChange={(e) => onMetadataPluginParamChange?.(e.target.value)}
                disabled={isSaving || isMetadataPluginRunning}
                placeholder={t('archive.metadataPluginParamPlaceholder')}
              />
              <Button
                type="button"
                onClick={() => {
                  void onRunMetadataPlugin?.();
                }}
                disabled={
                  isSaving || isMetadataPluginRunning || metadataPlugins.length === 0 || !selectedMetadataPlugin || !onRunMetadataPlugin
                }
              >
                <Play className="w-4 h-4 mr-2" />
                {isMetadataPluginRunning ? t('archive.metadataPluginRunning') : t('archive.metadataPluginRun')}
              </Button>
            </div>
            {(metadataPluginProgress !== null || metadataPluginMessage) && (
              <div className="text-xs text-muted-foreground flex items-center justify-between gap-2">
                <span className="truncate" title={metadataPluginMessage}>
                  {metadataPluginMessage || ''}
                </span>
                {metadataPluginProgress !== null && (
                  <span className="tabular-nums">{Math.max(0, Math.min(100, metadataPluginProgress))}%</span>
                )}
              </div>
            )}
            {metadataPlugins.length === 0 && (
              <div className="text-xs text-muted-foreground">{t('archive.metadataPluginNoPlugins')}</div>
            )}
          </div>
        </div>
      ) : null}
      <div>
        <label className="text-sm font-medium">{tagsLabel || t('archive.tags')}</label>
        <TagInput value={tags} onChange={onTagsChange} placeholder={tagsPlaceholder || t('archive.tagsPlaceholder')} disabled={isSaving} />
      </div>
    </div>
  );

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent
          size={dialogSize}
          style={showSidebar ? { width: 'min(94vw, 1080px)', maxWidth: '1080px', height: '82vh' } : undefined}
        >
          {showSidebar && !isMobile ? (
            <DialogBody className="h-full min-h-0 flex-1 overflow-hidden p-0">
              <div className="flex h-full max-h-full min-h-0 gap-0 overflow-hidden">
                <div className="h-full max-h-full min-h-0 min-w-0 flex-1 overflow-y-scroll px-0 py-5">
                  {formContent}
                </div>
                <aside className="h-full max-h-full min-h-0 w-80 shrink-0 overflow-y-scroll border-l">
                  {sidebarContent}
                </aside>
              </div>
            </DialogBody>
          ) : showSidebar && isMobile ? (
            <DialogBody className="p-0 overflow-hidden">
              <div className="flex h-full min-h-0 flex-col">
                {mobileToggle}
                <div className="flex-1 min-h-0 overflow-y-auto">
                  {mobileView === 'list' ? (
                    sidebarContent
                  ) : (
                    <div className="px-5 py-5">{formContent}</div>
                  )}
                </div>
              </div>
            </DialogBody>
          ) : (
            <DialogBody className="pt-0 space-y-4">
              {formContent}
            </DialogBody>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={isSaving}>
              {t('common.cancel')}
            </Button>
            <Button
              onClick={() => {
                void onSave();
              }}
              disabled={saveDisabled || isSaving || isMetadataPluginRunning}
            >
              {isSaving ? t('common.saving') : t('common.save')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {rpcSelect ? (
        <Dialog open={!!rpcSelect.request} onOpenChange={() => {}}>
          <DialogContent className="max-w-4xl h-[75vh] flex flex-col">
            <DialogHeader>
              <DialogTitle>{rpcSelect.request?.title || '请选择元数据匹配项'}</DialogTitle>
            </DialogHeader>
            <DialogBody className="pt-0">
              <div
                className="space-y-3 h-full flex flex-col"
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && rpcSelect.selectedIndex != null && (rpcSelect.remainingSeconds ?? 1) > 0) {
                    e.preventDefault();
                    void rpcSelect.onSubmit();
                  }
                }}
              >
                {rpcSelect.request?.message ? (
                  <p className="text-sm text-muted-foreground">{rpcSelect.request.message}</p>
                ) : null}
                <div className="flex-1 min-h-0 overflow-y-auto space-y-2">
                  {(rpcSelect.request?.options || []).map((opt) => (
                    <Button
                      key={`${rpcSelect.request?.request_id}-${opt.index}`}
                      type="button"
                      variant={rpcSelect.selectedIndex === opt.index ? 'default' : 'outline'}
                      className="w-full h-auto py-3 px-3 flex-col items-start gap-1 text-left whitespace-normal"
                      onClick={() => rpcSelect.onSelectIndex(opt.index)}
                    >
                        <div className="flex w-full items-start gap-3">
                          {opt.cover ? (
                          <RawImage
                            src={opt.cover}
                            alt={opt.label || `候选 ${opt.index + 1}`}
                            className="w-20 h-28 shrink-0 object-cover rounded border"
                            loading="lazy"
                          />
                        ) : null}
                          <div className="min-w-0 flex-1 text-left">
                            <div className="font-medium whitespace-normal wrap-break-word">{opt.label || `候选 ${opt.index + 1}`}</div>
                            {opt.description ? (
                              <div className="text-xs text-muted-foreground whitespace-normal">{opt.description}</div>
                            ) : null}
                          </div>
                        </div>
                    </Button>
                  ))}
                </div>
                <p className="text-xs text-muted-foreground">
                  如果长时间不选择，本次预览任务会超时失败。
                  {rpcSelect.remainingSeconds != null ? ` 剩余 ${Math.max(0, rpcSelect.remainingSeconds)} 秒。` : ''}
                </p>
                <div className="flex justify-end gap-2">
                  <Button type="button" variant="outline" onClick={() => void rpcSelect.onAbort()}>
                    放弃
                  </Button>
                  <Button
                    type="button"
                    disabled={rpcSelect.selectedIndex == null || (rpcSelect.remainingSeconds ?? 1) <= 0}
                    onClick={() => void rpcSelect.onSubmit()}
                  >
                    选择并提交
                  </Button>
                </div>
              </div>
            </DialogBody>
          </DialogContent>
        </Dialog>
      ) : null}
    </>
  );
}
