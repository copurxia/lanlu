import { Tankoubon } from '@/types/tankoubon';
import { BaseMediaCard } from '@/components/ui/base-media-card';
import { Badge } from '@/components/ui/badge';
import { BookOpen } from 'lucide-react';
import { FavoriteService } from '@/lib/services/favorite-service';
import { useLanguage } from '@/contexts/LanguageContext';

interface TankoubonCardProps {
  tankoubon: Tankoubon;
  priority?: boolean;  // 优先加载图片（用于首屏 LCP 优化）
}

export function TankoubonCard({ tankoubon, priority = false }: TankoubonCardProps) {
  const { t } = useLanguage();
  const firstArchiveId = tankoubon.archives?.[0];

  const handleFavoriteToggle = async (id: string, isFavorite: boolean) => {
    return await FavoriteService.toggleTankoubonFavorite(id, isFavorite);
  };

  return (
    <BaseMediaCard
      id={tankoubon.tankoubon_id}
      title={tankoubon.name}
      thumbnailId={firstArchiveId || ''}
      tags={tankoubon.tags}
      summary={tankoubon.summary}
      pagecount={tankoubon.pagecount || 0}
      progress={tankoubon.progress}
      isnew={tankoubon.isnew}
      isfavorite={tankoubon.isfavorite}
      type="tankoubon"
      priority={priority}
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
    />
  );
}
