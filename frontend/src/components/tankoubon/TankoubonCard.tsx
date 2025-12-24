import { useRouter } from 'next/navigation';
import { Tankoubon } from '@/types/tankoubon';
import { Card, CardContent, CardFooter } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Eye, BookOpen, Heart } from 'lucide-react';
import Link from 'next/link';
import Image from 'next/image';
import { ArchiveService } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { useState, useCallback, useMemo } from 'react';

interface TankoubonCardProps {
  tankoubon: Tankoubon;
}

// 去掉 namespace 前缀的简单显示函数
function stripNamespace(tag: string): string {
  const idx = tag.indexOf(':');
  return idx > 0 ? tag.slice(idx + 1) : tag;
}

export function TankoubonCard({ tankoubon }: TankoubonCardProps) {
  const router = useRouter();
  const { t } = useLanguage();
  const [isFavorite, setIsFavorite] = useState(tankoubon.isfavorite || false);
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const [imageError, setImageError] = useState(false);

  // 直接从 archives 获取第一个 ID，无需额外 API 调用
  const firstArchiveId = tankoubon.archives?.[0];

  const allTags = useMemo(() => {
    return tankoubon.tags ? tankoubon.tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [];
  }, [tankoubon.tags]);

  const displayTag = useCallback((tag: string) => {
    // 现在标签已经是翻译后的，只需要去掉 namespace 前缀显示
    return stripNamespace(tag);
  }, []);

  const displayAllTags = useMemo(() => allTags.map(displayTag), [allTags, displayTag]);
  const hoverTags = allTags.slice(0, 8);
  const hoverTitleParts = [
    displayAllTags.length > 0 ? `${t('archive.tags')}: ${displayAllTags.join(', ')}` : '',
    tankoubon.summary ? `${t('archive.summary')}: ${tankoubon.summary}` : '',
    `${t('tankoubon.archiveCount')}: ${tankoubon.archive_count || 0}`
  ].filter(Boolean);

  // 处理收藏点击
  const handleFavoriteClick = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (favoriteLoading) return;

    setFavoriteLoading(true);
    try {
      const success = await FavoriteService.toggleTankoubonFavorite(tankoubon.tankoubon_id, isFavorite);
      if (success) {
        setIsFavorite(!isFavorite);
      }
    } catch (error) {
      console.error('合集收藏操作失败:', error);
    } finally {
      setFavoriteLoading(false);
    }
  };

  return (
    <Card
      className="group overflow-hidden hover:shadow-lg transition-shadow"
      title={hoverTitleParts.length > 0 ? `${tankoubon.name}\n${hoverTitleParts.join('\n')}` : tankoubon.name}
    >
      <div className="aspect-[3/4] bg-muted relative">
        <div
          className="relative w-full h-full"
          onClick={(e) => {
            e.stopPropagation(); // 阻止事件冒泡到卡片的点击事件
            // 点击封面进入第一本归档的阅读器
            if (firstArchiveId) {
              router.push(`/reader?id=${firstArchiveId}`);
            }
          }}
        >
          {firstArchiveId && !imageError ? (
            <Image
              src={ArchiveService.getThumbnailUrl(firstArchiveId)}
              alt={tankoubon.name}
              fill
              className="object-cover"
              onError={() => setImageError(true)}
            />
          ) : (
            <div className="w-full h-full bg-muted flex items-center justify-center">
              <span className="text-muted-foreground">{t('archive.noCover')}</span>
            </div>
          )}
        </div>

        {/* Tankoubon badge */}
        <Badge className="absolute top-2 left-2 bg-primary">
          <BookOpen className="w-3 h-3 mr-1" />
          {t('tankoubon.collection')}
        </Badge>

        {(tankoubon.isnew ?? false) && (
          <Badge className="absolute top-2 right-2 bg-red-500">
            {t('archive.new')}
          </Badge>
        )}

        {/* Archive count badge */}
        <Badge className="absolute bottom-2 right-2 bg-black/70 text-white">
          {tankoubon.archive_count || 0} {t('tankoubon.archives')}
        </Badge>

        {(allTags.length > 0 || tankoubon.summary) && (
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
              {tankoubon.summary && (
                <div className="text-[11px] leading-snug text-white/90 line-clamp-3">
                  {tankoubon.summary}
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      <CardContent className="p-4">
        <div className="h-10 mb-2"> {/* 固定高度容纳两行标题 */}
          <h3 className="font-semibold text-sm line-clamp-2" title={tankoubon.name}>
            {tankoubon.name}
          </h3>
        </div>

        <div className="text-xs text-muted-foreground">
          {t('tankoubon.totalPages').replace('{count}', String(tankoubon.pagecount || 0))}
          {(tankoubon.progress ?? 0) > 0 && ` • ${Math.round(((tankoubon.progress ?? 0) / (tankoubon.pagecount || 1)) * 100)}% ${t('common.read')}`}
        </div>
      </CardContent>

      <CardFooter className="p-4 pt-0 flex gap-2">
        <Button
          asChild
          size="sm"
          className="flex-1"
          onClick={() => {
            // 点击详情按钮进入合集详情页
            router.push(`/tankoubon?id=${tankoubon.tankoubon_id}`);
          }}
        >
          <Link href={`/tankoubon?id=${tankoubon.tankoubon_id}`}>
            <Eye className="w-4 h-4 mr-2" />
            {t('common.details')}
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
