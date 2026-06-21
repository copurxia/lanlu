'use client';

import { Info } from 'lucide-react';
import { DetailSectionCard } from '@/components/detail/DetailSectionCard';
import { DetailInfoList } from '@/components/detail/DetailInfoList';
import type { ArchiveMetadata } from '@/types/archive';
import { formatDate, formatFileSize } from '@/lib/utils/utils';
import { isTvArchiveMetadata } from '@/lib/utils/tv-media';

type Props = {
  metadata: ArchiveMetadata;
  t: (key: string) => string;
};

export function ArchiveBasicInfoCard({ metadata, t }: Props) {
  const isTvArchive = isTvArchiveMetadata(metadata);

  const fileName = [metadata.relative_path, metadata.filename].filter(Boolean).join('/') || t('archive.unknown');
  const lastRead = metadata.last_read_time
    ? new Date(metadata.last_read_time).toLocaleDateString()
    : metadata.lastreadtime
      ? new Date(metadata.lastreadtime * 1000).toLocaleDateString()
      : t('archive.neverRead');

  const items = [
    { label: t('archive.fileName'), value: fileName, title: fileName },
    {
      label: isTvArchive ? t('archive.episodeCount') : t('archive.pageCount'),
      value: metadata.pagecount ?? 0,
    },
    {
      label: t('archive.progress'),
      value: `${metadata.progress ?? 0}/${metadata.pagecount ?? 0}`,
    },
    {
      label: t('archive.releaseAt'),
      value: formatDate(metadata.release_at || '', t('archive.unknown')),
    },
    { label: t('archive.lastRead'), value: lastRead },
    {
      label: t('archive.status'),
      value: metadata.isnew ? t('archive.statusNew') : t('archive.statusRead'),
    },
    {
      label: t('archive.fileSize'),
      value: formatFileSize(metadata.file_size || 0),
    },
    {
      label: t('archive.fileType'),
      value: metadata.archivetype ? metadata.archivetype.toUpperCase() : t('archive.unknown'),
    },
    {
      label: t('archive.createdAt'),
      value: formatDate(metadata.created_at || '', t('archive.unknown')),
    },
    {
      label: t('archive.updatedAt'),
      value: formatDate(metadata.updated_at || '', t('archive.unknown')),
    },
  ];

  return (
    <DetailSectionCard
      title={
        <span className="flex items-center gap-2">
          <Info className="w-4 h-4" />
          {t('archive.basicInfo')}
        </span>
      }
      variant="glass"
    >
      <DetailInfoList items={items} />
    </DetailSectionCard>
  );
}
