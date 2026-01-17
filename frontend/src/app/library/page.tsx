'use client';

import { Suspense, useCallback, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { BookOpen, Heart } from 'lucide-react';

import { Header } from '@/components/layout/Header';
import { MobileBottomNav } from '@/components/layout/MobileBottomNav';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Spinner } from '@/components/ui/spinner';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ArchiveGrid } from '@/components/archive/ArchiveGrid';

import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { logger } from '@/lib/utils/logger';
import { groupArchivesByTime, TimeGroup } from '@/lib/utils/time-group';
import { ArchiveService } from '@/lib/services/archive-service';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

type ActiveTab = 'favorites' | 'history';
type FavoriteItem = Archive | Tankoubon;

function timeToMs(v: unknown): number {
  if (!v) return 0;
  if (typeof v === 'number') return v * 1000; // backend uses seconds in most places
  if (typeof v === 'string') {
    const d = new Date(v);
    const ms = d.getTime();
    return Number.isFinite(ms) ? ms : 0;
  }
  return 0;
}

function LibraryPageContent() {
  const { t, language } = useLanguage();
  const { token } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();

  const tabFromUrl = (searchParams?.get('tab') ?? '').toLowerCase();
  const initialTab: ActiveTab = tabFromUrl === 'history' ? 'history' : 'favorites';

  const [activeTab, setActiveTab] = useState<ActiveTab>(initialTab);

  // Favorites state (archives + tankoubons mixed together; no extra level of tabs).
  const [favoritesLoading, setFavoritesLoading] = useState(true);
  const [favoriteItems, setFavoriteItems] = useState<FavoriteItem[]>([]);
  const [favoritesGrouped, setFavoritesGrouped] = useState<TimeGroup[]>([]);
  const [favoritesError, setFavoritesError] = useState<string | null>(null);

  // Reading history state.
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyArchives, setHistoryArchives] = useState<Archive[]>([]);
  const [historyGrouped, setHistoryGrouped] = useState<TimeGroup[]>([]);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [historyLoadedLanguage, setHistoryLoadedLanguage] = useState<string | null>(null);

  const loadFavorites = useCallback(
    async (silent = false) => {
      if (!token) {
        setFavoriteItems([]);
        setFavoritesGrouped([]);
        setFavoritesError(null);
        setFavoritesLoading(false);
        return;
      }
      try {
        if (!silent) setFavoritesLoading(true);
        setFavoritesError(null);

        const [archivesRes, tankRes] = await Promise.allSettled([
          ArchiveService.search({
            favoriteonly: true,
            groupby_tanks: false,
            sortby: 'date_added',
            order: 'desc',
            start: 0,
            count: 1000,
            lang: language,
          }),
          TankoubonService.getFavoriteTankoubons({
            start: 0,
            count: 1000,
          }),
        ]);

        const archives: FavoriteItem[] =
          archivesRes.status === 'fulfilled'
            ? ((archivesRes.value.data as Archive[]) ?? [])
            : [];
        const tankoubons: FavoriteItem[] =
          tankRes.status === 'fulfilled'
            ? (tankRes.value.data ?? [])
            : [];

        if (archivesRes.status === 'rejected' || tankRes.status === 'rejected') {
          setFavoritesError(t('favorites.loadError'));
          if (archivesRes.status === 'rejected') logger.apiError('加载收藏归档失败:', archivesRes.reason);
          if (tankRes.status === 'rejected') logger.apiError('加载收藏合集失败:', tankRes.reason);
        }

        const combined = [...archives, ...tankoubons].sort(
          (a, b) => timeToMs((b as any).favoritetime) - timeToMs((a as any).favoritetime)
        );

        setFavoriteItems(combined);
        setFavoritesGrouped(groupArchivesByTime(combined, 'favoritetime', t));
      } catch (err) {
        logger.apiError('加载收藏列表失败:', err);
        setFavoritesError(t('favorites.loadError'));
      } finally {
        if (!silent) setFavoritesLoading(false);
      }
    },
    [language, t, token]
  );

  const loadReadingHistory = useCallback(
    async (silent = false) => {
      if (!token) {
        setHistoryArchives([]);
        setHistoryGrouped([]);
        setHistoryError(null);
        setHistoryLoadedLanguage(null);
        setHistoryLoading(false);
        return;
      }
      try {
        if (!silent) setHistoryLoading(true);
        setHistoryError(null);

        const response = await ArchiveService.search({
          sortby: 'lastread',
          order: 'desc',
          start: 0,
          count: 1000,
          lang: language,
        });

        const archiveData = response.data as Archive[];
        setHistoryArchives(archiveData);
        setHistoryGrouped(groupArchivesByTime(archiveData, 'lastreadtime', t));
        setHistoryLoadedLanguage(language);
      } catch (err) {
        logger.apiError('readingHistory.loadError', err);
        setHistoryError(t('readingHistory.loadError'));
      } finally {
        if (!silent) setHistoryLoading(false);
      }
    },
    [language, t, token]
  );

  // Load favorites on mount.
  useEffect(() => {
    loadFavorites();
  }, [loadFavorites]);

  // Lazy-load history when user switches to it (or when language changes).
  useEffect(() => {
    if (activeTab === 'history' && historyLoadedLanguage !== language && !historyLoading) {
      loadReadingHistory();
    }
  }, [activeTab, historyLoading, historyLoadedLanguage, language, loadReadingHistory]);

  // Keep URL in sync for shareable links and redirects from legacy routes.
  useEffect(() => {
    const current = (searchParams?.get('tab') ?? '').toLowerCase();
    if ((activeTab === 'favorites' && current !== 'favorites') || (activeTab === 'history' && current !== 'history')) {
      router.replace(`/library?tab=${activeTab}`);
    }
    // We intentionally omit `searchParams` to avoid infinite loops.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeTab, router]);

  const activeError = activeTab === 'favorites' ? favoritesError : historyError;

  return (
    <div className="min-h-screen bg-background pb-20 lg:pb-0">
      <Header />

      <div className="container mx-auto px-4 py-8">
        {!token ? (
          <div className="space-y-3">
            <div className="flex items-center gap-2">
              <Heart className="w-5 h-5" />
              <h1 className="text-xl font-semibold">{t('library.title')}</h1>
            </div>
            <p className="text-sm text-muted-foreground">{t('library.loginRequired')}</p>
            <Button onClick={() => router.push('/login')}>{t('auth.login')}</Button>
          </div>
        ) : (
          <div className="space-y-4">
            {activeError && <div className="text-red-500 mb-4">{activeError}</div>}

            <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as ActiveTab)}>
              <div className="grid gap-6 md:grid-cols-[220px_1fr]">
                {/* Desktop: vertical tabs */}
                <aside className="hidden md:block md:sticky md:top-20 h-fit">
                  <TabsList className="flex h-auto w-full flex-col items-stretch gap-1 bg-transparent p-0">
                    <TabsTrigger
                      value="favorites"
                      className="w-full justify-start rounded-md px-3 py-2 data-[state=active]:bg-muted data-[state=active]:shadow-none"
                    >
                      {t('library.tabs.favorites')}
                    </TabsTrigger>
                    <TabsTrigger
                      value="history"
                      className="w-full justify-start rounded-md px-3 py-2 data-[state=active]:bg-muted data-[state=active]:shadow-none"
                    >
                      {t('library.tabs.history')}
                    </TabsTrigger>
                  </TabsList>
                </aside>

                <div>
                  {/* Mobile: horizontal tabs */}
                  <div className="md:hidden">
                    <TabsList className="grid w-full grid-cols-2 mb-6">
                      <TabsTrigger value="favorites">{t('library.tabs.favorites')}</TabsTrigger>
                      <TabsTrigger value="history">{t('library.tabs.history')}</TabsTrigger>
                    </TabsList>
                  </div>

                  <TabsContent value="favorites">
                  {favoritesLoading ? (
                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
                    {Array.from({ length: 10 }).map((_, i) => (
                      <div key={i} className="space-y-2">
                        <Skeleton className="aspect-[3/4] w-full" />
                        <Skeleton className="h-4 w-full" />
                        <Skeleton className="h-4 w-2/3" />
                      </div>
                    ))}
                  </div>
                ) : favoritesGrouped.length === 0 ? (
                  <div className="text-center py-12">
                    <Heart className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
                    <p className="text-lg text-muted-foreground">{t('favorites.noFavorites')}</p>
                    <p className="text-sm text-muted-foreground mt-2">{t('favorites.noFavoritesHint')}</p>
                  </div>
                ) : (
                  <div className="space-y-8">
                    <div className="mb-4 text-sm text-muted-foreground">
                      {t('favorites.count').replace('{count}', String(favoriteItems.length))}
                    </div>
                    {favoritesGrouped.map((group) => (
                      <div key={group.label} className="space-y-3">
                        <h3 className="text-lg font-semibold">{group.label}</h3>
                        <ArchiveGrid archives={group.archives as any} />
                      </div>
                    ))}
                  </div>
                )}
                  </TabsContent>

                  <TabsContent value="history">
                {historyLoading ? (
                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
                    {Array.from({ length: 10 }).map((_, i) => (
                      <div key={i} className="space-y-2">
                        <Skeleton className="aspect-[3/4] w-full" />
                        <Skeleton className="h-4 w-full" />
                        <Skeleton className="h-4 w-2/3" />
                      </div>
                    ))}
                  </div>
                ) : historyGrouped.length === 0 ? (
                  <div className="text-center py-12">
                    <BookOpen className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
                    <p className="text-lg text-muted-foreground">{t('readingHistory.noHistory')}</p>
                    <p className="text-sm text-muted-foreground mt-2">{t('readingHistory.noHistoryHint')}</p>
                  </div>
                ) : (
                  <div className="space-y-8">
                    <div className="mb-4 text-sm text-muted-foreground">
                      {t('readingHistory.count').replace('{count}', String(historyArchives.length))}
                    </div>
                    {historyGrouped.map((group) => (
                      <div key={group.label} className="space-y-3">
                        <h3 className="text-lg font-semibold">{group.label}</h3>
                        <ArchiveGrid archives={group.archives as any} />
                      </div>
                    ))}
                  </div>
                )}
                  </TabsContent>
                </div>
              </div>
            </Tabs>
          </div>
	        )}
      </div>

      <MobileBottomNav />
    </div>
  );
}

export default function LibraryPage() {
  return (
    <Suspense
      fallback={
        <div className="min-h-screen bg-background flex items-center justify-center">
          <Spinner size="lg" />
        </div>
      }
    >
      <LibraryPageContent />
    </Suspense>
  );
}
