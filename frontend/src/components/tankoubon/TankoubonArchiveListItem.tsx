'use client';

import { useMemo } from 'react';
import Image from 'next/image';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Spinner } from '@/components/ui/spinner';
import { useLanguage } from '@/contexts/LanguageContext';
import { getArchiveAssetId } from '@/lib/utils/archive-assets';
import { parseTags, stripNamespace } from '@/lib/utils/tag-utils';
import { cn } from '@/lib/utils/utils';
import { Edit, Trash2 } from 'lucide-react';
import type { Archive } from '@/types/archive';

type TankoubonArchiveListItemProps = {
  archive: Archive;
  isRemoving?: boolean;
  onEdit: (archive: Archive) => void;
  onRemove: (archive: Archive) => void;
};

export function TankoubonArchiveListItem({
  archive,
  isRemoving = false,
  onEdit,
  onRemove,
}: TankoubonArchiveListItemProps) {
  const { t } = useLanguage();
  const coverAssetId = getArchiveAssetId(archive, 'cover');
  const parsedTags = useMemo(
    () => parseTags(archive.tags).map(stripNamespace).slice(0, 4),
    [archive.tags]
  );

  return (
    <div
      className={cn(
        'flex items-start gap-2.5 rounded-md border border-border/40 px-2.5 py-2 transition-colors',
        'hover:border-border hover:bg-muted/40'
      )}
    >
      <div className="relative h-16 w-11 shrink-0 overflow-hidden rounded bg-muted">
        {coverAssetId ? (
          <Image
            src={`/api/assets/${coverAssetId}`}
            alt={archive.title}
            fill
            className="object-cover"
            sizes="44px"
            decoding="async"
          />
        ) : (
          <div className="absolute inset-0 flex items-center justify-center text-[9px] text-muted-foreground">
            {t('archive.noCover')}
          </div>
        )}
      </div>

      <div className="min-w-0 flex-1">
        <h3
          className="text-sm font-medium leading-tight line-clamp-2"
          title={archive.title}
        >
          {archive.title}
        </h3>

        {archive.description ? (
          <p
            className="mt-0.5 text-xs text-muted-foreground line-clamp-2"
            title={archive.description}
          >
            {archive.description}
          </p>
        ) : null}

        {parsedTags.length > 0 && (
          <div className="mt-1.5 flex flex-wrap gap-1">
            {parsedTags.map((tag) => (
              <Badge
                key={`${archive.arcid}-${tag}`}
                variant="secondary"
                className="max-w-full text-[10px]"
                title={tag}
              >
                <span className="truncate">{tag}</span>
              </Badge>
            ))}
          </div>
        )}
      </div>

      <div className="flex shrink-0 flex-col items-center gap-1">
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-6 w-6 text-muted-foreground hover:text-foreground"
          title={t('common.edit')}
          onClick={() => onEdit(archive)}
        >
          <Edit className="h-3.5 w-3.5" />
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="h-6 w-6 text-muted-foreground hover:text-destructive"
          title={t('tankoubon.removeArchive')}
          disabled={isRemoving}
          onClick={() => onRemove(archive)}
        >
          {isRemoving ? <Spinner size="sm" /> : <Trash2 className="h-3.5 w-3.5" />}
        </Button>
      </div>
    </div>
  );
}
