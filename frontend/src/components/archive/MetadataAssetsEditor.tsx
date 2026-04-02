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
        <div className="absolute inset-0 group/backdrop">
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
          <div className="absolute inset-0 bg-linear-to-r from-black/35 via-black/10 to-black/30" />
          <div className="absolute inset-x-0 bottom-0 h-28 bg-linear-to-t from-background/95 via-background/65 to-transparent" />
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={onUploadBackdrop}
            disabled={disabled || uploadingBackdrop || !onUploadBackdrop}
            className="absolute right-3 top-3 z-20 h-8 w-8 rounded-full border-white/20 bg-background/85 p-0 shadow-xs backdrop-blur-xs opacity-0 pointer-events-none transition-opacity group-hover/backdrop:opacity-100 group-hover/backdrop:pointer-events-auto group-focus-within/backdrop:opacity-100 group-focus-within/backdrop:pointer-events-auto focus-visible:opacity-100 focus-visible:pointer-events-auto [@media(hover:none)]:opacity-100 [@media(hover:none)]:pointer-events-auto"
            title={t('archive.assetUploadBackdrop')}
          >
            <ImagePlus className="h-4 w-4" />
            <span className="sr-only">{t('archive.assetUploadBackdrop')}</span>
          </Button>
        </div>

        <div className="absolute left-4 bottom-4 z-10 group/cover">
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
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={onUploadCover}
            disabled={disabled || uploadingCover || !onUploadCover}
            className="absolute right-1.5 top-1.5 z-20 h-8 w-8 rounded-full border-white/20 bg-background/85 p-0 shadow-xs backdrop-blur-xs opacity-0 pointer-events-none transition-opacity group-hover/cover:opacity-100 group-hover/cover:pointer-events-auto group-focus-within/cover:opacity-100 group-focus-within/cover:pointer-events-auto focus-visible:opacity-100 focus-visible:pointer-events-auto [@media(hover:none)]:opacity-100 [@media(hover:none)]:pointer-events-auto"
            title={t('archive.assetUploadCover')}
          >
            <ImageIcon className="h-4 w-4" />
            <span className="sr-only">{t('archive.assetUploadCover')}</span>
          </Button>
        </div>

        <div className="absolute left-28 sm:left-32 right-4 bottom-6 z-10 h-24 sm:h-28 px-3 flex items-center justify-center rounded-md group/clearlogo">
          {clearlogoPreviewUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={clearlogoPreviewUrl}
              alt={t('archive.assetClearlogoLabel')}
              className="max-h-16 sm:max-h-20 max-w-full object-contain"
            />
          ) : (
            <span className="max-w-full truncate text-sm sm:text-base font-semibold text-white/90 drop-shadow-xs">{clearlogoPlaceholder}</span>
          )}
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={onUploadClearlogo}
            disabled={disabled || uploadingClearlogo || !onUploadClearlogo}
            className="absolute right-2 top-2 z-20 h-8 w-8 rounded-full border-white/20 bg-background/85 p-0 shadow-xs backdrop-blur-xs opacity-0 pointer-events-none transition-opacity group-hover/clearlogo:opacity-100 group-hover/clearlogo:pointer-events-auto group-focus-within/clearlogo:opacity-100 group-focus-within/clearlogo:pointer-events-auto focus-visible:opacity-100 focus-visible:pointer-events-auto [@media(hover:none)]:opacity-100 [@media(hover:none)]:pointer-events-auto"
            title={t('archive.assetUploadClearlogo')}
          >
            <ImageIcon className="h-4 w-4" />
            <span className="sr-only">{t('archive.assetUploadClearlogo')}</span>
          </Button>
        </div>
      </div>
    </div>
  );
}
