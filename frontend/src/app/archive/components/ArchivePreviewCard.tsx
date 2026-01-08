'use client';

import Image from 'next/image';
import Link from 'next/link';
import { BookOpen, Eye, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import type { ArchiveMetadata } from '@/types/archive';
import type { PageInfo } from '@/lib/archive-service';

type Props = {
  metadata: ArchiveMetadata;
  t: (key: string) => string;
  showPreview: boolean;
  setShowPreview: (next: boolean) => void;
  previewLoading: boolean;
  previewError: string | null;
  archivePages: PageInfo[];
  displayPages: PageInfo[];
  loadingImages: Set<number>;
  loadMorePages: () => void;
  handleImageLoadEnd: (pageIndex: number) => void;
  handleImageError: (pageIndex: number) => void;
};

export function ArchivePreviewCard({
  metadata,
  t,
  showPreview,
  setShowPreview,
  previewLoading,
  previewError,
  archivePages,
  displayPages,
  loadingImages,
  loadMorePages,
  handleImageLoadEnd,
  handleImageError,
}: Props) {
  return (
    <Card>
      <CardHeader className="pb-4">
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
          ) : archivePages.length === 0 ? (
            <div className="flex items-center justify-center py-12">
              <p className="text-muted-foreground">{t('archive.noPreviewPages')}</p>
            </div>
          ) : (
            <div className="space-y-4">
              {metadata.archivetype === 'epub' ? (
                <div className="space-y-1">
                  {displayPages.map((page, index) => (
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
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
                  {displayPages.map((page, index) => {
                    const actualPageIndex = index;
                    const isLoading = loadingImages.has(actualPageIndex);

                    return (
                      <Link
                        key={actualPageIndex}
                        href={`/reader?id=${metadata.arcid}&page=${actualPageIndex + 1}`}
                        className="group relative aspect-[3/4] bg-muted rounded-lg overflow-hidden hover:ring-2 hover:ring-primary transition-all duration-200"
                      >
                        {isLoading && (
                          <div className="absolute inset-0 flex items-center justify-center bg-muted/50 z-10">
                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary"></div>
                          </div>
                        )}

                        <div className="relative w-full h-full">
                          {page.type === 'video' ? (
                            <video
                              src={page.url}
                              className="w-full h-full object-cover"
                              muted
                              loop
                              playsInline
                              onMouseEnter={(e) => {
                                const video = e.target as HTMLVideoElement;
                                video.play().catch(() => {});
                              }}
                              onMouseLeave={(e) => {
                                const video = e.target as HTMLVideoElement;
                                video.pause();
                                video.currentTime = 0;
                              }}
                            />
                          ) : (
                            <Image
                              src={page.url}
                              alt={t('archive.previewPage')
                                .replace('{current}', String(actualPageIndex + 1))
                                .replace('{total}', String(archivePages.length))}
                              fill
                              className={`object-contain transition-opacity duration-200 ${isLoading ? 'opacity-0' : 'opacity-100'}`}
                              onLoadingComplete={() => handleImageLoadEnd(actualPageIndex)}
                              onError={() => handleImageError(actualPageIndex)}
                              draggable={false}
                            />
                          )}
                        </div>

                        <div className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-xs py-1 px-1 text-center truncate">
                          {actualPageIndex + 1}
                          {page.type === 'video' ? ' 🎬' : ''}
                        </div>

                        <div className="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-20 transition-all duration-200 flex items-center justify-center">
                          <div className="opacity-0 group-hover:opacity-100 transition-opacity duration-200 bg-white bg-opacity-90 text-gray-800 px-2 py-1 rounded text-xs font-medium">
                            {t('archive.clickToRead')}
                          </div>
                        </div>
                      </Link>
                    );
                  })}
                </div>
              )}

              {displayPages.length < archivePages.length && (
                <div className="flex justify-center pt-4">
                  <Button
                    variant="outline"
                    onClick={loadMorePages}
                    disabled={previewLoading}
                    className="text-sm"
                  >
                    {t('archive.loadMore')} ({archivePages.length - displayPages.length} {t('common.next')})
                  </Button>
                </div>
              )}
            </div>
          )}
        </CardContent>
      )}
    </Card>
  );
}

