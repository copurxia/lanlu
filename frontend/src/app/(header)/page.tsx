'use client';

import { ArchiveGrid } from '@/components/archive/ArchiveGrid';
import { Pagination } from '@/components/ui/pagination';
import { Spinner } from '@/components/ui/spinner';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogBody, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { MobileBottomNav } from '@/components/layout/MobileBottomNav';
import { SearchSidebar } from '@/components/layout/SearchSidebar';
import { ArchiveService } from '@/lib/services/archive-service';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { Archive } from '@/types/archive';
import { Tankoubon } from '@/types/tankoubon';
import { appEvents, AppEvents } from '@/lib/utils/events';
import { RefreshCw } from 'lucide-react';
import { useState, useEffect, useCallback, Suspense, useRef, useMemo } from 'react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useDebounce, useGridColumnCount } from '@/hooks/common-hooks';
import { useSearchParams, useRouter } from 'next/navigation';
import { logger } from '@/lib/utils/logger';

// In-memory cache so random recommendations don't change when navigating away and back.
// Keyed by `${gridColumnCount}:${language}`.
const randomArchivesCache = new Map<string, any[]>();

function isAbortLikeError(err: any) {
  return (
    err?.name === 'AbortError' ||
    err?.name === 'CanceledError' ||
    err?.code === 'ERR_CANCELED' ||
    err?.message === 'canceled'
  );
}

function HomePageContent() {
  const { t, language } = useLanguage();
  const searchParams = useSearchParams();
  const router = useRouter();
  const gridColumnCount = useGridColumnCount();
  const pageSize = 20;
  const randomKey = `${gridColumnCount}:${language}`;
  const mainScrollRef = useRef<HTMLElement | null>(null);
  const lastPageRef = useRef<number | null>(null);

  const [archives, setArchives] = useState<any[]>([]);
  const cachedRandomArchives =
    typeof window !== 'undefined' ? randomArchivesCache.get(randomKey) : undefined;
  const [randomArchives, setRandomArchives] = useState<any[]>(() => cachedRandomArchives ?? []);
  const [loading, setLoading] = useState(true);
  const [randomLoading, setRandomLoading] = useState(() => !cachedRandomArchives);
  const [currentPage, setCurrentPage] = useState(0);
  const [totalPages, setTotalPages] = useState(0);
  const [totalRecords, setTotalRecords] = useState(0);
  const [sortBy, setSortBy] = useState('date_added');
  const [sortOrder, setSortOrder] = useState('desc');
  const [searchQuery, setSearchQuery] = useState('');
  const [newonly, setNewonly] = useState(false);
  const [untaggedonly, setUntaggedonly] = useState(false);
  const [favoriteonly, setFavoriteonly] = useState(false);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [groupByTanks, setGroupByTanks] = useState(true); // 默认启用Tankoubon分组
  const [categoryId, setCategoryId] = useState<string>('all');
  const [isInitialized, setIsInitialized] = useState(false);
  const [filterDialogOpen, setFilterDialogOpen] = useState(false);
  const lastRandomKeyRef = useRef<string | null>(null);
  const archivesAbortRef = useRef<AbortController | null>(null);
  const archivesRequestIdRef = useRef(0);

  // 读取URL参数
  const urlQuery = searchParams?.get('q') || '';
  const urlSortBy = searchParams?.get('sortby') || (urlQuery ? 'relevance' : 'date_added');
  const urlSortOrder = searchParams?.get('order') || 'desc';
  const urlNewonly = searchParams?.get('newonly') === 'true';
  const urlUntaggedonly = searchParams?.get('untaggedonly') === 'true';
  const urlFavoriteonly = searchParams?.get('favoriteonly') === 'true';
  const urlDateFrom = searchParams?.get('date_from') || '';
  const urlDateTo = searchParams?.get('date_to') || '';
  const urlGroupByTanks = searchParams?.get('groupby_tanks') !== 'false'; // 默认为true
  const urlCategoryId = searchParams?.get('category_id') || 'all';
  const urlPage = parseInt(searchParams?.get('page') || '0', 10); // 从URL读取页码

  const fetchInput = useMemo(() => ({
    page: currentPage,
    sortBy,
    sortOrder,
    searchQuery,
    newonly,
    untaggedonly,
    favoriteonly,
    dateFrom,
    dateTo,
    groupByTanks,
    categoryId,
    language,
  }), [categoryId, currentPage, dateFrom, dateTo, favoriteonly, groupByTanks, language, newonly, searchQuery, sortBy, sortOrder, untaggedonly]);
  const fetchInputRef = useRef(fetchInput);
  useEffect(() => {
    fetchInputRef.current = fetchInput;
  }, [fetchInput]);

  const debouncedFetchInput = useDebounce(fetchInput, 250);

  const fetchArchives = useCallback(async (input: typeof fetchInput) => {
    const requestId = (archivesRequestIdRef.current += 1);
    archivesAbortRef.current?.abort();
    const controller = new AbortController();
    archivesAbortRef.current = controller;

    try {
      setLoading(true);
      const params: any = {
        start: input.page * pageSize,
        count: pageSize,
        sortby: input.sortBy,
        order: input.sortOrder
      };

      if (input.searchQuery) params.filter = input.searchQuery;
      if (input.newonly) params.newonly = true;
      if (input.untaggedonly) params.untaggedonly = true;
      if (input.favoriteonly) params.favoriteonly = true;
      if (input.dateFrom) params.date_from = input.dateFrom;
      if (input.dateTo) params.date_to = input.dateTo;
      if (input.categoryId && input.categoryId !== 'all') params.category_id = input.categoryId;
      params.groupby_tanks = input.groupByTanks; // 添加Tankoubon分组参数
      params.lang = input.language; // 添加语言参数用于标签翻译

      const result = await ArchiveService.search(params, { signal: controller.signal });
      if (requestId !== archivesRequestIdRef.current) return;
      let data: (Archive | Tankoubon)[] = [...result.data];
      let totalRecordsAdjusted = result.recordsTotal;

      // 如果是搜索模式且启用了合集分组，手动搜索匹配的合集
      if (input.searchQuery && input.groupByTanks) {
        try {
          // 获取所有合集并过滤
          const allTanks = await TankoubonService.getAllTankoubons({ signal: controller.signal });
          if (requestId !== archivesRequestIdRef.current) return;
          const queryLower = input.searchQuery.toLowerCase();
          const matchingTanks = allTanks.filter(tank => 
            tank.name.toLowerCase().includes(queryLower) || 
            (tank.tags && tank.tags.toLowerCase().includes(queryLower))
          );

          // 过滤掉已经在结果中的合集（避免重复）
          const existingTankIds = new Set(
            data.filter(item => 'tankoubon_id' in item).map(item => (item as any).tankoubon_id)
          );
          
          const newTanks = matchingTanks.filter(tank => !existingTankIds.has(tank.tankoubon_id));
          
          // 调整总数
          totalRecordsAdjusted += newTanks.length;

          // 仅在第一页将匹配的合集插入到结果前面
          if (input.page === 0) {
            data = [...newTanks, ...data];
          }
        } catch (err) {
          if (isAbortLikeError(err)) return;
          logger.apiError('fetch matching tankoubons', err);
        }
      }

      if (requestId !== archivesRequestIdRef.current) return;
      setArchives(data);
      setTotalRecords(totalRecordsAdjusted);
      setTotalPages(Math.ceil(totalRecordsAdjusted / pageSize));
    } catch (error) {
      if (isAbortLikeError(error)) return;
      logger.apiError('fetch archives', error);
    } finally {
      if (requestId === archivesRequestIdRef.current) setLoading(false);
    }
  }, [pageSize]);

  const fetchRandomArchives = useCallback(async (options?: { force?: boolean }) => {
    if (typeof window !== 'undefined' && !options?.force) {
      const cached = randomArchivesCache.get(randomKey);
      if (cached) {
        setRandomArchives(cached);
        setRandomLoading(false);
        return;
      }
    }

    try {
      setRandomLoading(true);
      const archives = await ArchiveService.getRandom({ count: gridColumnCount, lang: language });
      setRandomArchives(archives);
      if (typeof window !== 'undefined') randomArchivesCache.set(randomKey, archives);
    } catch (error) {
      logger.apiError('fetch random archives', error);
      setRandomArchives([]);
      if (typeof window !== 'undefined') randomArchivesCache.set(randomKey, []);
    } finally {
      setRandomLoading(false);
    }
  }, [gridColumnCount, language, randomKey]);

  // Cancel in-flight list request on unmount.
  useEffect(() => {
    return () => archivesAbortRef.current?.abort();
  }, []);

  // 设置初始状态（从URL参数）
  useEffect(() => {
    setSearchQuery(urlQuery);
    if (urlSortBy) setSortBy(urlSortBy);
    if (urlSortOrder) setSortOrder(urlSortOrder);
    setNewonly(urlNewonly);
    setUntaggedonly(urlUntaggedonly);
    setFavoriteonly(urlFavoriteonly);
    setDateFrom(urlDateFrom);
    setDateTo(urlDateTo);
    setGroupByTanks(urlGroupByTanks);
    setCategoryId(urlCategoryId);
    setCurrentPage(urlPage); // 从URL恢复页码

    // 标记为已初始化，避免在初始化期间同步URL
    setIsInitialized(true);
  }, [urlCategoryId, urlDateFrom, urlDateTo, urlFavoriteonly, urlGroupByTanks, urlNewonly, urlQuery, urlSortBy, urlSortOrder, urlUntaggedonly, urlPage]);

  // 同步状态到URL（仅在初始化完成后执行）
  useEffect(() => {
    if (!isInitialized) return;

    const params = new URLSearchParams();
    if (searchQuery) params.set('q', searchQuery);
    if (sortBy !== 'date_added') params.set('sortby', sortBy);
    if (sortOrder !== 'desc') params.set('order', sortOrder);
    if (newonly) params.set('newonly', 'true');
    if (untaggedonly) params.set('untaggedonly', 'true');
    if (favoriteonly) params.set('favoriteonly', 'true');
    if (dateFrom) params.set('date_from', dateFrom);
    if (dateTo) params.set('date_to', dateTo);
    if (categoryId && categoryId !== 'all') params.set('category_id', categoryId);
    // Always reflect this in the URL so it's shareable/reproducible.
    params.set('groupby_tanks', groupByTanks ? 'true' : 'false');
    if (currentPage > 0) params.set('page', currentPage.toString()); // 只在非第一页时添加页码参数

    const queryString = params.toString();
    const newUrl = queryString ? `/?${queryString}` : '/';
    if (typeof window !== 'undefined') {
      const currentUrl = `${window.location.pathname}${window.location.search}`;
      if (currentUrl !== newUrl) {
        router.replace(newUrl);
      }
      return;
    }
    router.replace(newUrl);
  }, [categoryId, currentPage, dateFrom, dateTo, favoriteonly, groupByTanks, isInitialized, newonly, router, searchQuery, sortBy, sortOrder, untaggedonly]);

  useEffect(() => {
    // 只在客户端执行数据获取，避免静态生成时的API调用
    // 确保只在初始化完成后才获取数据，避免使用未同步的初始状态
    if (typeof window !== 'undefined' && isInitialized) {
      fetchArchives(debouncedFetchInput);
    }
  }, [debouncedFetchInput, fetchArchives, isInitialized]);

  // Random recommendations are hidden during search, and they don't need to refresh on every filter/sort/page change.
  useEffect(() => {
    if (typeof window === 'undefined' || !isInitialized) return;
    if (searchQuery) return;
    if (lastRandomKeyRef.current === randomKey) return;
    lastRandomKeyRef.current = randomKey;
    // Avoid refreshing when navigating away/back by restoring from cache if available.
    const cached = randomArchivesCache.get(randomKey);
    if (cached) {
      setRandomArchives(cached);
      setRandomLoading(false);
      return;
    }
    setRandomArchives([]);
    fetchRandomArchives();
  }, [fetchRandomArchives, isInitialized, randomKey, searchQuery]);

  // 监听上传完成事件，刷新首页数据
  useEffect(() => {
    const handleUploadCompleted = () => {
      fetchArchives(fetchInputRef.current);
      if (!searchQuery) fetchRandomArchives({ force: true });
    };

    const handleArchivesRefresh = () => {
      fetchArchives(fetchInputRef.current);
      if (!searchQuery) fetchRandomArchives({ force: true });
    };

    const handleSearchReset = () => {
      // 重置所有搜索相关状态
      setSearchQuery('');
      setSortBy('date_added');
      setSortOrder('desc');
      setNewonly(false);
      setUntaggedonly(false);
      setFavoriteonly(false);
      setDateFrom('');
      setDateTo('');
      setGroupByTanks(true);
      setCurrentPage(0);
    };

    appEvents.on(AppEvents.UPLOAD_COMPLETED, handleUploadCompleted);
    appEvents.on(AppEvents.ARCHIVES_REFRESH, handleArchivesRefresh);
    appEvents.on(AppEvents.SEARCH_RESET, handleSearchReset);

    return () => {
      appEvents.off(AppEvents.UPLOAD_COMPLETED, handleUploadCompleted);
      appEvents.off(AppEvents.ARCHIVES_REFRESH, handleArchivesRefresh);
      appEvents.off(AppEvents.SEARCH_RESET, handleSearchReset);
    };
  }, [fetchArchives, fetchRandomArchives, searchQuery]);

  // Open mobile filter dialog from the global header action.
  useEffect(() => {
    const handleFilterOpen = () => setFilterDialogOpen(true);
    appEvents.on(AppEvents.FILTER_OPEN, handleFilterOpen);
    return () => appEvents.off(AppEvents.FILTER_OPEN, handleFilterOpen);
  }, []);

  const handleSearch = (params: {
    query?: string;
    sortBy?: string;
    sortOrder?: string;
    dateFrom?: string;
    dateTo?: string;
    newonly?: boolean;
    untaggedonly?: boolean;
    favoriteonly?: boolean;
    groupby_tanks?: boolean;
    category_id?: string;
  }) => {
    // Search query is controlled by the global header search bar. Only update it when explicitly provided.
    if (typeof params.query === 'string') setSearchQuery(params.query);
    // 当有搜索查询且没有指定排序时，默认使用相关度排序
    if (params.sortBy) {
      setSortBy(params.sortBy);
    } else if (params.query) {
      setSortBy('relevance');
    }
    if (params.sortOrder) setSortOrder(params.sortOrder);
    if (typeof params.dateFrom === 'string') setDateFrom(params.dateFrom);
    if (typeof params.dateTo === 'string') setDateTo(params.dateTo);
    if (typeof params.newonly === 'boolean') setNewonly(params.newonly);
    if (typeof params.untaggedonly === 'boolean') setUntaggedonly(params.untaggedonly);
    if (typeof params.favoriteonly === 'boolean') setFavoriteonly(params.favoriteonly);
    if (typeof params.groupby_tanks === 'boolean') setGroupByTanks(params.groupby_tanks);
    if ('category_id' in params) setCategoryId(params.category_id || 'all');
    setCurrentPage(0);
    // 移动端：应用筛选后自动关闭对话框
    setFilterDialogOpen(false);
  };

  const handlePageChange = (page: number) => {
    setCurrentPage(page);
  };

  // Homepage uses an independently scrollable <main>; reset its scroll position when the page changes.
  // This covers pagination clicks and history navigation (back/forward) that updates `page` via URL.
  useEffect(() => {
    if (!isInitialized) return;
    const prev = lastPageRef.current;
    lastPageRef.current = currentPage;
    if (prev === null || prev === currentPage) return;

    const reduceMotion =
      typeof window !== 'undefined' &&
      typeof window.matchMedia === 'function' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    mainScrollRef.current?.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' });
  }, [currentPage, isInitialized]);

  // 搜索模式检测
  const isSearchMode = searchQuery;
  const statsText = t('home.archivesCount')
    .replace('{count}', String(totalRecords))
    .replace('{page}', String(currentPage + 1))
    .replace('{totalPages}', String(totalPages));

  return (
    <div className="bg-background h-[calc(100dvh-var(--app-header-height,4rem))] overflow-hidden">
      {/* Use the real header height (CSS var) so the document never exceeds the viewport. */}
      <div className="flex h-full min-h-0">
        {/* 侧栏 - 桌面端显示 */}
        <div className="hidden lg:block flex-shrink-0 border-r border-border w-80 min-h-0">
          <SearchSidebar
            onSearch={handleSearch}
            loading={loading}
            filters={{
              sortBy,
              sortOrder,
              dateFrom,
              dateTo,
              newonly,
              untaggedonly,
              favoriteonly,
              groupByTanks,
              categoryId,
            }}
          />
        </div>

        {/* 主内容区 - 独立滚动 */}
        {/* Reserve just enough space for the fixed mobile bottom nav (plus iOS safe-area). */}
        <main
          ref={mainScrollRef}
          className="flex-1 min-w-0 min-h-0 overflow-y-auto pb-[calc(env(safe-area-inset-bottom)+3.75rem)] lg:pb-2"
        >
          {/* Slightly tighter vertical padding so section headers don't feel "pushed down" on both desktop and mobile. */}
          <div className="px-4 pt-4 pb-2">
          {/* 随机推荐 - 搜索模式下隐藏 */}
          {!isSearchMode && (
          <section className="mb-8">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-2xl font-semibold">{t('home.randomRecommendations')}</h2>
              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => fetchRandomArchives({ force: true })}
                  disabled={randomLoading}
                  className="border-border bg-background hover:bg-accent hover:text-accent-foreground"
                >
                  <RefreshCw className={`w-4 h-4 mr-2 ${randomLoading ? 'animate-spin' : ''}`} />
                  {t('common.refresh')}
                </Button>
              </div>
            </div>

            {randomArchives.length > 0 ? (
              <ArchiveGrid archives={randomArchives} variant="random" priorityCount={6} />
            ) : !randomLoading ? (
              <div className="text-center py-12">
                <p className="text-muted-foreground">{t('home.noRecommendations')}</p>
              </div>
            ) : null}
          </section>
          )}

          {/* 档案列表 */}
          <section>
            <div className="flex flex-col gap-3 mb-4">
              {/* 标题栏 + 排序控件同一行（移动端/桌面端统一） */}
              <div className="flex items-center justify-between gap-3">
                <h2 className="text-2xl font-semibold min-w-0 flex-1 truncate">
                  {searchQuery ? t('home.searchResults') : t('home.allArchives')}
                </h2>

                <div className="flex items-center gap-2 shrink-0">
                  <span className="hidden sm:inline text-sm text-muted-foreground">{t('home.sortBy')}</span>
                  <Select value={sortBy} onValueChange={setSortBy}>
                    <SelectTrigger className="w-[120px] sm:w-[140px] h-8">
                      <SelectValue>
                        {sortBy === 'lastread' && t('home.lastRead')}
                        {sortBy === 'date_added' && t('home.dateAdded')}
                        {sortBy === 'title' && t('home.titleSort')}
                        {sortBy === 'relevance' && t('home.relevance')}
                        {sortBy === 'pagecount' && t('home.pageCount')}
                        {sortBy === '_default' && t('settings.smartFilterDefault')}
                      </SelectValue>
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="relevance">{t('home.relevance')}</SelectItem>
                      <SelectItem value="lastread">{t('home.lastRead')}</SelectItem>
                      <SelectItem value="date_added">{t('home.dateAdded')}</SelectItem>
                      <SelectItem value="title">{t('home.titleSort')}</SelectItem>
                      <SelectItem value="pagecount">{t('home.pageCount')}</SelectItem>
                      <SelectItem value="_default">{t('settings.smartFilterDefault')}</SelectItem>
                    </SelectContent>
                  </Select>

                  <Select value={sortOrder} onValueChange={setSortOrder}>
                    <SelectTrigger className="w-[88px] sm:w-[100px] h-8">
                      <SelectValue>
                        {sortOrder === 'asc' && t('common.asc')}
                        {sortOrder === 'desc' && t('common.desc')}
                      </SelectValue>
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="asc">{t('common.asc')}</SelectItem>
                      <SelectItem value="desc">{t('common.desc')}</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
            </div>

            {/* 筛选对话框 */}
            <Dialog open={filterDialogOpen} onOpenChange={setFilterDialogOpen}>
              <DialogContent className="w-full">
                <DialogHeader className="px-4 py-3 border-b">
                  <DialogTitle>{t('home.advancedFilter')}</DialogTitle>
                </DialogHeader>
                <DialogBody className="px-0 py-0">
                  <SearchSidebar
                    onSearch={handleSearch}
                    loading={loading}
                    filters={{
                      sortBy,
                      sortOrder,
                      dateFrom,
                      dateTo,
                      newonly,
                      untaggedonly,
                      favoriteonly,
                      groupByTanks,
                      categoryId,
                    }}
                  />
                </DialogBody>
              </DialogContent>
            </Dialog>

            {archives.length > 0 ? (
              <>
                <ArchiveGrid archives={archives} variant="home" />

                <div className="mt-4 flex items-center justify-between gap-3">
                  <div
                    className="text-xs sm:text-sm text-muted-foreground min-w-0 flex-1 truncate"
                    title={statsText}
                  >
                    {statsText}
                  </div>
                  {totalPages > 1 && (
                    <Pagination
                      currentPage={currentPage}
                      totalPages={totalPages}
                      onPageChange={handlePageChange}
                      className="justify-end py-0"
                    />
                  )}
                </div>
              </>
            ) : !loading ? (
              <div className="text-center py-12">
                <p className="text-muted-foreground">
                  {searchQuery ? t('home.noMatchingArchives') : t('home.noArchives')}
                </p>
              </div>
            ) : null}
          </section>
          </div>
        </main>
      </div>

      <MobileBottomNav />
    </div>
  );
}

export default function HomePage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-background flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    }>
      <HomePageContent />
    </Suspense>
  );
}
