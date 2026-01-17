'use client';

import { Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { AlertTriangle, BookOpen, Heart, RefreshCw, Search, History } from 'lucide-react';

import { Header } from '@/components/layout/Header';
import { MobileBottomNav } from '@/components/layout/MobileBottomNav';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Spinner } from '@/components/ui/spinner';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ArchiveGrid } from '@/components/archive/ArchiveGrid';

import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { logger } from '@/lib/utils/logger';
import { groupArchivesByTime } from '@/lib/utils/time-group';
import { ArchiveService } from '@/lib/services/archive-service';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

type ActiveTab = 'favorites' | 'history';
type FavoriteItem = Archive | Tankoubon;

function getItemTitle(item: FavoriteItem): string {
  return 'arcid' in item ? item.title : item.name;
}

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
  const [favoritesError, setFavoritesError] = useState<string | null>(null);

  // Reading history state.
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyArchives, setHistoryArchives] = useState<Archive[]>([]);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [historyLoadedLanguage, setHistoryLoadedLanguage] = useState<string | null>(null);

  const [query, setQuery] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  const loadFavorites = useCallback(
    async (silent = false) => {
      if (!token) {
        setFavoriteItems([]);
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
  const normalizedQuery = query.trim().toLowerCase();

  const filteredFavoriteItems = useMemo(() => {
    if (!normalizedQuery) return favoriteItems;
    return favoriteItems.filter((item) => getItemTitle(item).toLowerCase().includes(normalizedQuery));
  }, [favoriteItems, normalizedQuery]);

  const filteredFavoritesGrouped = useMemo(
    () => groupArchivesByTime(filteredFavoriteItems, 'favoritetime', t),
    [filteredFavoriteItems, t]
  );

  const filteredHistoryItems = useMemo(() => {
    if (!normalizedQuery) return historyArchives;
    return historyArchives.filter((a) => a.title.toLowerCase().includes(normalizedQuery));
  }, [historyArchives, normalizedQuery]);

  const filteredHistoryGrouped = useMemo(
    () => groupArchivesByTime(filteredHistoryItems, 'lastreadtime', t),
    [filteredHistoryItems, t]
  );

  const onRefresh = useCallback(async () => {
    if (!token) return;
    if (refreshing || favoritesLoading || historyLoading) return;
    try {
      setRefreshing(true);
      if (activeTab === 'favorites') await loadFavorites(true);
      else await loadReadingHistory(true);
    } finally {
      setRefreshing(false);
    }
  }, [activeTab, favoritesLoading, historyLoading, loadFavorites, loadReadingHistory, refreshing, token]);

  return (
    <div className="min-h-screen bg-background pb-20 lg:pb-0">
      <Header />

      <div className="container mx-auto px-4 py-6 md:py-10">
        {!token ? (
          <Card className="mx-auto max-w-xl overflow-hidden">
            <CardHeader className="space-y-2">
              <div className="flex items-center gap-2">
                <Heart className="h-5 w-5" />
                <CardTitle className="text-xl">{t('library.title')}</CardTitle>
              </div>
              <p className="text-sm text-muted-foreground">{t('library.loginRequired')}</p>
            </CardHeader>
            <CardContent className="flex items-center justify-between gap-4">
              <Button onClick={() => router.push('/login')}>{t('auth.login')}</Button>
              <div className="text-xs text-muted-foreground">{t('favorites.noFavoritesHint')}</div>
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-4">
            <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                <div className="flex items-center gap-2">
                  <Heart className="h-5 w-5 text-primary" />
                  <h1 className="text-lg font-semibold tracking-tight md:text-xl">{t('library.title')}</h1>
                </div>
                <div className="text-sm text-muted-foreground">
                  {activeTab === 'favorites'
                    ? t('favorites.count').replace('{count}', String(filteredFavoriteItems.length))
                    : t('readingHistory.count').replace('{count}', String(filteredHistoryItems.length))}
                  {normalizedQuery && (
                    <span className="ml-2 text-xs text-muted-foreground">
                      (
                      {activeTab === 'favorites'
                        ? `${filteredFavoriteItems.length}/${favoriteItems.length}`
                        : `${filteredHistoryItems.length}/${historyArchives.length}`}
                      )
                    </span>
                  )}
                </div>
              </div>

              <div className="flex w-full items-center gap-2 md:w-auto">
                <div className="relative w-full md:w-[360px]">
                  <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                  <Input
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder={t('search.placeholder')}
                    className="h-9 pl-9"
                  />
                </div>
                <Button
                  variant="secondary"
                  size="icon"
                  onClick={onRefresh}
                  disabled={refreshing || favoritesLoading || historyLoading}
                  className="h-9 w-9 shrink-0"
                  aria-label={t('common.refresh')}
                  title={t('common.refresh')}
                >
                  <RefreshCw className={refreshing ? 'h-4 w-4 animate-spin' : 'h-4 w-4'} />
                </Button>
              </div>
            </div>

            {activeError && (
              <Alert variant="destructive">
                <AlertTriangle className="h-4 w-4" />
                <AlertTitle>{t('common.error')}</AlertTitle>
                <AlertDescription>{activeError}</AlertDescription>
              </Alert>
            )}

            <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as ActiveTab)}>
              <div className="grid gap-6 md:grid-cols-[220px_1fr]">
                {/* Desktop: vertical tabs */}
                <aside className="hidden md:block md:sticky md:top-20 h-fit">
                  <Card>
                    <CardContent className="p-2">
                      <TabsList className="flex h-auto w-full flex-col items-stretch gap-1 bg-transparent p-0">
                        <TabsTrigger
                          value="favorites"
                          className="w-full justify-start rounded-md px-3 py-2 data-[state=active]:bg-muted data-[state=active]:shadow-none"
                        >
                          <div className="flex w-full items-center justify-between gap-2">
                            <div className="flex items-center gap-2">
                              <Heart className="h-4 w-4" />
                              <span>{t('library.tabs.favorites')}</span>
                            </div>
                            <Badge variant="secondary">{favoriteItems.length}</Badge>
                          </div>
                        </TabsTrigger>
                        <TabsTrigger
                          value="history"
                          className="w-full justify-start rounded-md px-3 py-2 data-[state=active]:bg-muted data-[state=active]:shadow-none"
                        >
                          <div className="flex w-full items-center justify-between gap-2">
                            <div className="flex items-center gap-2">
                              <History className="h-4 w-4" />
                              <span>{t('library.tabs.history')}</span>
                            </div>
                            <Badge variant="secondary">
                              {historyLoadedLanguage === language ? String(historyArchives.length) : '...'}
                            </Badge>
                          </div>
                        </TabsTrigger>
                      </TabsList>
                    </CardContent>
                  </Card>
                </aside>

                <div>
                  {/* Mobile: horizontal tabs */}
                  <div className="md:hidden">
                    <TabsList className="grid w-full grid-cols-2 mb-4">
                      <TabsTrigger value="favorites" className="gap-2">
                        <Heart className="h-4 w-4" />
                        {t('library.tabs.favorites')}
                      </TabsTrigger>
                      <TabsTrigger value="history" className="gap-2">
                        <History className="h-4 w-4" />
                        {t('library.tabs.history')}
                      </TabsTrigger>
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
                    ) : filteredFavoritesGrouped.length === 0 ? (
                      <Card className="border-dashed">
                        <CardContent className="text-center py-12">
                          <Heart className="h-16 w-16 mx-auto mb-4 text-muted-foreground" />
                          <p className="text-lg text-muted-foreground">
                            {normalizedQuery ? t('archive.noMatchingArchives') : t('favorites.noFavorites')}
                          </p>
                          {!normalizedQuery && (
                            <p className="text-sm text-muted-foreground mt-2">{t('favorites.noFavoritesHint')}</p>
                          )}
                        </CardContent>
                      </Card>
                    ) : (
                      <div className="space-y-8">
                        {filteredFavoritesGrouped.map((group) => (
                          <div key={group.label} className="space-y-3">
                            <div className="flex items-center justify-between gap-3">
                              <h3 className="text-base font-semibold md:text-lg">{group.label}</h3>
                              <Badge variant="secondary">{group.archives.length}</Badge>
                            </div>
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
                    ) : filteredHistoryGrouped.length === 0 ? (
                      <Card className="border-dashed">
                        <CardContent className="text-center py-12">
                          <BookOpen className="h-16 w-16 mx-auto mb-4 text-muted-foreground" />
                          <p className="text-lg text-muted-foreground">
                            {normalizedQuery ? t('archive.noMatchingArchives') : t('readingHistory.noHistory')}
                          </p>
                          {!normalizedQuery && (
                            <p className="text-sm text-muted-foreground mt-2">{t('readingHistory.noHistoryHint')}</p>
                          )}
                        </CardContent>
                      </Card>
                    ) : (
                      <div className="space-y-8">
                        {filteredHistoryGrouped.map((group) => (
                          <div key={group.label} className="space-y-3">
                            <div className="flex items-center justify-between gap-3">
                              <h3 className="text-base font-semibold md:text-lg">{group.label}</h3>
                              <Badge variant="secondary">{group.archives.length}</Badge>
                            </div>
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
