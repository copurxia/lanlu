'use client';

export function ReaderCollectionEndPage({
  enabled,
  finishedTitle,
  nextTitle,
  t,
}: {
  enabled: boolean;
  finishedTitle: string;
  nextTitle: string | null;
  t: (key: string) => string;
}) {
  if (!enabled) return null;

  return (
    <div className="absolute inset-0 flex items-center justify-center bg-background text-foreground">
      <div className="text-center px-6">
        <div className="text-lg font-semibold">
          {t('reader.finishedReading').replace('{title}', finishedTitle || '')}
        </div>
        <div className="mt-2 text-sm text-muted-foreground">
          {nextTitle
            ? t('reader.nextChapter').replace('{title}', nextTitle)
            : t('reader.noNextChapter').replace('{title}', finishedTitle || '')}
        </div>
      </div>
    </div>
  );
}

