'use client';

import { Image as ImageIcon, ImagePlus } from 'lucide-react';
import { Button } from '@/components/ui/button';

type Props = {
  t: (key: string) => string;
  title?: string;
  disabled?: boolean;
  coverAssetId: string;
  onCoverAssetIdChange?: (next: string) => void;
  backdropAssetId: string;
  onBackdropAssetIdChange?: (next: string) => void;
  clearlogoAssetId: string;
  onClearlogoAssetIdChange?: (next: string) => void;
  coverValue?: string;
  backdropValue?: string;
  clearlogoValue?: string;
  onUploadCover?: () => void;
  onUploadBackdrop?: () => void;
  onUploadClearlogo?: () => void;
  uploadingCover?: boolean;
  uploadingBackdrop?: boolean;
  uploadingClearlogo?: boolean;
};

function parseAssetId(raw: string): number {
  const n = Number.parseInt(String(raw || '').trim(), 10);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.trunc(n);
}

function resolvePreviewUrl(rawValue: string | undefined, rawAssetId: string): string {
  const value = String(rawValue || '').trim();
  if (value) {
    if (/^\d+$/.test(value)) {
      return `/api/assets/${value}`;
    }
    if (value.startsWith('/') || /^https?:\/\//i.test(value)) {
      return value;
    }
  }

  const assetId = parseAssetId(rawAssetId);
  return assetId > 0 ? `/api/assets/${assetId}` : '';
}

export function MetadataAssetsEditor({
  t,
  title = '',
  disabled = false,
  coverAssetId,
  backdropAssetId,
  clearlogoAssetId,
  coverValue = '',
  backdropValue = '',
  clearlogoValue = '',
  onUploadCover,
  onUploadBackdrop,
  onUploadClearlogo,
  uploadingCover = false,
  uploadingBackdrop = false,
  uploadingClearlogo = false,
}: Props) {
  const coverPreviewUrl = resolvePreviewUrl(coverValue, coverAssetId);
  const backdropPreviewUrl = resolvePreviewUrl(backdropValue, backdropAssetId);
  const clearlogoPreviewUrl = resolvePreviewUrl(clearlogoValue, clearlogoAssetId);
  const clearlogoPlaceholder = String(title || '').trim() || t('archive.titleField');

  return (
    <div className="rounded-md border overflow-hidden">
      <div className="relative h-40 sm:h-44">
        {backdropPreviewUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={backdropPreviewUrl}
            alt={t('archive.assetBackdropLabel')}
            className="absolute inset-0 h-full w-full object-cover"
          />
        ) : (
          <div
            className="absolute inset-0 bg-muted"
            style={{
              backgroundImage:
                'radial-gradient(120% 90% at 100% 0%, rgba(148,163,184,0.28), transparent 55%), radial-gradient(120% 90% at 0% 100%, rgba(100,116,139,0.22), transparent 55%)',
            }}
          />
        )}
        <div className="absolute inset-0 bg-gradient-to-r from-black/35 via-black/10 to-black/30" />
        <div className="absolute inset-x-0 bottom-0 h-28 bg-gradient-to-t from-background/95 via-background/65 to-transparent" />

        <div className="absolute left-4 bottom-4 z-10">
          <div className="h-28 w-20 sm:h-32 sm:w-24 rounded-lg border-2 border-white/80 bg-muted/40 shadow-xl overflow-hidden flex items-center justify-center">
            {coverPreviewUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={coverPreviewUrl}
                alt={t('archive.assetCoverLabel')}
                className="h-full w-full object-cover"
              />
            ) : (
              <ImageIcon className="h-8 w-8 text-muted-foreground/80" />
            )}
          </div>
        </div>

        <div className="absolute left-28 sm:left-32 right-4 bottom-8 z-10 h-20 sm:h-24 px-3 flex items-center justify-center">
          {clearlogoPreviewUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={clearlogoPreviewUrl}
              alt={t('archive.assetClearlogoLabel')}
              className="max-h-14 sm:max-h-16 max-w-full object-contain"
            />
          ) : (
            <span className="max-w-full truncate text-sm sm:text-base font-semibold text-white/90 drop-shadow-sm">{clearlogoPlaceholder}</span>
          )}
        </div>
      </div>

      <div className="pt-3 pb-3 px-3">
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onUploadCover}
            disabled={disabled || uploadingCover || !onUploadCover}
            className="flex items-center gap-2 justify-center"
          >
            <ImageIcon className="w-4 h-4" />
            {t('archive.assetUploadCover')}
          </Button>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onUploadBackdrop}
            disabled={disabled || uploadingBackdrop || !onUploadBackdrop}
            className="flex items-center gap-2 justify-center"
          >
            <ImagePlus className="w-4 h-4" />
            {t('archive.assetUploadBackdrop')}
          </Button>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onUploadClearlogo}
            disabled={disabled || uploadingClearlogo || !onUploadClearlogo}
            className="flex items-center gap-2 justify-center"
          >
            <ImageIcon className="w-4 h-4" />
            {t('archive.assetUploadClearlogo')}
          </Button>
        </div>
      </div>
    </div>
  );
}
