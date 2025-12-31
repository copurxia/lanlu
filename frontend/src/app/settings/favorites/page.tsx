'use client';

import { useState, useEffect, useCallback } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { logger } from '@/lib/logger';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Heart, Trash2, RefreshCw } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { FavoriteService } from '@/lib/favorite-service';
import { ArchiveService } from '@/lib/archive-service';
import { TankoubonService } from '@/lib/tankoubon-service';
import { groupArchivesByTime, TimeGroup } from '@/lib/time-group';
import { Archive } from '@/types/archive';
import { ArchiveCard } from '@/components/archive/ArchiveCard';
import type { Tankoubon } from '@/types/tankoubon';
import { TankoubonCard } from '@/components/tankoubon/TankoubonCard';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

export default function FavoritesPage() {
  const { t } = useLanguage();
  const { success } = useToast();
  const { confirm } = useConfirmContext();
  const [activeTab, setActiveTab] = useState<'archives' | 'tankoubons'>('archives');
  const [archiveLoading, setArchiveLoading] = useState(true);
  const [tankoubonLoading, setTankoubonLoading] = useState(true);
  const [archives, setArchives] = useState<Archive[]>([]);
  const [groupedArchives, setGroupedArchives] = useState<TimeGroup[]>([]);
  const [tankoubons, setTankoubons] = useState<Tankoubon[]>([]);
  const [groupedTankoubons, setGroupedTankoubons] = useState<TimeGroup[]>([]);
  const [archiveError, setArchiveError] = useState<string | null>(null);
  const [tankoubonError, setTankoubonError] = useState<string | null>(null);

  const loadArchiveFavorites = useCallback(async (silent = false) => {
    try {
      if (!silent) {
        setArchiveLoading(true);
      }
      setArchiveError(null);

      // 使用搜索接口获取收藏档案
      const response = await ArchiveService.search({
        favoriteonly: true,
        groupby_tanks: false,
        sortby: 'date_added',
        order: 'desc',
        start: 0,
        count: 1000
      });

      const archiveData = response.data as Archive[];
      setArchives(archiveData);
      // 按收藏时间分组，传入翻译函数
      const grouped = groupArchivesByTime(archiveData, 'favoritetime', t);
      setGroupedArchives(grouped);
    } catch (err) {
      logger.apiError('加载收藏列表失败:', err);
      setArchiveError(t('favorites.loadError'));
    } finally {
      if (!silent) {
        setArchiveLoading(false);
      }
    }
  }, [t]);

  const loadTankoubonFavorites = useCallback(async (silent = false) => {
    try {
      if (!silent) {
        setTankoubonLoading(true);
      }
      setTankoubonError(null);

      // 直接通过搜索接口获取收藏的合集数据（包含 archives）
      const response = await TankoubonService.getFavoriteTankoubons({
        start: 0,
        count: 1000
      });

      const tankoubonData = response.data;
      setTankoubons(tankoubonData);
      // 合集也使用收藏时间分组
      const grouped = groupArchivesByTime(tankoubonData, 'favoritetime', t);
      setGroupedTankoubons(grouped);
    } catch (err) {
      logger.apiError('加载收藏合集失败:', err);
      setTankoubonError(t('favorites.loadError'));
    } finally {
      if (!silent) {
        setTankoubonLoading(false);
      }
    }
  }, [t]);

  useEffect(() => {
    loadArchiveFavorites();
    loadTankoubonFavorites();
  }, [loadArchiveFavorites, loadTankoubonFavorites]);


  // 处理清空所有收藏
  const handleClearAll = async () => {
    const isArchives = activeTab === 'archives';
    const count = isArchives ? archives.length : tankoubons.length;
    if (count === 0) return;

    const confirmed = await confirm({
      title: '确认清空所有收藏',
      description: t('favorites.clearAllConfirm'),
      confirmText: '清空',
      cancelText: '取消',
      variant: 'destructive',
    });

    if (!confirmed) return;

    try {
      if (isArchives) {
        setArchiveLoading(true);
        const promises = archives.map((archive) => FavoriteService.removeFavorite(archive.arcid));
        await Promise.all(promises);
        await loadArchiveFavorites(true);
      } else {
        setTankoubonLoading(true);
        const promises = tankoubons.map((tank) => FavoriteService.removeTankoubonFavorite(tank.tankoubon_id));
        await Promise.all(promises);
        await loadTankoubonFavorites(true);
      }
      success('已清空所有收藏');
    } catch (error) {
      logger.apiError('清空收藏失败:', error);
    } finally {
      if (isArchives) {
        setArchiveLoading(false);
      } else {
        setTankoubonLoading(false);
      }
    }
  };

  const handleRefresh = async () => {
    if (activeTab === 'archives') {
      await loadArchiveFavorites();
    } else {
      await loadTankoubonFavorites();
    }
  };

  const isLoading = activeTab === 'archives' ? archiveLoading : tankoubonLoading;
  const activeError = activeTab === 'archives' ? archiveError : tankoubonError;
  const activeCount = activeTab === 'archives' ? archives.length : tankoubons.length;

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
            onClick={handleRefresh}
            disabled={isLoading}
          >
            <RefreshCw className={`w-4 h-4 mr-2 ${isLoading ? 'animate-spin' : ''}`} />
            {t('common.refresh')}
          </Button>
          {activeCount > 0 && (
            <Button
              variant="destructive"
              size="sm"
              onClick={handleClearAll}
              disabled={isLoading}
            >
              <Trash2 className="w-4 h-4 mr-2" />
              {t('favorites.clearAll')}
            </Button>
          )}
        </div>
      </div>

      <Card>
        <CardContent className="pt-6 space-y-4">
          {activeError && <div className="text-red-500 mb-4">{activeError}</div>}

          <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as any)}>
            <TabsList className="grid w-full grid-cols-2 mb-6">
              <TabsTrigger value="archives">{t('favorites.tabs.archives')}</TabsTrigger>
              <TabsTrigger value="tankoubons">{t('favorites.tabs.tankoubons')}</TabsTrigger>
            </TabsList>

            <TabsContent value="archives">
              {archiveLoading ? (
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
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
                      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
                        {group.archives.map((archive, index) => (
                          <ArchiveCard key={archive.arcid} archive={archive} index={index} />
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </TabsContent>

            <TabsContent value="tankoubons">
              {tankoubonLoading ? (
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
                  {Array.from({ length: 10 }).map((_, i) => (
                    <div key={i} className="space-y-2">
                      <Skeleton className="aspect-[3/4] w-full" />
                      <Skeleton className="h-4 w-full" />
                      <Skeleton className="h-4 w-2/3" />
                    </div>
                  ))}
                </div>
              ) : groupedTankoubons.length === 0 ? (
                <div className="text-center py-12">
                  <Heart className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
                  <p className="text-lg text-muted-foreground">{t('favorites.noFavorites')}</p>
                  <p className="text-sm text-muted-foreground mt-2">{t('favorites.noFavoritesHint')}</p>
                </div>
              ) : (
                <div className="space-y-8">
                  <div className="mb-4 text-sm text-muted-foreground">
                    {t('favorites.count').replace('{count}', String(tankoubons.length))}
                  </div>
                  {groupedTankoubons.map((group) => (
                    <div key={group.label} className="space-y-3">
                      <h3 className="text-lg font-semibold">{group.label}</h3>
                      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
                        {group.archives.map((tank) => (
                          <TankoubonCard key={tank.tankoubon_id} tankoubon={tank} />
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  );
}
