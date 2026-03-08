'use client';

import Link from 'next/link';
import { BookOpen, Eye, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { cn } from '@/lib/utils/utils';
import type { ArchiveMetadata } from '@/types/archive';
import type { PageInfo } from '@/lib/services/archive-service';
import { MasonryThumbnailGrid } from '@/components/ui/masonry-thumbnail-grid';

type Props = {
  metadata: ArchiveMetadata;
  t: (key: string) => string;
  showPreview: boolean;
  setShowPreview: (next: boolean) => void;
  previewLoading: boolean;
  previewError: string | null;
  pages: PageInfo[];
};

export function ArchivePreviewCard({
  metadata,
  t,
  showPreview,
  setShowPreview,
  previewLoading,
  previewError,
  pages,
}: Props) {
  return (
    <Card className="bg-card/70 backdrop-blur dark:bg-card/70">
      {/* When collapsed, default CardHeader padding makes the row feel a bit low; tighten it. */}
      <CardHeader className={cn(showPreview ? 'pb-4' : 'py-4')}>
        <div className="flex items-center justify-between">
          <CardTitle className="flex items-center text-lg lg:text-xl">
            <Eye className="w-5 h-5 mr-2" />
            {metadata.archivetype === 'epub' ? t('archive.chapterList') : t('archive.pageThumbnails')}
          </CardTitle>
          {!showPreview ? (
            <Button variant="outline" size="sm" onClick={() => setShowPreview(true)} className="text-sm">
              <Eye className="w-4 h-4 mr-2" />
              {t('archive.preview')}
            </Button>
          ) : (
            <Button variant="outline" size="sm" onClick={() => setShowPreview(false)} className="text-sm">
              <X className="w-4 h-4 mr-2" />
              {t('common.close')}
            </Button>
          )}
        </div>
      </CardHeader>

      {showPreview && (
        <CardContent className="space-y-4">
          {previewLoading ? (
            <div className="flex items-center justify-center py-12">
              <p className="text-muted-foreground">{t('common.loading')}</p>
            </div>
          ) : previewError ? (
            <div className="flex items-center justify-center py-12">
              <p className="text-red-500">{previewError}</p>
            </div>
          ) : pages.length === 0 ? (
            <div className="flex items-center justify-center py-12">
              <p className="text-muted-foreground">{t('archive.noPreviewPages')}</p>
            </div>
          ) : (
            <div className="space-y-4">
              {metadata.archivetype === 'epub' ? (
                <div className="space-y-1">
                  {pages.map((page, index) => (
                    <Link
                      key={index}
                      href={`/reader?id=${metadata.arcid}&page=${index + 1}`}
                      className="flex items-center gap-3 p-3 rounded-lg hover:bg-muted transition-colors group"
                    >
                      <span className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 text-primary flex items-center justify-center text-sm font-medium">
                        {index + 1}
                      </span>
                      <span className="flex-1 truncate text-sm group-hover:text-primary transition-colors">
                        {page.title || `${t('archive.chapter')} ${index + 1}`}
                      </span>
                      <BookOpen className="w-4 h-4 text-muted-foreground group-hover:text-primary transition-colors" />
                    </Link>
                  ))}
                </div>
              ) : (
                <div className="h-[500px] overflow-hidden">
                  <MasonryThumbnailGrid
                    pages={pages}
                    archiveId={metadata.arcid}
                    isLink={true}
                    t={t}
                    className="h-full"
                  />
                </div>
              )}
            </div>
          )}
        </CardContent>
      )}
    </Card>
  );
}
