import { Archive } from '@/types/archive';
import { BaseMediaCard } from '@/components/ui/base-media-card';
import { FavoriteService } from '@/lib/services/favorite-service';
import { getArchiveAssetId } from '@/lib/utils/archive-assets';

interface ArchiveCardProps {
  archive: Archive;
  index?: number;
  priority?: boolean;  // 优先加载图片（用于首屏 LCP 优化）
  disableContentVisibility?: boolean;
  coverHeight?: number;
  selectable?: boolean;
  selectionMode?: boolean;
  selected?: boolean;
  onToggleSelect?: (selected: boolean) => void;
  onRequestEnterSelection?: () => void;
  onCoverAspectRatioChange?: (aspectRatio: number) => void;
}

export function ArchiveCard({
  archive,
  index = 0,
  priority = false,
  disableContentVisibility = false,
  coverHeight,
  selectable = false,
  selectionMode = false,
  selected = false,
  onToggleSelect,
  onRequestEnterSelection,
  onCoverAspectRatioChange,
}: ArchiveCardProps) {
  const coverAssetId = getArchiveAssetId(archive, 'cover');

  const handleFavoriteToggle = async (id: string, isFavorite: boolean) => {
    return await FavoriteService.toggleFavorite(id, isFavorite);
  };

  return (
    <BaseMediaCard
      id={archive.arcid}
      title={archive.title}
      thumbnailId={archive.arcid}
      thumbnailAssetId={coverAssetId}
      tags={archive.tags}
      summary={archive.description}
      pagecount={archive.pagecount}
      progress={archive.progress}
      isnew={archive.isnew}
      isfavorite={archive.isfavorite}
      type="archive"
      index={index}
      priority={priority}
      disableContentVisibility={disableContentVisibility}
      coverHeight={coverHeight}
      onFavoriteToggle={handleFavoriteToggle}
      selectable={selectable}
      selectionMode={selectionMode}
      selected={selected}
      onToggleSelect={onToggleSelect}
      onRequestEnterSelection={onRequestEnterSelection}
      onCoverAspectRatioChange={onCoverAspectRatioChange}
    />
  );
}
