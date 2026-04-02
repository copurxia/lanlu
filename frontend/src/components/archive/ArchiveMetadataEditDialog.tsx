'use client';

import { Play } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { TagInput } from '@/components/ui/tag-input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { MetadataAssetsEditor } from '@/components/archive/MetadataAssetsEditor';
import type { Plugin } from '@/lib/services/plugin-service';
export type { RpcSelectOption, RpcSelectRequest } from '@/types/metadata-plugin';
import type { RpcSelectRequest } from '@/types/metadata-plugin';

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
};

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
}: Props) {
  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent>
          <DialogBody>
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
          </DialogBody>
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
                          // eslint-disable-next-line @next/next/no-img-element
                          <img
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
