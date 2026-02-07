'use client';

import Image from 'next/image';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { ArchiveService } from '@/lib/services/archive-service';

export function ReaderCollectionEndPage({
  enabled,
  mode = 'overlay',
  finishedId,
  finishedTitle,
  finishedCoverAssetId,
  nextId,
  nextTitle,
  nextCoverAssetId,
  t,
}: {
  enabled: boolean;
  mode?: 'overlay' | 'inline';
  finishedId: string | null;
  finishedTitle: string;
  finishedCoverAssetId?: number;
  nextId: string | null;
  nextTitle: string | null;
  nextCoverAssetId?: number;
  t: (key: string) => string;
}) {
  if (!enabled) return null;

  const finishedCoverUrl = ArchiveService.getAssetUrl(finishedCoverAssetId);
  const nextCoverUrl = ArchiveService.getAssetUrl(nextCoverAssetId);
  const finishedHeading = finishedTitle || '';
  const nextHeading = nextTitle
    ? t('reader.nextChapter').replace('{title}', nextTitle)
    : t('reader.noNextChapter').replace('{title}', finishedTitle || '');

  return (
    <div
      className={
        mode === 'overlay'
          ? 'absolute inset-0 flex items-center justify-center bg-background text-foreground'
          : 'w-full flex items-center justify-center bg-background text-foreground'
      }
    >
      <div className="w-full max-w-2xl px-6 py-8">
        <div className="rounded-xl border border-border bg-background/95 shadow-lg overflow-hidden">
          <div className="p-5 sm:p-6">
            <div className="text-base sm:text-lg font-semibold leading-snug line-clamp-2">
              {t('reader.finishedReading').replace('{title}', finishedTitle || '')}
            </div>

            <div className="mt-5 grid grid-cols-2 gap-4 sm:gap-6 items-start">
              <div className="flex flex-col">
                <div className="min-h-[3.25rem]">
                  <div className="text-xs text-muted-foreground">{t('common.details')}</div>
                  <div className="mt-1 text-sm font-medium leading-snug line-clamp-2">{finishedHeading}</div>
                </div>

                <Link
                  href={finishedId ? `/archive?id=${finishedId}` : '#'}
                  prefetch={false}
                  className={finishedId ? 'block mt-2' : 'block mt-2 pointer-events-none opacity-60'}
                >
                  <div className="relative aspect-[3/4] rounded-lg bg-muted overflow-hidden">
                    {finishedCoverUrl ? (
                      <Image
                        src={finishedCoverUrl}
                        alt={finishedTitle}
                        fill
                        sizes="(max-width: 640px) 45vw, 320px"
                        className="object-cover"
                        decoding="async"
                      />
                    ) : (
                      <div className="absolute inset-0 flex items-center justify-center text-xs text-muted-foreground">
                        {t('archive.noCover')}
                      </div>
                    )}
                  </div>
                </Link>

                {finishedId ? (
                  <div className="mt-3">
                    <Button asChild variant="outline" size="sm" className="w-full">
                      <Link href={`/archive?id=${finishedId}`} prefetch={false}>
                        {t('common.details')}
                      </Link>
                    </Button>
                  </div>
                ) : null}
              </div>

              <div className="flex flex-col">
                <div className="min-h-[3.25rem]">
                  <div className="text-xs text-muted-foreground">{t('reader.nextChapterLabel')}</div>
                  <div className="mt-1 text-sm font-medium leading-snug line-clamp-2">{nextHeading}</div>
                </div>

                <Link
                  href={nextId ? `/archive?id=${nextId}` : '#'}
                  prefetch={false}
                  className={nextId ? 'block mt-2' : 'block mt-2 pointer-events-none opacity-60'}
                >
                  <div className="relative aspect-[3/4] rounded-lg bg-muted overflow-hidden">
                    {nextCoverUrl ? (
                      <Image
                        src={nextCoverUrl}
                        alt={nextTitle || ''}
                        fill
                        sizes="(max-width: 640px) 45vw, 320px"
                        className="object-cover"
                        decoding="async"
                      />
                    ) : (
                      <div className="absolute inset-0 flex items-center justify-center text-xs text-muted-foreground">
                        {t('archive.noCover')}
                      </div>
                    )}
                  </div>
                </Link>

                <div className="mt-3 flex gap-2">
                  {nextId ? (
                    <Button asChild variant="outline" size="sm" className="flex-1">
                      <Link href={`/archive?id=${nextId}`} prefetch={false}>
                        {t('common.details')}
                      </Link>
                    </Button>
                  ) : null}
                  {nextId ? (
                    <Button asChild size="sm" className="flex-1">
                      <Link href={`/reader?id=${nextId}&page=1`} prefetch={false}>
                        {t('common.read')}
                      </Link>
                    </Button>
                  ) : null}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
