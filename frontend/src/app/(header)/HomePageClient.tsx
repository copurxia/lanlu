'use client';

import dynamic from 'next/dynamic';
import { HomeScrollableCardRow } from '@/components/home/HomeScrollableCardRow';
import { Pagination } from '@/components/ui/pagination';
import { Skeleton } from '@/components/ui/skeleton';
import { Spinner } from '@/components/ui/spinner';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogBody, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { ChannelFeedSkeleton, TweetFeedSkeleton } from '@/components/home/HomeFeedLoading';
import { ArchiveService } from '@/lib/services/archive-service';
import { CategoryService, type Category } from '@/lib/services/category-service';
import { RecommendationService } from '@/lib/services/recommendation-service';
import { Archive } from '@/types/archive';
import { Tankoubon } from '@/types/tankoubon';
import { appEvents, AppEvents } from '@/lib/utils/events';
import { ChevronRight, RefreshCw } from 'lucide-react';
import { startTransition, useState, useEffect, useCallback, Suspense, useRef, useMemo } from 'react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useDebounce, useGridColumnCount } from '@/hooks/common-hooks';
import { useHomeSelection } from '@/hooks/use-home-selection';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { logger } from '@/lib/utils/logger';
import { cn } from '@/lib/utils/utils';
import {
  DEFAULT_HOME_VIEW_MODE,
  DEFAULT_SEARCH_SORT_BY,
  HOME_VIEW_MODE_STORAGE_KEY,
  type HomeViewMode,
  normalizeHomeViewMode,
  normalizeSearchSortBy,
} from '@/lib/utils/constants';

// In-memory cache so random recommendations don't change when navigating away and back.
const randomArchivesCache = new Map<string, Array<Archive | Tankoubon>>();

function isAbortLikeError(err: any) {
  return (
    err?.name === 'AbortError' ||
    err?.name === 'CanceledError' ||
    err?.code === 'ERR_CANCELED' ||
    err?.message === 'canceled'
  );
}

type HomeViewSurface = 'archive-feed-continuous' | 'archive-feed-paged' | 'home-category-rows';

function resolveHomeViewSurface(mode: HomeViewMode, isHomeLanding: boolean): HomeViewSurface {
  if (mode === 'category-rows' && isHomeLanding) return 'home-category-rows';
  if (mode === 'masonry' || mode === 'tweet' || mode === 'channel') return 'archive-feed-continuous';
  return 'archive-feed-paged';
}

function getStoredHomeViewMode(): HomeViewMode {
  if (typeof window === 'undefined') {
    return DEFAULT_HOME_VIEW_MODE;
  }

  return normalizeHomeViewMode(window.localStorage.getItem(HOME_VIEW_MODE_STORAGE_KEY));
}

const ArchiveGrid = dynamic(
  () => import('@/components/archive/ArchiveGrid').then((m) => m.ArchiveGrid),
  {
    loading: () => (
      <div className="columns-2 gap-4 sm:columns-3 lg:columns-4 xl:columns-5 2xl:columns-6">
        {Array.from({ length: 10 }).map((_, idx) => (
          <div key={idx} className="mb-4 break-inside-avoid">
            <Skeleton className="aspect-3/4 w-full rounded-lg" />
          </div>
        ))}
      </div>
    ),
  }
);

const AppSidebarNav = dynamic(
  () => import('@/components/layout/AppSidebarNav').then((m) => m.AppSidebarNav),
  {
    loading: () => (
      <div className="space-y-6 px-4 pb-4">
        {Array.from({ length: 8 }).map((_, idx) => (
          <div key={idx} className="flex items-center gap-3 rounded-lg px-3 py-2">
            <Skeleton className="h-4 w-4 rounded-sm" />
            <Skeleton className="h-4 flex-1" />
          </div>
        ))}
      </div>
    ),
  }
);

const SearchSidebar = dynamic(
  () => import('@/components/layout/SearchSidebar').then((m) => m.SearchSidebar),
  {
    loading: () => <div className="space-y-4 p-4"><Skeleton className="h-10 w-full" /><Skeleton className="h-10 w-full" /><Skeleton className="h-24 w-full" /></div>,
  }
);

const HomeBatchActionBar = dynamic(
  () => import('@/components/home/HomeBatchActionBar').then((m) => m.HomeBatchActionBar),
  { loading: () => null }
);

const HomeMediaList = dynamic(
  () => import('@/components/home/HomeMediaList').then((m) => m.HomeMediaList),
  { loading: () => null }
);

const HomeMediaMasonry = dynamic(
  () => import('@/components/home/HomeMediaMasonry').then((m) => m.HomeMediaMasonry),
  { loading: () => null }
);

const HomeMediaChannel = dynamic(
  () => import('@/components/home/HomeMediaChannel').then((m) => m.HomeMediaChannel),
  { loading: () => <ChannelFeedSkeleton /> }
);

const HomeMediaTweet = dynamic(
  () => import('@/components/home/HomeMediaTweet').then((m) => m.HomeMediaTweet),
  { loading: () => <TweetFeedSkeleton /> }
);

const MobileBottomNav = dynamic(
  () => import('@/components/layout/MobileBottomNav').then((m) => m.MobileBottomNav),
  { loading: () => null }
);

function HomePageContent() {
  const { t, language } = useLanguage();
  const searchParams = useSearchParams();
  const router = useRouter();
  const gridColumnCount = useGridColumnCount();
  const pageSize = 20;
  const categoryRowSize = Math.max(8, gridColumnCount * 2);
  const randomKey = `${categoryRowSize}:${language}`;
  const mainScrollRef = useRef<HTMLElement | null>(null);
  const masonrySentinelRef = useRef<HTMLDivElement | null>(null);
  const lastPageRef = useRef<number | null>(null);
  const lastRandomKeyRef = useRef<string | null>(null);
  const archivesAbortRef = useRef<AbortController | null>(null);
  const archivesRequestIdRef = useRef(0);
  const categoryRowsRequestIdRef = useRef(0);

  // --- URL params ---
  const urlQuery = searchParams?.get('q') || '';
  const urlSortBy = normalizeSearchSortBy(searchParams?.get('sortby'), urlQuery ? 'relevance' : DEFAULT_SEARCH_SORT_BY);
  const urlSortOrder = searchParams?.get('order') || 'desc';
  const urlNewonly = searchParams?.get('newonly') === 'true';
  const urlUntaggedonly = searchParams?.get('untaggedonly') === 'true';
  const urlFavoriteonly = searchParams?.get('favoriteonly') === 'true';
  const urlDateFrom = searchParams?.get('date_from') || '';
  const urlDateTo = searchParams?.get('date_to') || '';
  const urlGroupByTanks = searchParams?.get('groupby_tanks') !== 'false';
  const urlCategoryId = searchParams?.get('category_id') || 'all';
  const urlPage = parseInt(searchParams?.get('page') || '0', 10);

  // --- Filter state ---
  const [homeViewMode, setHomeViewMode] = useState<HomeViewMode>(DEFAULT_HOME_VIEW_MODE);
  const [isInitialized, setIsInitialized] = useState(false);
  const [filterDialogOpen, setFilterDialogOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState(DEFAULT_SEARCH_SORT_BY);
  const [sortOrder, setSortOrder] = useState('desc');
  const [newonly, setNewonly] = useState(false);
  const [untaggedonly, setUntaggedonly] = useState(false);
  const [favoriteonly, setFavoriteonly] = useState(false);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [groupByTanks, setGroupByTanks] = useState(true);
  const [categoryId, setCategoryId] = useState<string>('all');

  // --- Data state ---
  const [archives, setArchives] = useState<Array<Archive | Tankoubon>>([]);
  const cachedRandomArchives =
    typeof window !== 'undefined' ? randomArchivesCache.get(randomKey) : undefined;
  const [randomArchives, setRandomArchives] = useState<Array<Archive | Tankoubon>>(() => cachedRandomArchives ?? []);
  const [loading, setLoading] = useState(true);
  const [autoLoadingMore, setAutoLoadingMore] = useState(false);
  const [randomLoading, setRandomLoading] = useState(() => !cachedRandomArchives);
  const [currentPage, setCurrentPage] = useState(0);
  const [totalPages, setTotalPages] = useState(0);
  const [totalRecords, setTotalRecords] = useState(0);
  const [categories, setCategories] = useState<Category[]>([]);
  const [categoriesLoading, setCategoriesLoading] = useState(false);
  const [categoryRows, setCategoryRows] = useState<Record<string, (Archive | Tankoubon)[]>>({});
  const [categoryRowsLoading, setCategoryRowsLoading] = useState(false);
  const [categoryRowsRefreshKey, setCategoryRowsRefreshKey] = useState(0);

  // --- Selection (extracted hook) ---
  const selection = useHomeSelection(() => ({
    archives,
    randomArchives,
    categoryRows,
  }));

  // Derived filter values
  const effectiveCategoryId = searchQuery ? 'all' : categoryId;
  const centeredFeedClassName =
    homeViewMode === 'tweet' || homeViewMode === 'channel'
      ? 'mx-auto w-full max-w-2xl'
      : homeViewMode === 'list'
        ? 'mx-auto w-full max-w-6xl'
        : '';

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
    categoryId: effectiveCategoryId,
    language,
  }), [currentPage, dateFrom, dateTo, effectiveCategoryId, favoriteonly, groupByTanks, language, newonly, searchQuery, sortBy, sortOrder, untaggedonly]);
  const fetchInputRef = useRef(fetchInput);
  useEffect(() => { fetchInputRef.current = fetchInput; }, [fetchInput]);

  const debouncedFetchInput = useDebounce(fetchInput, 250);

  const isSearchMode = Boolean(searchQuery);
  const isHomeLanding = !isSearchMode && categoryId === 'all';
  const homeViewSurface = resolveHomeViewSurface(homeViewMode, isHomeLanding);
  const showCategoryRowsView = isHomeLanding && homeViewMode === 'category-rows';
  const showArchiveFeed = !showCategoryRowsView;
  const isContinuousFeed = homeViewSurface === 'archive-feed-continuous';
  const hasMoreFeedPages = totalPages > 0 && currentPage + 1 < totalPages;
  const homeViewSurfaceRef = useRef<HomeViewSurface>(homeViewSurface);
  const isHomeLandingRef = useRef(isHomeLanding);
  const urlPageRef = useRef(urlPage);

  useEffect(() => {
    homeViewSurfaceRef.current = homeViewSurface;
  }, [homeViewSurface]);

  useEffect(() => {
    isHomeLandingRef.current = isHomeLanding;
  }, [isHomeLanding]);

  useEffect(() => {
    urlPageRef.current = urlPage;
  }, [urlPage]);

  // --- Data fetching ---
  const fetchArchives = useCallback(async (
    input: typeof fetchInput,
    options?: { append?: boolean }
  ) => {
    const requestId = (archivesRequestIdRef.current += 1);
    archivesAbortRef.current?.abort();
    const controller = new AbortController();
    archivesAbortRef.current = controller;
    const append = options?.append === true;

    try {
      setLoading(true);
      const params: any = {
        page: input.page + 1,
        pageSize,
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
      params.groupby_tanks = input.groupByTanks;
      params.lang = input.language;

      const result = await ArchiveService.search(params, { signal: controller.signal });
      if (requestId !== archivesRequestIdRef.current) return;
      const data: (Archive | Tankoubon)[] = [...result.data];
      const totalRecordsAdjusted = result.recordsTotal;

      if (requestId !== archivesRequestIdRef.current) return;
      setArchives((current) => {
        if (!append) return data;
        const merged = [...current];
        for (const item of data) {
          const isTank = item && 'tankoubon_id' in item;
          const alreadyExists = merged.some((existing) => {
            const exIsTank = existing && 'tankoubon_id' in existing;
            return isTank && exIsTank
              ? existing.tankoubon_id === item.tankoubon_id
              : !isTank && !exIsTank
                ? existing.arcid === item.arcid
                : false;
          });
          if (!alreadyExists) merged.push(item);
        }
        return merged;
      });
      setTotalRecords(totalRecordsAdjusted);
      setTotalPages(Math.ceil(totalRecordsAdjusted / pageSize));
    } catch (error) {
      if (isAbortLikeError(error)) return;
      logger.apiError('fetch archives', error);
    } finally {
      if (requestId === archivesRequestIdRef.current) {
        setLoading(false);
        setAutoLoadingMore(false);
      }
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
      const archives = await RecommendationService.getDiscover({ count: categoryRowSize, lang: language });
      setRandomArchives(archives);
      if (typeof window !== 'undefined') randomArchivesCache.set(randomKey, archives);
    } catch (error) {
      logger.apiError('fetch random archives', error);
      setRandomArchives([]);
      if (typeof window !== 'undefined') randomArchivesCache.set(randomKey, []);
    } finally {
      setRandomLoading(false);
    }
  }, [categoryRowSize, language, randomKey]);

  const trackDiscoverOpenReader = useCallback(async (itemType: any, itemId: string) => {
    try {
      await RecommendationService.recordInteraction({ scene: 'discover', item_type: itemType, item_id: itemId, interaction_type: 'open_reader' });
    } catch (error) {
      logger.apiError('track discover open_reader', error);
    }
  }, []);

  const trackDiscoverFavorite = useCallback(async (itemType: any, itemId: string) => {
    try {
      await RecommendationService.recordInteraction({ scene: 'discover', item_type: itemType, item_id: itemId, interaction_type: 'favorite' });
    } catch (error) {
      logger.apiError('track discover favorite', error);
    }
  }, []);

  // Cancel in-flight list request on unmount.
  useEffect(() => { return () => archivesAbortRef.current?.abort(); }, []);

  // Init from URL params
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
    setCategoryId(urlQuery ? 'all' : urlCategoryId);
    setIsInitialized(true);
  }, [urlCategoryId, urlDateFrom, urlDateTo, urlFavoriteonly, urlGroupByTanks, urlNewonly, urlQuery, urlSortBy, urlSortOrder, urlUntaggedonly]);

  useEffect(() => {
    setHomeViewMode(getStoredHomeViewMode());
  }, []);

  useEffect(() => {
    if (!isInitialized) return;
    if (homeViewMode !== 'list') return;
    setCurrentPage(urlPage);
  }, [homeViewMode, isInitialized, urlPage]);

  // Home view mode change listener
  useEffect(() => {
    const handleHomeViewModeChange = (nextMode?: HomeViewMode) => {
      const normalized = normalizeHomeViewMode(nextMode);
      const previousSurface = homeViewSurfaceRef.current;
      const nextSurface = resolveHomeViewSurface(normalized, isHomeLandingRef.current);

      setHomeViewMode(normalized);
      setAutoLoadingMore(false);

      if (previousSurface !== nextSurface) {
        if (nextSurface === 'home-category-rows') {
          archivesAbortRef.current?.abort();
          setArchives([]);
          setCurrentPage(0);
          setLoading(false);
        } else {
          setLoading(true);
          setArchives([]);
          setCurrentPage(nextSurface === 'archive-feed-paged' && normalized === 'list' ? urlPageRef.current : 0);
        }
      }

      if (typeof window !== 'undefined') {
        window.localStorage.setItem(HOME_VIEW_MODE_STORAGE_KEY, normalized);
      }
    };
    appEvents.on(AppEvents.HOME_VIEW_MODE_CHANGE, handleHomeViewModeChange);
    return () => appEvents.off(AppEvents.HOME_VIEW_MODE_CHANGE, handleHomeViewModeChange);
  }, []);

  // Sync state to URL
  useEffect(() => {
    if (!isInitialized) return;
    const params = new URLSearchParams();
    if (searchQuery) params.set('q', searchQuery);
    if (sortBy !== DEFAULT_SEARCH_SORT_BY) params.set('sortby', sortBy);
    if (sortOrder !== 'desc') params.set('order', sortOrder);
    if (newonly) params.set('newonly', 'true');
    if (untaggedonly) params.set('untaggedonly', 'true');
    if (favoriteonly) params.set('favoriteonly', 'true');
    if (dateFrom) params.set('date_from', dateFrom);
    if (dateTo) params.set('date_to', dateTo);
    if (!searchQuery && categoryId && categoryId !== 'all') params.set('category_id', categoryId);
    params.set('groupby_tanks', groupByTanks ? 'true' : 'false');
    if (!isContinuousFeed && currentPage > 0) params.set('page', currentPage.toString());

    const queryString = params.toString();
    const newUrl = queryString ? `/?${queryString}` : '/';
    if (typeof window !== 'undefined') {
      const currentUrl = `${window.location.pathname}${window.location.search}`;
      if (currentUrl !== newUrl) router.replace(newUrl);
      return;
    }
    router.replace(newUrl);
  }, [categoryId, currentPage, dateFrom, dateTo, favoriteonly, groupByTanks, isContinuousFeed, isInitialized, newonly, router, searchQuery, sortBy, sortOrder, untaggedonly]);

  // Fetch archives on filter change
  useEffect(() => {
    if (typeof window !== 'undefined' && isInitialized && showArchiveFeed) {
      fetchArchives(debouncedFetchInput, {
        append: isContinuousFeed && debouncedFetchInput.page > 0,
      });
    }
  }, [debouncedFetchInput, fetchArchives, isContinuousFeed, isInitialized, showArchiveFeed]);

  useEffect(() => {
    if (!isInitialized) return;
    if (!showArchiveFeed) setLoading(false);
  }, [isInitialized, showArchiveFeed]);

  // Load metadata plugins when batch edit opens
  useEffect(() => {
    if (!selection.batchEditOpen) return;
    selection.loadMetadataPlugins();
  }, [selection.batchEditOpen]); // eslint-disable-line react-hooks/exhaustive-deps

  // Random recommendations for category-rows view
  useEffect(() => {
    if (typeof window === 'undefined' || !isInitialized) return;
    if (!showCategoryRowsView) return;
    if (lastRandomKeyRef.current === randomKey) return;
    lastRandomKeyRef.current = randomKey;
    const cached = randomArchivesCache.get(randomKey);
    if (cached) {
      setRandomArchives(cached);
      setRandomLoading(false);
      return;
    }
    setRandomArchives([]);
    fetchRandomArchives();
  }, [fetchRandomArchives, isInitialized, randomKey, showCategoryRowsView]);

  // Event listeners: upload completed, archives refresh, search reset
  const refreshAllData = useCallback(() => {
    if (showArchiveFeed) {
      if (isContinuousFeed) {
        setAutoLoadingMore(false);
        setArchives([]);
        setCurrentPage(0);
        if (fetchInputRef.current.page === 0) {
          fetchArchives({ ...fetchInputRef.current, page: 0 }, { append: false });
        }
      } else {
        fetchArchives(fetchInputRef.current, { append: false });
      }
    } else {
      setCategoryRowsRefreshKey((prev) => prev + 1);
    }
    if (!searchQuery && homeViewMode === 'category-rows') fetchRandomArchives({ force: true });
  }, [fetchArchives, fetchRandomArchives, isContinuousFeed, homeViewMode, searchQuery, showArchiveFeed]);

  useEffect(() => {
    const handleSearchReset = () => {
      setSearchQuery('');
      setSortBy(DEFAULT_SEARCH_SORT_BY);
      setSortOrder('desc');
      setNewonly(false);
      setUntaggedonly(false);
      setFavoriteonly(false);
      setDateFrom('');
      setDateTo('');
      setGroupByTanks(true);
      setCurrentPage(0);
    };
    appEvents.on(AppEvents.UPLOAD_COMPLETED, refreshAllData);
    appEvents.on(AppEvents.ARCHIVES_REFRESH, refreshAllData);
    appEvents.on(AppEvents.SEARCH_RESET, handleSearchReset);
    return () => {
      appEvents.off(AppEvents.UPLOAD_COMPLETED, refreshAllData);
      appEvents.off(AppEvents.ARCHIVES_REFRESH, refreshAllData);
      appEvents.off(AppEvents.SEARCH_RESET, handleSearchReset);
    };
  }, [refreshAllData]);

  // Load categories
  useEffect(() => {
    let cancelled = false;
    const loadCategories = async () => {
      try {
        setCategoriesLoading(true);
        const cats = await CategoryService.getAllCategories();
        if (cancelled) return;
        setCategories(cats);
      } catch (error) {
        if (!cancelled) logger.apiError('fetch categories', error);
      } finally {
        if (!cancelled) setCategoriesLoading(false);
      }
    };
    if (typeof window !== 'undefined') loadCategories();
    return () => { cancelled = true; };
  }, []);

  // Filter dialog
  useEffect(() => {
    const handleFilterOpen = () => setFilterDialogOpen(true);
    appEvents.on(AppEvents.FILTER_OPEN, handleFilterOpen);
    return () => appEvents.off(AppEvents.FILTER_OPEN, handleFilterOpen);
  }, []);

  const handleSearch = useCallback((params: {
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
    const hasQueryParam = typeof params.query === 'string';
    if (hasQueryParam) {
      setSearchQuery(params.query ?? '');
      if (params.query) setCategoryId('all');
    }
    if (params.sortBy) {
      setSortBy(normalizeSearchSortBy(params.sortBy, DEFAULT_SEARCH_SORT_BY));
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
    if (!params.query && 'category_id' in params) setCategoryId(params.category_id || 'all');
    setCurrentPage(0);
    setFilterDialogOpen(false);
  }, []);

  const enabledCategories = useMemo(() => {
    return categories
      .filter((category) => category.enabled)
      .sort((a, b) => {
        if (a.sort_order !== b.sort_order) return a.sort_order - b.sort_order;
        return a.name.localeCompare(b.name);
      });
  }, [categories]);

  // Category rows
  useEffect(() => {
    if (!showCategoryRowsView || enabledCategories.length === 0) {
      setCategoryRowsLoading(false);
      return;
    }
    const requestId = (categoryRowsRequestIdRef.current += 1);
    let cancelled = false;
    const loadCategoryRows = async () => {
      setCategoryRowsLoading(true);
      const rowData: Record<string, (Archive | Tankoubon)[]> = {};
      const categoryIds = enabledCategories.map((c) => String(c.id || '').trim()).filter(Boolean);
      try {
        for (const cid of categoryIds) rowData[cid] = [];
        if (categoryIds.length > 0) {
          const params: any = {
            page: 1, pageSize: categoryRowSize, sortby: sortBy, order: sortOrder,
            groupby_tanks: groupByTanks, lang: language, category_ids: categoryIds.join(','), aggregate_by: 'category',
          };
          if (newonly) params.newonly = true;
          if (untaggedonly) params.untaggedonly = true;
          if (favoriteonly) params.favoriteonly = true;
          if (dateFrom) params.date_from = dateFrom;
          if (dateTo) params.date_to = dateTo;
          const result = await ArchiveService.search(params);
          for (const group of result.groups ?? []) {
            if (!group.category_id) continue;
            rowData[group.category_id] = group.data || [];
          }
        }
      } catch (error) {
        logger.apiError('fetch category rows aggregate', error);
      } finally {
        if (cancelled || requestId !== categoryRowsRequestIdRef.current) return;
        setCategoryRows(rowData);
        setCategoryRowsLoading(false);
      }
    };
    loadCategoryRows();
    return () => { cancelled = true; };
  }, [categoryRowSize, categoryRowsRefreshKey, dateFrom, dateTo, enabledCategories, favoriteonly, groupByTanks, language, newonly, showCategoryRowsView, sortBy, sortOrder, untaggedonly]);

  const buildCategoryUrl = useCallback((nextCategoryId: string) => {
    const params = new URLSearchParams();
    if (searchQuery) params.set('q', searchQuery);
    if (sortBy !== DEFAULT_SEARCH_SORT_BY) params.set('sortby', sortBy);
    if (sortOrder !== 'desc') params.set('order', sortOrder);
    if (newonly) params.set('newonly', 'true');
    if (untaggedonly) params.set('untaggedonly', 'true');
    if (favoriteonly) params.set('favoriteonly', 'true');
    if (dateFrom) params.set('date_from', dateFrom);
    if (dateTo) params.set('date_to', dateTo);
    if (!searchQuery && nextCategoryId && nextCategoryId !== 'all') params.set('category_id', nextCategoryId);
    params.set('groupby_tanks', groupByTanks ? 'true' : 'false');
    const queryString = params.toString();
    return queryString ? `/?${queryString}` : '/';
  }, [dateFrom, dateTo, favoriteonly, groupByTanks, newonly, searchQuery, sortBy, sortOrder, untaggedonly]);

  // Clear selection on filter/view change
  useEffect(() => {
    selection.clearSelection();
  }, [selection.clearSelection, categoryId, searchQuery, sortBy, sortOrder, newonly, untaggedonly, favoriteonly, dateFrom, dateTo, groupByTanks, homeViewMode]);

  useEffect(() => {
    if (isContinuousFeed) return;
    selection.clearSelection();
  }, [selection.clearSelection, currentPage, isContinuousFeed]);

  // Scroll to top on page change
  useEffect(() => {
    if (!isInitialized || isContinuousFeed) return;
    const prev = lastPageRef.current;
    lastPageRef.current = currentPage;
    if (prev === null || prev === currentPage) return;
    const reduceMotion =
      typeof window !== 'undefined' &&
      typeof window.matchMedia === 'function' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    mainScrollRef.current?.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' });
  }, [currentPage, isContinuousFeed, isInitialized]);

  const statsText = t('home.archivesCount')
    .replace('{count}', String(totalRecords))
    .replace('{page}', String(currentPage + 1))
    .replace('{totalPages}', String(totalPages));

  // Infinite scroll observer
  useEffect(() => {
    if (!isContinuousFeed) return;
    if (!masonrySentinelRef.current || !mainScrollRef.current) return;
    if (loading || autoLoadingMore) return;
    if (!hasMoreFeedPages) return;

    const sentinel = masonrySentinelRef.current;
    const root = mainScrollRef.current;
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        setAutoLoadingMore(true);
        startTransition(() => { setCurrentPage((page) => page + 1); });
      },
      { root, rootMargin: '0px 0px 640px 0px', threshold: 0 },
    );
    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [autoLoadingMore, currentPage, hasMoreFeedPages, isContinuousFeed, loading]);

  // Selection prop bag for child components
  const selectionProps = useMemo(() => ({
    selectionMode: selection.selectionMode,
    selectedArchiveIds: selection.selectedArchiveIds,
    selectedTankoubonIds: selection.selectedTankoubonIds,
    onRequestEnterSelection: selection.enterSelectionMode,
    onToggleArchiveSelect: selection.toggleArchiveSelect,
    onToggleTankoubonSelect: selection.toggleTankoubonSelect,
  }), [selection.selectionMode, selection.selectedArchiveIds, selection.selectedTankoubonIds, selection.enterSelectionMode, selection.toggleArchiveSelect, selection.toggleTankoubonSelect]);

  return (
    <div className="bg-background h-[calc(100dvh-var(--app-header-height,4rem))] overflow-hidden">
      <div className="flex h-full min-h-0">
        <aside className="hidden lg:block shrink-0 border-r border-border w-72 min-h-0 pt-4">
          <AppSidebarNav
            mode="home"
            categories={categories}
            categoriesLoading={categoriesLoading}
            activeCategoryId={categoryId}
          />
        </aside>

        <main
          ref={mainScrollRef}
          className="flex-1 min-w-0 min-h-0 overflow-y-auto pb-[calc(env(safe-area-inset-bottom)+3.75rem)] lg:pb-2"
        >
          <div className="px-4 pt-4 pb-2">

          {/* Random recommendations */}
          {showCategoryRowsView && (
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
              <HomeScrollableCardRow
                items={randomArchives}
                {...selectionProps}
                onRecommendationOpenReader={trackDiscoverOpenReader}
                onRecommendationFavorite={trackDiscoverFavorite}
              />
            ) : !randomLoading ? (
              <div className="text-center py-12">
                <p className="text-muted-foreground">{t('home.noRecommendations')}</p>
              </div>
            ) : null}
          </section>
          )}

          {/* Filter dialog */}
          <Dialog open={filterDialogOpen} onOpenChange={setFilterDialogOpen}>
            <DialogContent className="w-full">
              <DialogHeader className="px-4 py-3 border-b">
                <DialogTitle>{t('home.advancedFilter')}</DialogTitle>
              </DialogHeader>
              <DialogBody>
                {filterDialogOpen ? (
                  <SearchSidebar
                    noPadding
                    onSearch={handleSearch}
                    loading={loading}
                    filters={{ sortBy, sortOrder, dateFrom, dateTo, newonly, untaggedonly, favoriteonly, groupByTanks, categoryId }}
                  />
                ) : null}
              </DialogBody>
            </DialogContent>
          </Dialog>

          {/* Category rows view */}
          {showCategoryRowsView && (
            <section className="mb-10 space-y-8">
              {categoriesLoading ? (
                <div className="space-y-6">
                  {[0, 1].map((idx) => (
                    <div key={idx} className="space-y-3">
                      <Skeleton className="h-6 w-32" />
                      <div className="flex items-start gap-4 overflow-x-auto pb-2 pr-2">
                        {Array.from({ length: 6 }).map((_, i) => (
                          <div key={i} className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 shrink-0 space-y-2">
                            <Skeleton className="aspect-3/4 w-full" />
                            <Skeleton className="h-4 w-full" />
                            <Skeleton className="h-4 w-2/3" />
                          </div>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              ) : enabledCategories.length > 0 ? (
                enabledCategories.map((category) => {
                  const rowItems = categoryRows[String(category.id)] || [];
                  const rowLoading = categoryRowsLoading && rowItems.length === 0;
                  return (
                    <div key={category.catid} className="space-y-3">
                      <div className="flex items-center justify-between gap-3">
                        <Link href={buildCategoryUrl(category.catid)} className="flex items-center gap-2 text-lg font-semibold hover:text-foreground">
                          {category.icon ? <span className="text-lg">{category.icon}</span> : null}
                          <span className="truncate">{category.name}</span>
                          <ChevronRight className="h-4 w-4 text-muted-foreground" />
                        </Link>
                        <Button variant="ghost" size="sm" className="gap-1" asChild>
                          <Link href={buildCategoryUrl(category.catid)}>
                            {t('home.viewMore')}
                            <ChevronRight className="h-4 w-4" />
                          </Link>
                        </Button>
                      </div>
                      {rowLoading ? (
                        <div className="flex items-start gap-4 overflow-x-auto pb-2 pr-2">
                          {Array.from({ length: Math.min(6, categoryRowSize) }).map((_, idx) => (
                            <div key={idx} className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 shrink-0 space-y-2">
                              <Skeleton className="aspect-3/4 w-full" />
                              <Skeleton className="h-4 w-full" />
                              <Skeleton className="h-4 w-2/3" />
                            </div>
                          ))}
                        </div>
                      ) : rowItems.length > 0 ? (
                        <HomeScrollableCardRow items={rowItems} {...selectionProps} />
                      ) : (
                        <div className="text-sm text-muted-foreground">{t('home.noArchives')}</div>
                      )}
                    </div>
                  );
                })
              ) : (
                <div className="text-sm text-muted-foreground">{t('home.noCategories')}</div>
              )}
            </section>
          )}

          {/* Archive feed (search/filter mode) */}
          {showArchiveFeed && (
            <section>
              <div className="flex flex-col gap-3 mb-4">
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
                          {sortBy === 'created_at' && t('home.createdAt')}
                          {sortBy === 'release_at' && t('home.releaseAt')}
                          {sortBy === 'updated_at' && t('home.updatedAt')}
                          {sortBy === 'title' && t('home.titleSort')}
                          {sortBy === 'relevance' && t('home.relevance')}
                          {sortBy === 'pagecount' && t('home.pageCount')}
                          {sortBy === '_default' && t('settings.smartFilterDefault')}
                        </SelectValue>
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="relevance">{t('home.relevance')}</SelectItem>
                        <SelectItem value="lastread">{t('home.lastRead')}</SelectItem>
                        <SelectItem value="created_at">{t('home.createdAt')}</SelectItem>
                        <SelectItem value="release_at">{t('home.releaseAt')}</SelectItem>
                        <SelectItem value="updated_at">{t('home.updatedAt')}</SelectItem>
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

              {archives.length > 0 ? (
                <>
                  <div className={centeredFeedClassName || undefined}>
                    {homeViewMode === 'masonry' ? (
                      <HomeMediaMasonry items={archives} {...selectionProps} />
                    ) : homeViewMode === 'list' ? (
                      <HomeMediaList items={archives} {...selectionProps} />
                    ) : homeViewMode === 'tweet' ? (
                      <HomeMediaTweet items={archives} {...selectionProps} />
                    ) : homeViewMode === 'channel' ? (
                      <HomeMediaChannel items={archives} {...selectionProps} />
                    ) : (
                      <ArchiveGrid
                        archives={archives} variant="home" selectable
                        selectedArchives={selection.selectedArchiveIds}
                        selectedTankoubons={selection.selectedTankoubonIds}
                        onToggleArchiveSelect={selection.toggleArchiveSelect}
                        onToggleTankoubonSelect={selection.toggleTankoubonSelect}
                        onRequestEnterSelection={selection.enterSelectionMode}
                      />
                    )}
                  </div>
                  <div className={cn('mt-4 flex items-center justify-between gap-3', centeredFeedClassName)}>
                    <div className="text-xs sm:text-sm text-muted-foreground min-w-0 flex-1 truncate" title={statsText}>
                      {statsText}
                    </div>
                    {showArchiveFeed && !isContinuousFeed && totalPages > 1 && (
                      <Pagination currentPage={currentPage} totalPages={totalPages} onPageChange={setCurrentPage} className="justify-end py-0" />
                    )}
                  </div>
                  {isContinuousFeed && hasMoreFeedPages && (
                    <div className={cn('mt-6 flex flex-col items-center justify-center gap-3', centeredFeedClassName)}>
                      <div ref={masonrySentinelRef} className="h-1 w-full" />
                      {homeViewMode === 'tweet' && (loading || autoLoadingMore) ? (
                        <TweetFeedSkeleton count={2} append />
                      ) : homeViewMode === 'channel' && (loading || autoLoadingMore) ? (
                        <ChannelFeedSkeleton count={2} append />
                      ) : (loading || autoLoadingMore) && (
                        <div className="flex items-center gap-2 text-sm text-muted-foreground">
                          <Spinner size="sm" />
                          <span>{t('common.loading')}</span>
                        </div>
                      )}
                    </div>
                  )}
                </>
              ) : !loading ? (
                <div className="text-center py-12">
                  <p className="text-muted-foreground">
                    {searchQuery ? t('home.noMatchingArchives') : t('home.noArchives')}
                  </p>
                </div>
              ) : homeViewMode === 'tweet' ? (
                <div className={centeredFeedClassName || undefined}><TweetFeedSkeleton /></div>
              ) : homeViewMode === 'channel' ? (
                <div className={centeredFeedClassName || undefined}><ChannelFeedSkeleton /></div>
              ) : homeViewMode === 'list' ? (
                <div className={cn('space-y-3', centeredFeedClassName)}>
                  {Array.from({ length: 4 }).map((_, idx) => (
                    <div key={idx} className="rounded-lg border bg-card p-3 sm:p-4">
                      <div className="flex gap-3 sm:gap-4">
                        <Skeleton className="h-24 w-16 shrink-0 rounded-md sm:h-28 sm:w-20" />
                        <div className="min-w-0 flex-1 space-y-2">
                          <Skeleton className="h-5 w-2/3" />
                          <Skeleton className="h-4 w-1/3" />
                          <Skeleton className="h-4 w-full" />
                          <Skeleton className="h-4 w-5/6" />
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="columns-2 gap-4 sm:columns-3 lg:columns-4 xl:columns-5 2xl:columns-6">
                  {Array.from({ length: 10 }).map((_, idx) => (
                    <div key={idx} className="mb-4 break-inside-avoid">
                      <Skeleton className="aspect-3/4 w-full rounded-lg" />
                    </div>
                  ))}
                </div>
              )}
            </section>
          )}
          </div>
        </main>
      </div>

      {(selection.selectionMode || selection.batchEditOpen) ? (
        <HomeBatchActionBar
          visible={selection.selectionMode}
          selectedTotal={selection.selectedTotal}
          selectedArchiveCount={selection.selectedArchiveCount}
          selectedTankoubonCount={selection.selectedTankoubonCount}
          hasAnySelected={selection.hasAnySelected}
          canBatchDownload={selection.canBatchDownload}
          batchActionRunning={selection.batchActionRunning}
          batchEditApplying={selection.batchEditApplying}
          favoriteActionLabel={selection.favoriteActionLabel}
          allSelectedArchiveIsNew={selection.allSelectedArchiveIsNew}
          batchEditOpen={selection.batchEditOpen}
          setBatchEditOpen={selection.setBatchEditOpen}
          metadataPlugins={selection.metadataPlugins}
          onExit={selection.exitSelectionMode}
          onEdit={selection.openBatchEdit}
          onFavorite={selection.handleBatchFavorite}
          onDownload={selection.handleBatchDownload}
          onReadStatus={selection.handleBatchReadStatus}
          onDelete={selection.handleBatchDelete}
          onApplyBatchEdit={selection.applyBatchEdit}
          t={t}
        />
      ) : null}

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
