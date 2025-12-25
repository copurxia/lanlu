import { useRouter } from 'next/navigation';
import { Archive } from '@/types/archive';
import { Card, CardContent, CardFooter } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Eye, Heart } from 'lucide-react';
import Link from 'next/link';
import Image from 'next/image';
import { ArchiveService } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { useState, useCallback, useMemo } from 'react';

interface ArchiveCardProps {
  archive: Archive;
  index?: number;
}

// 去掉 namespace 前缀的简单显示函数
function stripNamespace(tag: string): string {
  const idx = tag.indexOf(':');
  return idx > 0 ? tag.slice(idx + 1) : tag;
}

export function ArchiveCard({ archive, index = 0 }: ArchiveCardProps) {
  const router = useRouter();
  const { t } = useLanguage();
  const [isFavorite, setIsFavorite] = useState(archive.isfavorite || false);
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const [imageError, setImageError] = useState(false);

  const allTags = useMemo(() => {
    return archive.tags ? archive.tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [];
  }, [archive.tags]);

  const displayTag = useCallback((tag: string) => {
    // 现在标签已经是翻译后的，只需要去掉 namespace 前缀显示
    return stripNamespace(tag);
  }, []);

  const displayAllTags = useMemo(() => allTags.map(displayTag), [allTags, displayTag]);
  // 过滤掉 source 相关的标签（包含 namespace 前缀和已翻译的标签）
  const hoverTags = useMemo(() => {
    return allTags
      .filter(tag => {
        const strippedTag = stripNamespace(tag).toLowerCase();
        return !strippedTag.includes('source');
      })
      .slice(0, 8);
  }, [allTags]);
  const hoverTitleParts = [
    displayAllTags.length > 0 ? `${t('archive.tags')}: ${displayAllTags.join(', ')}` : '',
    archive.summary ? `${t('archive.summary')}: ${archive.summary}` : ''
  ].filter(Boolean);

  // 处理收藏点击
  const handleFavoriteClick = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (favoriteLoading) return;

    setFavoriteLoading(true);
    try {
      const success = await FavoriteService.toggleFavorite(archive.arcid, isFavorite);
      if (success) {
        setIsFavorite(!isFavorite);
      }
    } catch (error) {
      console.error('收藏操作失败:', error);
    } finally {
      setFavoriteLoading(false);
    }
  };
  
  // 计算交错动画延迟，最大延迟 500ms
  const animationDelay = Math.min(index * 50, 500);

  return (
    <Card
      className="group overflow-hidden cursor-pointer transition-shadow hover:shadow-lg motion-safe:animate-archive-card-in motion-reduce:animate-none will-change-transform"
      style={{ animationDelay: `${animationDelay}ms` }}
      title={hoverTitleParts.length > 0 ? `${archive.title}\n${hoverTitleParts.join('\n')}` : archive.title}
      onClick={() => {
        // 点击卡片其他区域进入阅读器
        router.push(`/reader?id=${archive.arcid}`);
      }}
    >
      <div className="aspect-[3/4] bg-muted relative">
        {!imageError ? (
          <Image
            src={ArchiveService.getThumbnailUrl(archive.arcid)}
            alt={archive.title}
            fill
            className="object-cover"
            onError={() => setImageError(true)}
          />
        ) : (
          <div className="absolute inset-0 flex items-center justify-center">
            <span className="text-muted-foreground">{t('archive.noCover')}</span>
          </div>
        )}
        {archive.isnew && (
          <Badge className="absolute top-2 right-2 bg-red-500">
            {t('archive.new')}
          </Badge>
        )}

        {(allTags.length > 0 || archive.summary) && (
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
        <div className="h-10 mb-2"> {/* 固定高度容纳两行标题 */}
          <h3 className="font-semibold text-sm line-clamp-2" title={archive.title}>
            {archive.title}
          </h3>
        </div>

        <div className="text-xs text-muted-foreground">
          {t('archive.pages').replace('{count}', String(archive.pagecount))}
          {archive.progress > 0 && ` • ${Math.round((archive.progress / archive.pagecount) * 100)}% ${t('common.read')}`}
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
