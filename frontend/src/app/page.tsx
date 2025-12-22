'use client';

import { ArchiveGrid } from '@/components/archive/ArchiveGrid';
import { Pagination } from '@/components/ui/pagination';
import { Spinner } from '@/components/ui/spinner';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogBody, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Header } from '@/components/layout/Header';
import { SearchSidebar } from '@/components/layout/SearchSidebar';
import { ArchiveService } from '@/lib/archive-service';
import { TankoubonService } from '@/lib/tankoubon-service';
import { Archive } from '@/types/archive';
import { Tankoubon } from '@/types/tankoubon';
import { appEvents, AppEvents } from '@/lib/events';
import { RefreshCw, Filter } from 'lucide-react';
import { useState, useEffect, useCallback, Suspense } from 'react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useGridColumnCount } from '@/hooks/common-hooks';
import { useSearchParams, useRouter } from 'next/navigation';
import { logger } from '@/lib/logger';

function HomePageContent() {
  const { t } = useLanguage();
  const searchParams = useSearchParams();
  const router = useRouter();
  const gridColumnCount = useGridColumnCount();

  const [archives, setArchives] = useState<any[]>([]);
  const [randomArchives, setRandomArchives] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [randomLoading, setRandomLoading] = useState(true);
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
  const [isInitialized, setIsInitialized] = useState(false);
  const [filterDialogOpen, setFilterDialogOpen] = useState(false);
  const pageSize = 20;

  // 读取URL参数
  const urlQuery = searchParams?.get('q') || '';
  const urlSortBy = searchParams?.get('sortby') || 'date_added';
  const urlSortOrder = searchParams?.get('order') || 'desc';
  const urlNewonly = searchParams?.get('newonly') === 'true';
  const urlUntaggedonly = searchParams?.get('untaggedonly') === 'true';
  const urlFavoriteonly = searchParams?.get('favoriteonly') === 'true';
  const urlDateFrom = searchParams?.get('date_from') || '';
  const urlDateTo = searchParams?.get('date_to') || '';
  const urlGroupByTanks = searchParams?.get('groupby_tanks') !== 'false'; // 默认为true

  const fetchArchives = useCallback(async (page: number = 0) => {
    try {
      setLoading(true);
      const params: any = {
        start: page * pageSize,
        count: pageSize,
        sortby: sortBy,
        order: sortOrder
      };

      if (searchQuery) params.filter = searchQuery;
      if (newonly) params.newonly = true;
      if (untaggedonly) params.untaggedonly = true;
      if (favoriteonly) params.favoriteonly = true;
      if (dateFrom) params.date_from = dateFrom;
      if (dateTo) params.date_to = dateTo;
      params.groupby_tanks = groupByTanks; // 添加Tankoubon分组参数

      const result = await ArchiveService.search(params);
      let data: (Archive | Tankoubon)[] = [...result.data];
      let totalRecordsAdjusted = result.recordsTotal;

      // 如果是搜索模式且启用了合集分组，手动搜索匹配的合集
      if (searchQuery && groupByTanks) {
        try {
          // 获取所有合集并过滤
          const allTanks = await TankoubonService.getAllTankoubons();
          const queryLower = searchQuery.toLowerCase();
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
          if (page === 0) {
            data = [...newTanks, ...data];
          }
        } catch (err) {
          logger.apiError('fetch matching tankoubons', err);
        }
      }

      setArchives(data);
      setTotalRecords(totalRecordsAdjusted);
      setTotalPages(Math.ceil(totalRecordsAdjusted / pageSize));
    } catch (error) {
      logger.apiError('fetch archives', error);
      setArchives([]);
    } finally {
      setLoading(false);
    }
  }, [pageSize, sortBy, sortOrder, searchQuery, newonly, untaggedonly, favoriteonly, dateFrom, dateTo, groupByTanks]);

  const fetchRandomArchives = useCallback(async () => {
    try {
      setRandomLoading(true);
      const archives = await ArchiveService.getRandom({ count: gridColumnCount });
      setRandomArchives(archives);
    } catch (error) {
      logger.apiError('fetch random archives', error);
      setRandomArchives([]);
    } finally {
      setRandomLoading(false);
    }
  }, [gridColumnCount]);

  // 设置初始状态（从URL参数）
  useEffect(() => {
    if (urlQuery) setSearchQuery(urlQuery);
    if (urlSortBy) setSortBy(urlSortBy);
    if (urlSortOrder) setSortOrder(urlSortOrder);
    setNewonly(urlNewonly);
    setUntaggedonly(urlUntaggedonly);
    setFavoriteonly(urlFavoriteonly);
    setDateFrom(urlDateFrom);
    setDateTo(urlDateTo);
    setGroupByTanks(urlGroupByTanks);

    // 标记为已初始化，避免在初始化期间同步URL
    setIsInitialized(true);
  }, [urlQuery, urlSortBy, urlSortOrder, urlNewonly, urlUntaggedonly, urlFavoriteonly, urlDateFrom, urlDateTo, urlGroupByTanks]);

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
    if (!groupByTanks) params.set('groupby_tanks', 'false'); // 只在禁用时添加参数

    const queryString = params.toString();
    const newUrl = queryString ? `/?${queryString}` : '/';
    router.replace(newUrl);
  }, [searchQuery, sortBy, sortOrder, newonly, untaggedonly, favoriteonly, dateFrom, dateTo, groupByTanks, router, isInitialized]);

  useEffect(() => {
    // 只在客户端执行数据获取，避免静态生成时的API调用
    // 确保只在初始化完成后才获取数据，避免使用未同步的初始状态
    if (typeof window !== 'undefined' && isInitialized) {
      fetchArchives(currentPage);
      fetchRandomArchives();
    }
  }, [currentPage, fetchArchives, fetchRandomArchives, sortBy, sortOrder, newonly, untaggedonly, favoriteonly, dateFrom, dateTo, groupByTanks, isInitialized]);

  // 监听上传完成事件，刷新首页数据
  useEffect(() => {
    const handleUploadCompleted = () => {
      fetchArchives(currentPage);
      fetchRandomArchives();
    };

    const handleArchivesRefresh = () => {
      fetchArchives(currentPage);
      fetchRandomArchives();
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
  }, [currentPage, fetchArchives, fetchRandomArchives]);

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
  }) => {
    setSearchQuery(params.query || '');
    if (params.sortBy) setSortBy(params.sortBy);
    if (params.sortOrder) setSortOrder(params.sortOrder);
    if (typeof params.dateFrom === 'string') setDateFrom(params.dateFrom);
    if (typeof params.dateTo === 'string') setDateTo(params.dateTo);
    if (typeof params.newonly === 'boolean') setNewonly(params.newonly);
    if (typeof params.untaggedonly === 'boolean') setUntaggedonly(params.untaggedonly);
    if (typeof params.favoriteonly === 'boolean') setFavoriteonly(params.favoriteonly);
    if (typeof params.groupby_tanks === 'boolean') setGroupByTanks(params.groupby_tanks);
    setCurrentPage(0);
    // 移动端：应用筛选后自动关闭对话框
    setFilterDialogOpen(false);
  };

  const handlePageChange = (page: number) => {
    setCurrentPage(page);
  };

  // 搜索模式检测
  const isSearchMode = searchQuery;

  return (
    <div className="min-h-screen bg-background">
      <Header />

      <div className="flex min-h-screen">
        {/* 侧栏 - 桌面端显示 */}
        <div className="hidden lg:block flex-shrink-0 border-r border-border">
          <SearchSidebar onSearch={handleSearch} loading={loading} />
        </div>

        {/* 主内容区 */}
        <main className="flex-1 min-w-0 px-4 py-8">
          {/* 随机推荐 - 搜索模式下隐藏 */}
          {!isSearchMode && (
          <section className="mb-12">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-2xl font-semibold">{t('home.randomRecommendations')}</h2>
              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={fetchRandomArchives}
                  disabled={randomLoading}
                  className="border-border bg-background hover:bg-accent hover:text-accent-foreground"
                >
                  <RefreshCw className={`w-4 h-4 mr-2 ${randomLoading ? 'animate-spin' : ''}`} />
                  {t('common.refresh')}
                </Button>
              </div>
            </div>

            {randomArchives.length > 0 ? (
              <ArchiveGrid archives={randomArchives} variant="random" />
            ) : !randomLoading ? (
              <div className="text-center py-12">
                <p className="text-muted-foreground">{t('home.noRecommendations')}</p>
              </div>
            ) : null}
          </section>
          )}

          {/* 档案列表 */}
          <section>
            <div className="flex flex-col gap-4 mb-6">
              {/* PC端：标题、档案数量和排序控件在一行；移动端：分行显示 */}
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <h2 className="text-2xl font-semibold">
                  {searchQuery ? t('home.searchResults') : t('home.allArchives')}
                </h2>

                <div className="flex flex-col sm:flex-row sm:items-center gap-4">
                  <div className="flex items-center gap-4">
                    <div className="text-sm text-muted-foreground">
                      {t('home.archivesCount').replace('{count}', String(totalRecords)).replace('{page}', String(currentPage + 1)).replace('{totalPages}', String(totalPages))}
                    </div>
                    {/* 移动端筛选按钮 */}
                    <Button
                      variant="outline"
                      size="sm"
                      className="lg:hidden ml-auto"
                      onClick={() => setFilterDialogOpen(true)}
                    >
                      <Filter className="w-4 h-4 mr-2" />
                      {t('common.filter')}
                    </Button>
                  </div>

                  <div className="flex items-center gap-2">
                    <span className="text-sm text-muted-foreground">{t('home.sortBy')}</span>
                    <Select value={sortBy} onValueChange={setSortBy}>
                      <SelectTrigger className="w-[140px] h-8">
                        <SelectValue>
                          {sortBy === 'lastread' && t('home.lastRead')}
                          {sortBy === 'date_added' && t('home.dateAdded')}
                          {sortBy === 'title' && t('home.titleSort')}
                          {sortBy === 'pagecount' && t('home.pageCount')}
                          {sortBy === '_default' && t('settings.smartFilterDefault')}
                        </SelectValue>
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="lastread">{t('home.lastRead')}</SelectItem>
                        <SelectItem value="date_added">{t('home.dateAdded')}</SelectItem>
                        <SelectItem value="title">{t('home.titleSort')}</SelectItem>
                        <SelectItem value="pagecount">{t('home.pageCount')}</SelectItem>
                        <SelectItem value="_default">{t('settings.smartFilterDefault')}</SelectItem>
                      </SelectContent>
                    </Select>

                    <Select value={sortOrder} onValueChange={setSortOrder}>
                      <SelectTrigger className="w-[100px] h-8">
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
            </div>

            {/* 筛选对话框 */}
            <Dialog open={filterDialogOpen} onOpenChange={setFilterDialogOpen}>
              <DialogContent className="max-w-[90vw] w-full">
                <DialogHeader className="px-4 py-3 border-b">
                  <DialogTitle>{t('home.advancedFilter')}</DialogTitle>
                </DialogHeader>
                <DialogBody className="px-0 py-0">
                  <SearchSidebar onSearch={handleSearch} loading={loading} />
                </DialogBody>
              </DialogContent>
            </Dialog>

            {archives.length > 0 ? (
              <>
                <ArchiveGrid archives={archives} variant="home" />

                {totalPages > 1 && (
                  <div className="mt-8">
                    <Pagination
                      currentPage={currentPage}
                      totalPages={totalPages}
                      onPageChange={handlePageChange}
                    />
                  </div>
                )}
              </>
            ) : !loading ? (
              <div className="text-center py-12">
                <p className="text-muted-foreground">
                  {searchQuery ? t('home.noMatchingArchives') : t('home.noArchives')}
                </p>
              </div>
            ) : null}
          </section>
        </main>
      </div>
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
