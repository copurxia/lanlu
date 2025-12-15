import { Archive } from '@/types/archive';
import { Card, CardContent, CardFooter } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Eye, Heart } from 'lucide-react';
import Link from 'next/link';
import { ArchiveService } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { TagI18nService } from '@/lib/tag-i18n-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { useState, useEffect, useCallback, useMemo } from 'react';

interface ArchiveCardProps {
  archive: Archive;
  tagsDisplay?: 'inline' | 'hover' | 'none';
}

// 去掉 namespace 前缀的简单显示函数
function stripNamespace(tag: string): string {
  const idx = tag.indexOf(':');
  return idx > 0 ? tag.slice(idx + 1) : tag;
}

export function ArchiveCard({ archive, tagsDisplay = 'inline' }: ArchiveCardProps) {
  const { t, language } = useLanguage();
  const [isFavorite, setIsFavorite] = useState(false);
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const [tagI18nMap, setTagI18nMap] = useState<Record<string, string>>({});

  const allTags = useMemo(() => {
    return archive.tags ? archive.tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [];
  }, [archive.tags]);

  const displayTag = useCallback((tag: string) => {
    const key = String(tag || '').trim();
    if (!key) return '';
    const translated = tagI18nMap[key];
    if (translated && String(translated).trim()) return String(translated);
    return stripNamespace(key);
  }, [tagI18nMap]);

  const displayAllTags = useMemo(() => allTags.map(displayTag), [allTags, displayTag]);
  const inlineTags = allTags.slice(0, 3);
  const hoverTags = allTags.slice(0, 8);
  const hoverTitleParts = [
    displayAllTags.length > 0 ? `${t('archive.tags')}: ${displayAllTags.join(', ')}` : '',
    archive.summary ? `${t('archive.summary')}: ${archive.summary}` : ''
  ].filter(Boolean);

  // 加载该档案的 tag i18n
  useEffect(() => {
    if (!archive.arcid || allTags.length === 0) return;
    let cancelled = false;

    (async () => {
      try {
        const map = await TagI18nService.getMap(language, archive.arcid);
        if (!cancelled) {
          setTagI18nMap(map || {});
        }
      } catch (e) {
        // 加载失败时静默处理，使用原始 tag
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [archive.arcid, language, allTags.length]);

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
    <Card
      className="group overflow-hidden hover:shadow-lg transition-shadow cursor-pointer"
      title={hoverTitleParts.length > 0 ? `${archive.title}\n${hoverTitleParts.join('\n')}` : archive.title}
      onClick={() => {
        // 点击卡片其他区域进入阅读器
        window.location.href = `/reader?id=${archive.arcid}`;
      }}
    >
      <div className="aspect-[3/4] bg-muted relative">
        <img
          src={ArchiveService.getThumbnailUrl(archive.arcid)}
          alt={archive.title}
          className="w-full h-full object-cover"
          onError={(e) => {
            // 如果图片加载失败，显示占位符
            (e.target as HTMLImageElement).style.display = 'none';
            (e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden');
          }}
        />
        <div className="hidden w-full h-full bg-muted flex items-center justify-center">
          <span className="text-muted-foreground">{t('archive.noCover')}</span>
        </div>
        {archive.isnew === 'true' && (
          <Badge className="absolute top-2 right-2 bg-red-500">
            {t('archive.new')}
          </Badge>
        )}

        {tagsDisplay === 'hover' && (allTags.length > 0 || archive.summary) && (
          <div className="pointer-events-none absolute inset-0 flex items-end bg-gradient-to-t from-black/70 via-black/30 to-transparent opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100">
            <div className="w-full p-3 space-y-2">
              {allTags.length > 0 && (
                <div className="flex flex-wrap gap-1">
                  {hoverTags.map((tag) => (
                    <span
                      key={tag}
                      className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white backdrop-blur-sm"
                    >
                      {displayTag(tag)}
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
      
      <CardContent className="p-4">
        <h3 className="font-semibold text-sm line-clamp-2 mb-2" title={archive.title}>
          {archive.title}
        </h3>
        
        {tagsDisplay === 'inline' && inlineTags.length > 0 && (
          <div className="flex flex-wrap gap-1 mb-2">
            {inlineTags.map((tag, index) => (
              <Badge key={index} variant="secondary" className="text-xs">
                {displayTag(tag)}
              </Badge>
            ))}
          </div>
        )}
        
        <div className="text-xs text-muted-foreground">
          {t('archive.pages').replace('{count}', String(archive.pagecount))}
          {archive.progress > 0 && ` • ${t('archive.progressRead').replace('{progress}', String(archive.progress)).replace('{total}', String(archive.pagecount))}`}
        </div>
      </CardContent>
      
      <CardFooter className="p-4 pt-0 flex gap-2">
        <Button
          asChild
          size="sm"
          className="flex-1"
          onClick={(e) => {
            e.stopPropagation(); // 阻止事件冒泡到卡片的点击事件
          }}
        >
          <Link href={`/archive?id=${archive.arcid}`}>
            <Eye className="w-4 h-4 mr-2" />
            {t('archive.details')}
          </Link>
        </Button>
        <Button
          size="sm"
          variant="outline"
          className={`px-3 ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
          title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
          disabled={favoriteLoading}
          onClick={handleFavoriteClick}
        >
          <Heart className={`w-4 h-4 ${isFavorite ? 'fill-current' : ''}`} />
        </Button>
      </CardFooter>
    </Card>
  );
}
