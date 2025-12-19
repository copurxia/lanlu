'use client';

import { useState, useEffect, useCallback } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Heart, Trash2, RefreshCw } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { FavoriteService } from '@/lib/favorite-service';
import { groupArchivesByTime, TimeGroup } from '@/lib/time-group';
import { Archive } from '@/types/archive';
import { HomeArchiveCard } from '@/components/archive/HomeArchiveCard';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';

export default function FavoritesPage() {
  const { t } = useLanguage();
  const { success } = useToast();
  const { confirm } = useConfirmContext();
  const [loading, setLoading] = useState(true);
  const [archives, setArchives] = useState<Archive[]>([]);
  const [groupedArchives, setGroupedArchives] = useState<TimeGroup[]>([]);
  const [error, setError] = useState<string | null>(null);

  // 加载收藏列表
  const loadFavorites = useCallback(async (silent = false) => {
    try {
      if (!silent) {
        setLoading(true);
      }
      setError(null);

      // 使用新的 API 直接获取收藏档案详情
      const response = await FavoriteService.getFavoriteArchives(0, 1000);

      if (response.success === 1) {
        setArchives(response.data);
        // 按时间分组，传入翻译函数
        const grouped = groupArchivesByTime(response.data, 'last_read_time', t);
        setGroupedArchives(grouped);
      } else {
        setError(t('favorites.loadError'));
      }
    } catch (err) {
      console.error('加载收藏列表失败:', err);
      setError(t('favorites.loadError'));
    } finally {
      if (!silent) {
        setLoading(false);
      }
    }
  }, [t]);

  useEffect(() => {
    loadFavorites();
  }, [loadFavorites]);

  // 处理取消收藏
  const handleRemoveFavorite = async (arcid: string) => {
    try {
      const success = await FavoriteService.removeFavorite(arcid);
      if (success) {
        // 静默刷新列表
        await loadFavorites(true);
      }
    } catch (error) {
      console.error('取消收藏失败:', error);
    }
  };

  // 处理清空所有收藏
  const handleClearAll = async () => {
    const confirmed = await confirm({
      title: '确认清空所有收藏',
      description: t('favorites.clearAllConfirm'),
      confirmText: '清空',
      cancelText: '取消',
      variant: 'destructive',
    });

    if (!confirmed) return;

    try {
      setLoading(true);
      // 逐个取消收藏
      const promises = archives.map(archive => FavoriteService.removeFavorite(archive.arcid));
      await Promise.all(promises);

      // 刷新列表
      await loadFavorites(true);
      success('已清空所有收藏');
    } catch (error) {
      console.error('清空收藏失败:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            <Heart className="w-5 h-5" />
            {t('settings.favorites')}
          </h2>
          <p className="text-sm text-muted-foreground">{t('settings.favoritesDescription')}</p>
        </div>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => loadFavorites()}
            disabled={loading}
          >
            <RefreshCw className={`w-4 h-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
            {t('common.refresh')}
          </Button>
          {archives.length > 0 && (
            <Button
              variant="destructive"
              size="sm"
              onClick={handleClearAll}
              disabled={loading}
            >
              <Trash2 className="w-4 h-4 mr-2" />
              {t('favorites.clearAll')}
            </Button>
          )}
        </div>
      </div>

      <Card>
        <CardContent className="pt-6 space-y-4">
          {error && (
            <div className="text-red-500 mb-4">{error}</div>
          )}

          {loading ? (
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
              {Array.from({ length: 10 }).map((_, i) => (
                <div key={i} className="space-y-2">
                  <Skeleton className="aspect-[3/4] w-full" />
                  <Skeleton className="h-4 w-full" />
                  <Skeleton className="h-4 w-2/3" />
                </div>
              ))}
            </div>
          ) : groupedArchives.length === 0 ? (
            <div className="text-center py-12">
              <Heart className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
              <p className="text-lg text-muted-foreground">{t('favorites.noFavorites')}</p>
              <p className="text-sm text-muted-foreground mt-2">{t('favorites.noFavoritesHint')}</p>
            </div>
          ) : (
            <div className="space-y-8">
              <div className="mb-4 text-sm text-muted-foreground">
                {t('favorites.count').replace('{count}', String(archives.length))}
              </div>
              {groupedArchives.map((group) => (
                <div key={group.label} className="space-y-3">
                  <h3 className="text-lg font-semibold">{group.label}</h3>
                  <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
                    {group.archives.map((archive) => (
                      <HomeArchiveCard
                        key={archive.arcid}
                        archive={archive}
                        onFavoriteChange={() => handleRemoveFavorite(archive.arcid)}
                      />
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
