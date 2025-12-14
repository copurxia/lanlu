import { Archive } from '@/types/archive';
import { Button } from '@/components/ui/button';
import { Eye, Heart } from 'lucide-react';
import Link from 'next/link';
import { ArchiveService } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { useState, useEffect } from 'react';

interface HomeArchiveCardProps {
  archive: Archive;
}

export function HomeArchiveCard({ archive }: HomeArchiveCardProps) {
  const { t } = useLanguage();
  const [isFavorite, setIsFavorite] = useState(false);
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const allTags = archive.tags ? archive.tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [];
  const hoverTags = allTags.slice(0, 8);
  const hoverTitleParts = [
    allTags.length > 0 ? `${t('archive.tags')}: ${allTags.join(', ')}` : '',
    archive.summary ? `${t('archive.summary')}: ${archive.summary}` : ''
  ].filter(Boolean);

  // 检查收藏状态
  useEffect(() => {
    const checkFavoriteStatus = async () => {
      try {
        const favorite = await FavoriteService.isFavorite(archive.arcid);
        setIsFavorite(favorite);
      } catch (error) {
        console.error('检查收藏状态失败:', error);
      }
    };

    checkFavoriteStatus();
  }, [archive.arcid]);
  
  // 处理收藏点击
  const handleFavoriteClick = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (favoriteLoading) return;
    
    setFavoriteLoading(true);
    try {
      const success = await FavoriteService.toggleFavorite(archive.arcid);
      if (success) {
        setIsFavorite(!isFavorite);
      }
    } catch (error) {
      console.error('收藏操作失败:', error);
    } finally {
      setFavoriteLoading(false);
    }
  };
  
  return (
    <div className="flex-shrink-0 w-40">
      {/* 单个档案卡片 */}
      <div 
        className="group bg-card rounded-lg border shadow-sm overflow-hidden hover:shadow-md transition-shadow cursor-pointer"
        title={hoverTitleParts.length > 0 ? `${archive.title}\n${hoverTitleParts.join('\n')}` : archive.title}
        onClick={() => {
          window.location.href = `/reader?id=${archive.arcid}`;
        }}
      >
        <div className="aspect-[3/4] bg-muted relative">
          <img
            src={ArchiveService.getThumbnailUrl(archive.arcid)}
            alt={archive.title}
            className="w-full h-full object-cover"
            onError={(e) => {
              const target = e.target as HTMLImageElement;
              // 隐藏失败的图片，显示占位符
              target.style.display = 'none';
              const placeholder = target.nextElementSibling as HTMLElement;
              if (placeholder) {
                placeholder.classList.remove('hidden');
              }
            }}
          />
          {/* 无封面时显示的占位符 - 默认隐藏 */}
          <div className="hidden absolute inset-0 flex items-center justify-center bg-muted">
            <div className="text-center text-muted-foreground">
              <div className="text-2xl mb-2">📚</div>
              <div className="text-xs">{t('archive.noCover')}</div>
            </div>
          </div>

          {(allTags.length > 0 || archive.summary) && (
            <div className="pointer-events-none absolute inset-0 flex items-end bg-gradient-to-t from-black/70 via-black/30 to-transparent opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100">
              <div className="w-full p-2 space-y-2">
                {allTags.length > 0 && (
                  <div className="flex flex-wrap gap-1">
                    {hoverTags.map((tag) => (
                      <span
                        key={tag}
                        className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white backdrop-blur-sm"
                      >
                        {tag}
                      </span>
                    ))}
                    {allTags.length > hoverTags.length && (
                      <span className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white backdrop-blur-sm">
                        +{allTags.length - hoverTags.length}
                      </span>
                    )}
                  </div>
                )}
                {archive.summary && (
                  <div className="text-[11px] leading-snug text-white/90 line-clamp-3">
                    {archive.summary}
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
        <div className="p-3">
          <h3 className="font-medium text-sm line-clamp-2 mb-2 min-h-[2.5rem]">
            {archive.title}
          </h3>
          <div className="text-xs text-muted-foreground mb-3">
            {archive.pagecount} {t('home.pages')}
          </div>
          <div className="flex gap-1">
            <Button 
              asChild 
              size="sm" 
              className="flex-1 text-xs h-7"
              onClick={(e) => {
                e.stopPropagation();
              }}
            >
              <Link href={`/archive?id=${archive.arcid}`}>
                {t('common.details')}
              </Link>
            </Button>
            <Button 
              size="sm" 
              variant="outline" 
              className={`px-2 h-7 ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
              title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
              disabled={favoriteLoading}
              onClick={handleFavoriteClick}
            >
              <Heart className={`w-4 h-4 ${isFavorite ? 'fill-current' : ''}`} />
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
