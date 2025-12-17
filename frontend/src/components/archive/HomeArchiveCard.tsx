import { Archive } from '@/types/archive';
import { Card, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Heart } from 'lucide-react';
import Link from 'next/link';
import Image from 'next/image';
import { ArchiveService } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { TagService } from '@/lib/tag-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { useState, useEffect, useCallback, useMemo } from 'react';

interface HomeArchiveCardProps {
  archive: Archive;
  onFavoriteChange?: () => void;
}

// 去掉 namespace 前缀的简单显示函数
function stripNamespace(tag: string): string {
  const idx = tag.indexOf(':');
  return idx > 0 ? tag.slice(idx + 1) : tag;
}

export function HomeArchiveCard({ archive, onFavoriteChange }: HomeArchiveCardProps) {
  const { t, language } = useLanguage();
  const [isFavorite, setIsFavorite] = useState(archive.isfavorite || false);
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
        const map = await TagService.getTranslations(language, archive.arcid);
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
  }, [archive.arcid, language, allTags.length]);

  // 处理收藏点击
  const handleFavoriteClick = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (favoriteLoading) return;

    setFavoriteLoading(true);
    try {
      const success = await FavoriteService.toggleFavorite(archive.arcid, isFavorite);
      if (success) {
        setIsFavorite(!isFavorite);
        // 如果提供了回调函数，则调用它
        if (onFavoriteChange) {
          onFavoriteChange();
        }
      }
    } catch (error) {
      console.error('收藏操作失败:', error);
    } finally {
      setFavoriteLoading(false);
    }
  };

  return (
    <Card
      className="group overflow-hidden hover:shadow-lg transition-shadow cursor-pointer w-[180px] flex-shrink-0"
      title={hoverTitleParts.length > 0 ? `${archive.title}\n${hoverTitleParts.join('\n')}` : archive.title}
      onClick={() => {
        window.location.href = `/reader?id=${archive.arcid}`;
      }}
    >
        <div className="aspect-[3/4] bg-muted relative">
          <div className="relative w-full h-full">
            <Image
              src={ArchiveService.getThumbnailUrl(archive.arcid)}
              alt={archive.title}
              fill
              className="object-cover"
              onError={() => {
                const imgElement = document.querySelector(`img[alt="${archive.title}"]`) as HTMLElement;
                if (imgElement) {
                  imgElement.style.display = 'none';
                  const placeholder = imgElement.closest('.relative')?.nextElementSibling;
                  if (placeholder) {
                    placeholder.classList.remove('hidden');
                  }
                }
              }}
            />
          </div>
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
          <h3 className="font-semibold text-sm line-clamp-2 mb-2">
            {archive.title}
          </h3>
          <div className="text-xs text-muted-foreground">
            {archive.pagecount} {t('home.pages')}
          </div>
        </CardContent>

        <CardFooter className="p-4 pt-0 flex gap-2">
          <Button
            asChild
            size="sm"
            className="flex-1"
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
