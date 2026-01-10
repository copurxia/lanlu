import { Archive } from '@/types/archive';
import { BaseMediaCard } from '@/components/ui/base-media-card';
import { FavoriteService } from '@/lib/services/favorite-service';

interface ArchiveCardProps {
  archive: Archive;
  index?: number;
}

export function ArchiveCard({ archive, index = 0 }: ArchiveCardProps) {
  const handleFavoriteToggle = async (id: string, isFavorite: boolean) => {
    return await FavoriteService.toggleFavorite(id, isFavorite);
  };

  return (
    <BaseMediaCard
      id={archive.arcid}
      title={archive.title}
      thumbnailId={archive.arcid}
      tags={archive.tags}
      summary={archive.summary}
      pagecount={archive.pagecount}
      progress={archive.progress}
      isnew={archive.isnew}
      isfavorite={archive.isfavorite}
      type="archive"
      index={index}
      onFavoriteToggle={handleFavoriteToggle}
    />
  );
}
