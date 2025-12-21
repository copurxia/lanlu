import { Tankoubon } from '@/types/tankoubon';
import { Card, CardContent, CardFooter } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Eye, BookOpen, Heart } from 'lucide-react';
import Link from 'next/link';
import Image from 'next/image';
import { TankoubonService } from '@/lib/tankoubon-service';
import { ArchiveService } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { TagService } from '@/lib/tag-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { useState, useEffect, useCallback, useMemo } from 'react';
import type { Archive } from '@/types/archive';

interface TankoubonCardProps {
  tankoubon: Tankoubon;
}

// 去掉 namespace 前缀的简单显示函数
function stripNamespace(tag: string): string {
  const idx = tag.indexOf(':');
  return idx > 0 ? tag.slice(idx + 1) : tag;
}

export function TankoubonCard({ tankoubon }: TankoubonCardProps) {
  const { t, language } = useLanguage();
  const [isFavorite, setIsFavorite] = useState(tankoubon.isfavorite || false);
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const [tagI18nMap, setTagI18nMap] = useState<Record<string, string>>({});
  const [firstArchive, setFirstArchive] = useState<Archive | null>(null);
  const [loadingFirstArchive, setLoadingFirstArchive] = useState(false);
  const [imageError, setImageError] = useState(false);

  const allTags = useMemo(() => {
    return tankoubon.tags ? tankoubon.tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [];
  }, [tankoubon.tags]);

  const displayTag = useCallback((tag: string) => {
    const key = String(tag || '').trim();
    if (!key) return '';
    const translated = tagI18nMap[key];
    if (translated && String(translated).trim()) return String(translated);
    return stripNamespace(key);
  }, [tagI18nMap]);

  const displayAllTags = useMemo(() => allTags.map(displayTag), [allTags, displayTag]);
  const hoverTags = allTags.slice(0, 8);
  const hoverTitleParts = [
    displayAllTags.length > 0 ? `${t('archive.tags')}: ${displayAllTags.join(', ')}` : '',
    tankoubon.summary ? `${t('archive.summary')}: ${tankoubon.summary}` : '',
    `${t('tankoubon.archiveCount')}: ${tankoubon.archive_count || 0}`
  ].filter(Boolean);

  // 加载 tag i18n（使用 tankoubon_id 查询合集相关的所有标签翻译）
  useEffect(() => {
    if (!tankoubon.tankoubon_id || allTags.length === 0) return;
    let cancelled = false;

    (async () => {
      try {
        const map = await TagService.getTranslations(language, undefined, tankoubon.tankoubon_id);
        if (!cancelled) {
          setTagI18nMap(map || {});
        }
      } catch {
        // 加载失败时静默处理，使用原始 tag
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [tankoubon.tankoubon_id, language, allTags.length]);

  // 获取第一本归档的信息（用于显示封面和跳转阅读器）
  useEffect(() => {
    if (!tankoubon.tankoubon_id) return;

    let cancelled = false;

    (async () => {
      try {
        setLoadingFirstArchive(true);

        // 优先使用传入的 archives 数据
        let archives = tankoubon.archives || [];

        // 如果没有 archives 数据，则调用 API 获取
        if (archives.length === 0) {
          const tankoubonDetail = await TankoubonService.getTankoubonById(tankoubon.tankoubon_id);
          archives = tankoubonDetail.archives || [];
        }

        if (archives.length > 0 && !cancelled) {
          try {
            // 获取第一本归档的详细信息
            const firstArchiveDetail = await ArchiveService.getArchive(archives[0]);
            if (!cancelled) {
              setFirstArchive(firstArchiveDetail);
            }
          } catch (error) {
            console.error('Failed to fetch first archive:', error);
          }
        }
      } catch (error) {
        console.error('Failed to fetch tankoubon detail:', error);
      } finally {
        if (!cancelled) {
          setLoadingFirstArchive(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [tankoubon.tankoubon_id, tankoubon.archives]);

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
            if (firstArchive) {
              window.location.href = `/reader?id=${firstArchive.arcid}`;
            }
          }}
        >
          {firstArchive && !imageError ? (
            <Image
              src={ArchiveService.getThumbnailUrl(firstArchive.arcid)}
              alt={tankoubon.name}
              fill
              className="object-cover"
              onError={() => setImageError(true)}
            />
          ) : loadingFirstArchive ? (
            <div className="w-full h-full bg-muted flex items-center justify-center">
              <span className="text-muted-foreground animate-pulse">...</span>
            </div>
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
          {(tankoubon.progress ?? 0) > 0 && ` • ${Math.round(tankoubon.progress ?? 0)}% ${t('common.read')}`}
        </div>
      </CardContent>

      <CardFooter className="p-4 pt-0 flex gap-2">
        <Button
          asChild
          size="sm"
          className="flex-1"
          onClick={() => {
            // 点击详情按钮进入合集详情页
            window.location.href = `/tankoubon?id=${tankoubon.tankoubon_id}`;
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
