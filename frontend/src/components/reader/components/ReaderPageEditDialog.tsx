'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Checkbox } from '@/components/ui/checkbox';
import { Spinner } from '@/components/ui/spinner';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ChunkedUploadService } from '@/lib/services/chunked-upload-service';
import { toast } from '@/lib/ui/feedback';
import { logger } from '@/lib/utils/logger';
import type { MetadataPageAttachment } from '@/types/archive';
import { ImagePlus, Plus, Trash2, Upload } from 'lucide-react';

const SLOT_OPTIONS = [
  { value: 'lyrics', labelKey: 'reader.pageEditSlotLyrics' },
  { value: 'subtitle', labelKey: 'reader.pageEditSlotSubtitle' },
  { value: 'font', labelKey: 'reader.pageEditSlotFont' },
  { value: 'attachment', labelKey: 'reader.pageEditSlotAttachment' },
];
const KIND_OPTIONS = ['lrc', 'vtt', 'srt', 'ass', 'ttml', 'txt', 'otf', 'ttf', 'woff2'];

export type PageEditData = {
  title: string;
  description: string;
  thumb: string;
  release_at: string;
  order_index: number;
  hidden_in_files: boolean;
  attachments: MetadataPageAttachment[];
};

type Props = {
  open: boolean;
  onOpenChange: (next: boolean) => void;
  pageNumber: number;
  title: string;
  description: string;
  thumb: string;
  releaseAt: string;
  orderIndex: number;
  hiddenInFiles: boolean;
  attachments: MetadataPageAttachment[];
  isSaving: boolean;
  onSave: (data: PageEditData) => void;
  t: (key: string) => string;
};

function emptyAttachment(): MetadataPageAttachment {
  return { slot: 'lyrics', name: '' };
}

function uploadAttachFile(attachIndex: number, callback: (assetId: string) => void, t: (k: string) => string) {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '*/*';

  input.onchange = async (event) => {
    const e = event as unknown as Event;
    const target = e.target as HTMLInputElement;
    const file = target.files?.[0];
    if (!file) return;

    try {
      const result = await ChunkedUploadService.uploadWithChunks(
        file,
        {
          targetType: 'metadata_asset',
          overwrite: true,
          contentType: file.type || 'application/octet-stream',
        },
        { onProgress: () => {}, onChunkComplete: () => {}, onError: () => {} }
      );
      if (!result.success) throw new Error(result.error || t('archive.assetUploadFailed'));

      const assetId = Number(result.data?.assetId ?? 0);
      if (!Number.isFinite(assetId) || assetId <= 0) throw new Error(t('archive.assetUploadFailed'));

      callback(String(Math.trunc(assetId)));
      toast.success(t('archive.assetUploadSuccess'));
    } catch (error) {
      logger.operationFailed('upload page attachment', error);
      toast.error(t('archive.assetUploadFailed'));
    }
  };

  document.body.appendChild(input);
  input.click();
}

function AttachmentRow({
  att,
  index,
  disabled,
  onUpdate,
  onRemove,
  onUpload,
  uploading,
  t,
}: {
  att: MetadataPageAttachment;
  index: number;
  disabled: boolean;
  onUpdate: (i: number, att: MetadataPageAttachment) => void;
  onRemove: (i: number) => void;
  onUpload: (i: number) => void;
  uploading: boolean;
  t: (key: string) => string;
}) {
  const update = (patch: Partial<MetadataPageAttachment>) => {
    onUpdate(index, { ...att, ...patch });
  };

  const rowDisabled = disabled || uploading;
  const hasFile = att.asset_id ? att.asset_id > 0 : false;

  return (
    <div className="rounded-md border border-border/60 bg-muted/20 p-3 space-y-2">
      <div className="grid grid-cols-2 gap-2">
        <div>
          <label className="text-[11px] text-muted-foreground block mb-0.5">{t('reader.pageEditAttachmentSlot')}</label>
          <Select
            value={att.slot}
            onValueChange={(value) => update({ slot: value })}
            disabled={rowDisabled}
          >
            <SelectTrigger className="h-8 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {SLOT_OPTIONS.map((opt) => (
                <SelectItem key={opt.value} value={opt.value}>
                  {t(opt.labelKey)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div>
          <label className="text-[11px] text-muted-foreground block mb-0.5">{t('reader.pageEditAttachmentName')}</label>
          <Input
            value={att.name}
            onChange={(e) => update({ name: e.target.value })}
            disabled={rowDisabled}
            className="h-8 text-xs"
          />
        </div>
        <div>
          <label className="text-[11px] text-muted-foreground block mb-0.5">{t('reader.pageEditAttachmentKind')}</label>
          <input
            list={`attach-kind-${index}`}
            value={att.kind || ''}
            onChange={(e) => update({ kind: e.target.value || undefined })}
            disabled={rowDisabled}
            className="flex h-8 w-full rounded border border-input bg-background px-2 py-1 text-xs ring-offset-background placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50"
          />
          <datalist id={`attach-kind-${index}`}>
            {KIND_OPTIONS.map((k) => <option key={k} value={k} />)}
          </datalist>
        </div>
        <div>
          <label className="text-[11px] text-muted-foreground block mb-0.5">{t('reader.pageEditAttachmentLanguage')}</label>
          <Input
            value={att.language || ''}
            onChange={(e) => update({ language: e.target.value || undefined })}
            disabled={rowDisabled}
            placeholder="zh"
            className="h-8 text-xs"
          />
        </div>
      </div>

      <div className="flex items-center justify-between gap-2">
        <span className="text-[11px] text-muted-foreground">
          {hasFile ? `✓ asset#${att.asset_id}` : t('reader.pageEditAttachmentNoFile')}
        </span>
        <div className="flex items-center gap-1">
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => onUpload(index)}
            disabled={rowDisabled}
            className="h-7 text-xs gap-1"
          >
            {uploading ? <Spinner className="h-3 w-3" /> : <Upload className="h-3 w-3" />}
            {t('reader.pageEditAttachmentUpload')}
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => onRemove(index)}
            disabled={rowDisabled}
            className="h-7 text-xs text-destructive hover:text-destructive gap-1"
          >
            <Trash2 className="h-3 w-3" />
          </Button>
        </div>
      </div>
    </div>
  );
}

export function ReaderPageEditDialog({
  open,
  onOpenChange,
  pageNumber,
  title: initialTitle,
  description: initialDescription,
  thumb: initialThumb,
  releaseAt: initialReleaseAt,
  orderIndex: initialOrderIndex,
  hiddenInFiles: initialHiddenInFiles,
  attachments: initialAttachments,
  isSaving,
  onSave,
  t,
}: Props) {
  const [title, setTitle] = useState(initialTitle);
  const [description, setDescription] = useState(initialDescription);
  const [thumb, setThumb] = useState(initialThumb);
  const [releaseAt, setReleaseAt] = useState(initialReleaseAt);
  const [orderIndexStr, setOrderIndexStr] = useState(
    initialOrderIndex > 0 ? String(initialOrderIndex) : ''
  );
  const [hiddenInFiles, setHiddenInFiles] = useState(initialHiddenInFiles);
  const [attachments, setAttachments] = useState<MetadataPageAttachment[]>(initialAttachments);
  const [uploadingThumb, setUploadingThumb] = useState(false);
  const [thumbLoadError, setThumbLoadError] = useState(false);

  const updateAttachment = (index: number, att: MetadataPageAttachment) => {
    setAttachments((prev) => prev.map((a, i) => (i === index ? att : a)));
  };

  const removeAttachment = (index: number) => {
    setAttachments((prev) => prev.filter((_, i) => i !== index));
  };

  const addAttachment = () => {
    setAttachments((prev) => [...prev, emptyAttachment()]);
  };

  const uploadAttachmentFile = (index: number) => {
    uploadAttachFile(index, (assetId) => {
      setAttachments((prev) =>
        prev.map((a, i) =>
          i === index ? { ...a, asset_id: Number(assetId) } : a
        )
      );
    }, t);
  };

  const handleThumbUpload = () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';

    input.onchange = async (event) => {
      const e = event as unknown as Event;
      const target = e.target as HTMLInputElement;
      const file = target.files?.[0];
      if (!file) return;

      setUploadingThumb(true);
      try {
        const result = await ChunkedUploadService.uploadWithChunks(
          file,
          {
            targetType: 'metadata_asset',
            overwrite: true,
            contentType: file.type || 'application/octet-stream',
          },
          { onProgress: () => {}, onChunkComplete: () => {}, onError: () => {} }
        );
        if (!result.success) throw new Error(result.error || t('archive.assetUploadFailed'));

        const assetId = Number(result.data?.assetId ?? 0);
        if (!Number.isFinite(assetId) || assetId <= 0) throw new Error(t('archive.assetUploadFailed'));

        setThumb(`/api/assets/${Math.trunc(assetId)}`);
        setThumbLoadError(false);
        toast.success(t('archive.assetUploadSuccess'));
      } catch (error) {
        logger.operationFailed('upload page thumb', error);
        toast.error(t('archive.assetUploadFailed'));
      } finally {
        setUploadingThumb(false);
      }
    };

    document.body.appendChild(input);
    input.click();
  };

  const handleClearThumb = () => {
    setThumb('');
    setThumbLoadError(false);
  };

  const handleSave = () => {
    const orderIndex = parseInt(orderIndexStr, 10);
    onSave({
      title,
      description,
      thumb: thumb.trim(),
      release_at: releaseAt,
      order_index: Number.isFinite(orderIndex) && orderIndex > 0 ? orderIndex : 0,
      hidden_in_files: hiddenInFiles,
      attachments,
    });
  };

  const disabled = isSaving || uploadingThumb;
  const thumbPreviewUrl = thumb && !thumbLoadError ? thumb : '';

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {t('reader.pageEdit')} — {t('reader.pageAlt').replace('{page}', String(pageNumber))}
          </DialogTitle>
        </DialogHeader>
        <DialogBody>
          <div className="space-y-5">
            <div>
              <label className="text-sm font-medium">{t('reader.pageEditThumb')}</label>
              <div className="mt-1 rounded-md border border-border/60 overflow-hidden bg-muted/30">
                <div className="relative h-32 sm:h-36 group/thumb">
                  {thumbPreviewUrl ? (
                    <img
                      src={thumbPreviewUrl}
                      alt="thumbnail"
                      className="absolute inset-0 h-full w-full object-cover"
                      onError={() => setThumbLoadError(true)}
                    />
                  ) : (
                    <div className="absolute inset-0 flex items-center justify-center text-muted-foreground/50 text-xs">
                      {t('archive.noCover')}
                    </div>
                  )}

                  <div className="absolute inset-0 bg-linear-to-t from-black/40 to-transparent opacity-0 group-hover/thumb:opacity-100 transition-opacity" />

                  <div className="absolute right-2 top-2 z-10 flex items-center gap-1.5 opacity-0 group-hover/thumb:opacity-100 transition-opacity [@media(hover:none)]:opacity-100">
                    <Button
                      type="button"
                      variant="outline"
                      size="icon"
                      onClick={handleThumbUpload}
                      disabled={disabled}
                      className="h-8 w-8 rounded-full border-white/20 bg-background/85 shadow-xs backdrop-blur-xs"
                      title={t('archive.assetUploadCover')}
                    >
                      {uploadingThumb ? (
                        <Spinner className="h-3.5 w-3.5" />
                      ) : (
                        <ImagePlus className="h-4 w-4" />
                      )}
                    </Button>
                    {thumb ? (
                      <Button
                        type="button"
                        variant="outline"
                        size="icon"
                        onClick={handleClearThumb}
                        disabled={disabled}
                        className="h-8 w-8 rounded-full border-white/20 bg-background/85 shadow-xs backdrop-blur-xs text-destructive hover:text-destructive"
                        title={t('common.clear')}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    ) : null}
                  </div>
                </div>
              </div>
            </div>

            <div>
              <label className="text-sm font-medium">{t('reader.pageEditTitle')}</label>
              <Input
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder={t('reader.pageEditTitlePlaceholder')}
                disabled={disabled}
              />
            </div>
            <div>
              <label className="text-sm font-medium">{t('reader.pageEditDescription')}</label>
              <Textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder={t('reader.pageEditDescriptionPlaceholder')}
                rows={3}
                disabled={disabled}
              />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm font-medium">{t('archive.releaseAt')}</label>
                <Input
                  type="date"
                  value={releaseAt}
                  onChange={(e) => setReleaseAt(e.target.value)}
                  disabled={disabled}
                />
              </div>
              <div>
                <label className="text-sm font-medium">{t('reader.pageEditOrderIndex')}</label>
                <Input
                  type="number"
                  value={orderIndexStr}
                  onChange={(e) => setOrderIndexStr(e.target.value)}
                  placeholder="0"
                  min={0}
                  disabled={disabled}
                />
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Checkbox
                id="hidden-in-files"
                checked={hiddenInFiles}
                onCheckedChange={(checked) => setHiddenInFiles(checked === true)}
                disabled={disabled}
              />
              <label htmlFor="hidden-in-files" className="text-sm cursor-pointer select-none">
                {t('reader.pageEditHiddenInFiles')}
              </label>
            </div>

            <div>
              <label className="text-sm font-medium">{t('reader.pageEditAttachments')}</label>
              <div className="mt-2 space-y-2">
                {attachments.map((att, i) => (
                  <AttachmentRow
                    key={`attach-${i}-${att.slot}`}
                    att={att}
                    index={i}
                    disabled={disabled}
                    onUpdate={updateAttachment}
                    onRemove={removeAttachment}
                    onUpload={uploadAttachmentFile}
                    uploading={false}
                    t={t}
                  />
                ))}
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={addAttachment}
                  disabled={disabled}
                  className="w-full h-8 text-xs gap-1"
                >
                  <Plus className="h-3.5 w-3.5" />
                  {t('reader.pageEditAttachmentAdd')}
                </Button>
              </div>
            </div>
          </div>
        </DialogBody>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={disabled}>
            {t('common.cancel')}
          </Button>
          <Button onClick={handleSave} disabled={disabled}>
            {isSaving ? t('common.saving') : t('common.save')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
