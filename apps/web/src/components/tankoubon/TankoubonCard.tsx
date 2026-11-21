import { Tankoubon } from '@/types/tankoubon';
import { BaseMediaCard } from '@/components/ui/base-media-card';
import { Badge } from '@/components/ui/badge';
import { BookOpen } from 'lucide-react';
import { FavoriteService } from '@/lib/services/favorite-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { getCoverAssetId } from '@/lib/utils/archive-assets';
import type { RecommendationItemType, RecommendationScene } from '@/types/recommendation';

interface TankoubonCardProps {
  tankoubon: Tankoubon;
  priority?: boolean;  // 优先加载图片（用于首屏 LCP 优化）
  disableContentVisibility?: boolean;
  coverHeight?: number;
  surfaceClassName?: string;
  selectable?: boolean;
  selectionMode?: boolean;
  selected?: boolean;
  onToggleSelect?: (selected: boolean) => void;
  onRequestEnterSelection?: () => void;
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

export function TankoubonCard({
  tankoubon,
  priority = false,
  disableContentVisibility = false,
  coverHeight,
  surfaceClassName,
  selectable = false,
  selectionMode = false,
  selected = false,
  onToggleSelect,
  onRequestEnterSelection,
  onCoverAspectRatioChange,
  recommendationContext,
  onRecommendationOpenReader,
  onRecommendationOpenDetails,
  onRecommendationFavorite,
}: TankoubonCardProps) {
  const { t } = useLanguage();
  const firstArchiveId = tankoubon.children?.[0];
  const coverAssetId = getCoverAssetId(tankoubon) ?? 0;

  const handleFavoriteToggle = async (id: string, isFavorite: boolean) => {
    return await FavoriteService.setFavorite('tankoubon', id, !isFavorite);
  };

  return (
    <BaseMediaCard
      id={tankoubon.tankoubon_id}
      title={tankoubon.title}
      thumbnailId={firstArchiveId || ''}
      thumbnailAssetId={coverAssetId}
      tags={tankoubon.tags}
      summary={tankoubon.description}
      pagecount={tankoubon.pagecount || 0}
      progress={tankoubon.progress}
      isnew={tankoubon.isnew}
      isfavorite={tankoubon.isfavorite}
      type="tankoubon"
      priority={priority}
      disableContentVisibility={disableContentVisibility}
      coverHeight={coverHeight}
      surfaceClassName={surfaceClassName}
      detailsLabel={t('common.details')}
      pagesLabel={t('tankoubon.totalPages').replace('{count}', String(tankoubon.pagecount || 0))}
      badge={
        <Badge className="bg-primary">
          <BookOpen className="w-3 h-3 mr-1" />
          {t('tankoubon.collection')}
        </Badge>
      }
      extraBadge={
        <Badge className="bg-black/70 text-white">
          {tankoubon.archive_count || 0} {t('tankoubon.archives')}
        </Badge>
      }
      onFavoriteToggle={handleFavoriteToggle}
      selectable={selectable}
      selectionMode={selectionMode}
      selected={selected}
      onToggleSelect={onToggleSelect}
      onRequestEnterSelection={onRequestEnterSelection}
      onCoverAspectRatioChange={onCoverAspectRatioChange}
      recommendationContext={recommendationContext}
      onRecommendationOpenReader={onRecommendationOpenReader}
      onRecommendationOpenDetails={onRecommendationOpenDetails}
      onRecommendationFavorite={onRecommendationFavorite}
    />
  );
}
