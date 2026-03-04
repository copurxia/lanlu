'use client';

import Link from 'next/link';
import { FolderOpen } from 'lucide-react';
import type { Tankoubon } from '@/types/tankoubon';
import type { Archive } from '@/types/archive';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ArchiveCard } from '@/components/archive/ArchiveCard';

type Props = {
  t: (key: string) => string;
  currentArchiveId: string;
  tankoubons: Tankoubon[];
  previewArchivesByTankoubonId: Record<string, Archive[]>;
  loading: boolean;
};

export function ArchiveCollectionsCard({
  t,
  currentArchiveId,
  tankoubons,
  previewArchivesByTankoubonId,
  loading,
}: Props) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center text-base lg:text-lg">
          <FolderOpen className="w-4 h-4 mr-2" />
          {t('archive.collectionsTitle')}
        </CardTitle>
      </CardHeader>
      <CardContent className="pt-0 space-y-6">
        {loading ? (
          <div className="py-8 text-center text-muted-foreground">{t('common.loading')}</div>
        ) : (
          tankoubons.map((tank) => {
            const archives = previewArchivesByTankoubonId[tank.tankoubon_id] || [];
            const total = tank.archives?.length ?? tank.archive_count ?? 0;

            return (
              <div key={tank.tankoubon_id} className="space-y-3">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="font-medium truncate">{tank.name}</div>
                    <div className="text-xs text-muted-foreground">
                      {total} {t('tankoubon.archives')}
                    </div>
                  </div>
                  <Button asChild size="sm" variant="outline">
                    <Link href={`/tankoubon?id=${tank.tankoubon_id}`}>{t('tankoubon.viewCollection')}</Link>
                  </Button>
                </div>

                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
                  {archives.map((a, index) => (
                    <div
                      key={`${tank.tankoubon_id}:${a.arcid}`}
                      className={a.arcid === currentArchiveId ? 'opacity-90' : undefined}
                    >
                      <ArchiveCard archive={a} index={index} />
                    </div>
                  ))}
                </div>
              </div>
            );
          })
        )}
      </CardContent>
    </Card>
  );
}
