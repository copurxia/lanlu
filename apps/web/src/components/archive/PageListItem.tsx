'use client';

import { Button } from '@/components/ui/button';
import { RawImage } from '@/components/ui/raw-image';
import { useLanguage } from '@/contexts/LanguageContext';
import { cn } from '@/lib/utils/utils';
import { Edit, FileText, Trash2 } from 'lucide-react';
import type { MetadataPagePatch } from '@/types/archive';

type PageListItemProps = {
  page: MetadataPagePatch;
  index: number;
  onEdit?: (page: MetadataPagePatch) => void;
  onRemove?: (page: MetadataPagePatch) => void;
};

export function PageListItem({ page, index, onEdit, onRemove }: PageListItemProps) {
  const { t } = useLanguage();
  const pageNum = page.page_number ?? index + 1;
  const pageTitle = page.title || `#${pageNum}`;
  const hasActions = Boolean(onEdit || onRemove);

  return (
    <div
      className={cn(
        'flex items-start gap-2.5 rounded-md border border-border/40 px-2.5 py-2 transition-colors',
        'hover:border-border hover:bg-muted/40'
      )}
    >
      {page.thumb ? (
        <div className="relative h-10 w-7 shrink-0 overflow-hidden rounded bg-muted">
          <RawImage
            src={page.thumb}
            alt={pageTitle}
            className="h-full w-full object-cover"
          />
        </div>
      ) : (
        <div className="flex h-10 w-7 shrink-0 items-center justify-center rounded bg-muted">
          <FileText className="h-4 w-4 text-muted-foreground" />
        </div>
      )}

      <div className={cn('min-w-0', hasActions ? 'flex-1 pr-1' : 'flex-1')}>
        <span
          className="text-xs font-medium leading-tight line-clamp-1"
          title={pageTitle}
        >
          {pageTitle}
        </span>
        {page.description ? (
          <p
            className="text-[11px] text-muted-foreground line-clamp-1"
            title={page.description}
          >
            {page.description}
          </p>
        ) : null}
      </div>

      {hasActions && (
        <div className="flex shrink-0 flex-col items-center gap-1">
          {onEdit && (
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="h-6 w-6 text-muted-foreground hover:text-foreground"
              title={t('common.edit')}
              onClick={() => onEdit(page)}
            >
              <Edit className="h-3.5 w-3.5" />
            </Button>
          )}
          {onRemove && (
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="h-6 w-6 text-muted-foreground hover:text-destructive"
              title={t('common.delete')}
              onClick={() => onRemove(page)}
            >
              <Trash2 className="h-3.5 w-3.5" />
            </Button>
          )}
        </div>
      )}
    </div>
  );
}
