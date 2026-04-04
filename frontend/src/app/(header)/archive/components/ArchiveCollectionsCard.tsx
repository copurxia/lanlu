'use client';

import Link from 'next/link';
import { FolderOpen } from 'lucide-react';
import type { Tankoubon } from '@/types/tankoubon';
import type { Archive } from '@/types/archive';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ArchiveCard } from '@/components/archive/ArchiveCard';
import { useGridRowCoverHeights } from '@/hooks/use-grid-row-cover-heights';

type Props = {
  t: (key: string) => string;
  currentArchiveId: string;
  tankoubons: Tankoubon[];
  previewArchivesByTankoubonId: Record<string, Archive[]>;
  loading: boolean;
};

function CollectionPreviewGrid({
  tankoubonId,
  archives,
  currentArchiveId,
}: {
  tankoubonId: string;
  archives: Archive[];
  currentArchiveId: string;
}) {
  const itemKeys = archives.map((archive) => `${tankoubonId}:${archive.arcid}`);
  const { containerRef, coverHeights, reportCoverAspectRatio } = useGridRowCoverHeights(itemKeys);

  return (
    <div
      ref={containerRef}
      className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4"
    >
      {archives.map((archive, index) => {
        const itemKey = `${tankoubonId}:${archive.arcid}`;
        return (
          <div
            key={itemKey}
            className={archive.arcid === currentArchiveId ? 'opacity-90' : undefined}
          >
            <ArchiveCard
              archive={archive}
              index={index}
              coverHeight={coverHeights[itemKey]}
              surfaceClassName="border-none shadow-none bg-transparent"
              onCoverAspectRatioChange={(aspectRatio) => reportCoverAspectRatio(itemKey, aspectRatio)}
            />
          </div>
        );
      })}
    </div>
  );
}

export function ArchiveCollectionsCard({
  t,
  currentArchiveId,
  tankoubons,
  previewArchivesByTankoubonId,
  loading,
}: Props) {

  return (
    <Card className="border-none bg-transparent shadow-none dark:bg-transparent">
      <CardHeader className="!p-0">
        <CardTitle className="flex items-center text-base lg:text-lg">
          <FolderOpen className="w-4 h-4 mr-2" />
          {t('archive.collectionsTitle')}
        </CardTitle>
      </CardHeader>
      <CardContent className="!p-0 space-y-6">
        {loading ? (
          <div className="py-0 text-center text-muted-foreground">{t('common.loading')}</div>
        ) : (
          tankoubons.map((tank) => {
            const archives = previewArchivesByTankoubonId[tank.tankoubon_id] || [];
            const total = tank.children?.length ?? tank.archive_count ?? 0;

            return (
              <div key={tank.tankoubon_id} className="space-y-3">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="font-medium truncate">{tank.title}</div>
                    <div className="text-xs text-muted-foreground">
                      {total} {t('tankoubon.archives')}
                    </div>
                  </div>
                  <Button asChild size="sm" variant="outline">
                    <Link href={`/tankoubon?id=${tank.tankoubon_id}`}>{t('tankoubon.viewCollection')}</Link>
                  </Button>
                </div>

                <CollectionPreviewGrid
                  tankoubonId={tank.tankoubon_id}
                  archives={archives}
                  currentArchiveId={currentArchiveId}
                />
              </div>
            );
          })
        )}
      </CardContent>
    </Card>
  );
}
