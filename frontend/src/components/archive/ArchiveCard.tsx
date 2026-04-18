import { Archive } from '@/types/archive';
import { BaseMediaCard } from '@/components/ui/base-media-card';
import { FavoriteService } from '@/lib/services/favorite-service';
import { getArchiveAssetId } from '@/lib/utils/archive-assets';
import type { RecommendationItemType, RecommendationScene } from '@/types/recommendation';
import type { MenuItem } from '@/components/ui/unified-menu';

interface ArchiveCardProps {
  archive: Archive;
  index?: number;
  priority?: boolean;  // 优先加载图片（用于首屏 LCP 优化）
  disableContentVisibility?: boolean;
  coverHeight?: number;
  surfaceClassName?: string;
  selectable?: boolean;
  selectionMode?: boolean;
  selected?: boolean;
  onToggleSelect?: (selected: boolean) => void;
  onRequestEnterSelection?: () => void;
  extraMenuItems?: MenuItem[];
  onCoverAspectRatioChange?: (aspectRatio: number) => void;
  recommendationContext?: {
    scene: RecommendationScene;
    seedEntityType?: RecommendationItemType;
    seedEntityId?: string;
  };
  onRecommendationOpenReader?: (itemType: RecommendationItemType, itemId: string) => void;
  onRecommendationOpenDetails?: (itemType: RecommendationItemType, itemId: string) => void;
  onRecommendationFavorite?: (itemType: RecommendationItemType, itemId: string) => void;
}

export function ArchiveCard({
  archive,
  index = 0,
  priority = false,
  disableContentVisibility = false,
  coverHeight,
  surfaceClassName,
  selectable = false,
  selectionMode = false,
  selected = false,
  onToggleSelect,
  onRequestEnterSelection,
  extraMenuItems,
  onCoverAspectRatioChange,
  recommendationContext,
  onRecommendationOpenReader,
  onRecommendationOpenDetails,
  onRecommendationFavorite,
}: ArchiveCardProps) {
  const coverAssetId = getArchiveAssetId(archive, 'cover');

  const handleFavoriteToggle = async (id: string, isFavorite: boolean) => {
    return await FavoriteService.setFavorite('archive', id, !isFavorite);
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
      surfaceClassName={surfaceClassName}
      onFavoriteToggle={handleFavoriteToggle}
      selectable={selectable}
      selectionMode={selectionMode}
      selected={selected}
      onToggleSelect={onToggleSelect}
      onRequestEnterSelection={onRequestEnterSelection}
      extraMenuItems={extraMenuItems}
      onCoverAspectRatioChange={onCoverAspectRatioChange}
      recommendationContext={recommendationContext}
      onRecommendationOpenReader={onRecommendationOpenReader}
      onRecommendationOpenDetails={onRecommendationOpenDetails}
      onRecommendationFavorite={onRecommendationFavorite}
    />
  );
}
