'use client';

import { Info } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import type { ArchiveMetadata } from '@/types/archive';
import { formatDate, formatFileSize } from '@/lib/utils/utils';

type Props = {
  metadata: ArchiveMetadata;
  t: (key: string) => string;
};

export function ArchiveBasicInfoCard({ metadata, t }: Props) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center text-base lg:text-lg">
          <Info className="w-4 h-4 mr-2" />
          {t('archive.basicInfo')}
        </CardTitle>
      </CardHeader>
      <CardContent className="pt-0">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
          <div className="sm:col-span-2 flex items-start justify-between gap-3">
            <span className="text-muted-foreground whitespace-nowrap shrink-0">{t('archive.fileName')}</span>
            <span
              className="flex-1 text-right whitespace-normal break-all"
              title={metadata.relative_path + '/' + metadata.filename}
            >
              {metadata.relative_path}/{metadata.filename}
            </span>
          </div>

          <div className="flex items-start justify-between gap-3">
            <span className="text-muted-foreground whitespace-nowrap shrink-0">{t('archive.pageCount')}</span>
            <span className="flex-1 text-right whitespace-normal break-words">{metadata.pagecount}</span>
          </div>
          <div className="flex items-start justify-between gap-3">
            <span className="text-muted-foreground whitespace-nowrap shrink-0">{t('archive.progress')}</span>
            <span className="flex-1 text-right whitespace-normal break-words">
              {metadata.progress}/{metadata.pagecount}
            </span>
          </div>

          <div className="flex items-start justify-between gap-3">
            <span className="text-muted-foreground whitespace-nowrap shrink-0">{t('archive.lastRead')}</span>
            <span className="flex-1 text-right whitespace-normal break-words">
              {metadata.lastreadtime ? new Date(metadata.lastreadtime * 1000).toLocaleDateString() : t('archive.neverRead')}
            </span>
          </div>
          <div className="flex items-start justify-between gap-3">
            <span className="text-muted-foreground whitespace-nowrap shrink-0">{t('archive.status')}</span>
            <span className="flex-1 text-right whitespace-normal break-words">
              {metadata.isnew ? t('archive.statusNew') : t('archive.statusRead')}
            </span>
          </div>

          <div className="flex items-start justify-between gap-3">
            <span className="text-muted-foreground whitespace-nowrap shrink-0">{t('archive.fileSize')}</span>
            <span className="flex-1 text-right whitespace-normal break-words">{formatFileSize(metadata.file_size)}</span>
          </div>
          <div className="flex items-start justify-between gap-3">
            <span className="text-muted-foreground whitespace-nowrap shrink-0">{t('archive.fileType')}</span>
            <span className="flex-1 text-right whitespace-normal break-words">{metadata.archivetype.toUpperCase()}</span>
          </div>

          <div className="flex items-start justify-between gap-3">
            <span className="text-muted-foreground whitespace-nowrap shrink-0">{t('archive.createdAt')}</span>
            <span className="flex-1 text-right whitespace-normal break-words">{formatDate(metadata.created_at, t('archive.unknown'))}</span>
          </div>
          <div className="flex items-start justify-between gap-3">
            <span className="text-muted-foreground whitespace-nowrap shrink-0">{t('archive.updatedAt')}</span>
            <span className="flex-1 text-right whitespace-normal break-words">{formatDate(metadata.updated_at, t('archive.unknown'))}</span>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
