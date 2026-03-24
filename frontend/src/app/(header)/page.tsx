'use client';

import { ArchiveCard } from '@/components/archive/ArchiveCard';
import { ArchiveGrid } from '@/components/archive/ArchiveGrid';
import { BatchEditDialog, type BatchEditPayload } from '@/components/archive/BatchEditDialog';
import { TankoubonCard } from '@/components/tankoubon/TankoubonCard';
import { Pagination } from '@/components/ui/pagination';
import { Skeleton } from '@/components/ui/skeleton';
import { Spinner } from '@/components/ui/spinner';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogBody, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { MobileBottomNav } from '@/components/layout/MobileBottomNav';
import { AppSidebarNav } from '@/components/layout/AppSidebarNav';
import { SearchSidebar } from '@/components/layout/SearchSidebar';
import { ArchiveService } from '@/lib/services/archive-service';
import { CategoryService, type Category } from '@/lib/services/category-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { PluginService } from '@/lib/services/plugin-service';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { Archive } from '@/types/archive';
import { Tankoubon } from '@/types/tankoubon';
import { appEvents, AppEvents } from '@/lib/utils/events';
import { Check, Download, Heart, Pencil, RotateCcw, Trash2, X, ChevronRight, RefreshCw } from 'lucide-react';
import { useState, useEffect, useCallback, Suspense, useRef, useMemo } from 'react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useDebounce, useGridColumnCount, useWindowSize } from '@/hooks/common-hooks';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { logger } from '@/lib/utils/logger';
import {
  DEFAULT_SEARCH_SORT_BY,
  normalizeSearchSortBy,
} from '@/lib/utils/constants';

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

function isTankoubonItem(item: any): item is Tankoubon {
  return item && 'tankoubon_id' in item;
}

const DEFAULT_CARD_COVER_ASPECT_RATIO = 3 / 4;

function getScrollableCardWidth(viewportWidth: number): number {
  if (viewportWidth < 640) return 128;
  if (viewportWidth < 768) return 144;
  if (viewportWidth < 1024) return 160;
  if (viewportWidth < 1280) return 176;
  return 192;
}

function HomeScrollableCardRow({
  items,
  selectionMode,
  selectedArchiveIds,
  selectedTankoubonIds,
  enterSelectionMode,
  toggleArchiveSelect,
  toggleTankoubonSelect,
}: {
  items: (Archive | Tankoubon)[];
  selectionMode: boolean;
  selectedArchiveIds: Set<string>;
  selectedTankoubonIds: Set<string>;
  enterSelectionMode: () => void;
  toggleArchiveSelect: (id: string, selected: boolean) => void;
  toggleTankoubonSelect: (id: string, selected: boolean) => void;
}) {
  const { width } = useWindowSize();
  const itemKeys = useMemo(() => items.map((item) => (
    isTankoubonItem(item) ? `tankoubon:${item.tankoubon_id}` : `archive:${item.arcid}`
  )), [items]);
  const [aspectRatios, setAspectRatios] = useState<Record<string, number>>({});

  useEffect(() => {
    setAspectRatios((current) => {
      const next: Record<string, number> = {};
      for (const key of itemKeys) {
        if (current[key] != null) {
          next[key] = current[key];
        }
      }
      const currentKeys = Object.keys(current);
      if (currentKeys.length !== Object.keys(next).length) {
        return next;
      }
      for (const key of currentKeys) {
        if (!(key in next)) {
          return next;
        }
      }
      return current;
    });
  }, [itemKeys]);

  const reportAspectRatio = useCallback((key: string, aspectRatio: number) => {
    const normalized = Number.isFinite(aspectRatio) && aspectRatio > 0
      ? aspectRatio
      : DEFAULT_CARD_COVER_ASPECT_RATIO;

    setAspectRatios((current) => {
      if (Math.abs((current[key] ?? DEFAULT_CARD_COVER_ASPECT_RATIO) - normalized) < 0.001) {
        return current;
      }
      return {
        ...current,
        [key]: normalized,
      };
    });
  }, []);

  const sharedCoverHeight = useMemo(() => {
    if (items.length === 0) return undefined;
    const itemWidth = getScrollableCardWidth(width);
    let maxHeight = 0;

    for (const key of itemKeys) {
      const aspectRatio = aspectRatios[key] ?? DEFAULT_CARD_COVER_ASPECT_RATIO;
      maxHeight = Math.max(maxHeight, itemWidth / aspectRatio);
    }

    return Math.round(maxHeight);
  }, [aspectRatios, itemKeys, items.length, width]);

  return (
    <div className="flex items-start gap-4 overflow-x-auto pb-2 pr-2">
      {items.map((item, index) => {
        const itemKey = isTankoubonItem(item) ? `tankoubon:${item.tankoubon_id}` : `archive:${item.arcid}`;
        return (
          <div
            key={itemKey}
            className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 flex-shrink-0"
          >
            {isTankoubonItem(item) ? (
              <TankoubonCard
                tankoubon={item}
                priority={index < 2}
                disableContentVisibility
                coverHeight={sharedCoverHeight}
                selectable
                selectionMode={selectionMode}
                selected={selectedTankoubonIds.has(item.tankoubon_id)}
                onRequestEnterSelection={enterSelectionMode}
                onToggleSelect={(selected) => toggleTankoubonSelect(item.tankoubon_id, selected)}
                onCoverAspectRatioChange={(aspectRatio) => reportAspectRatio(itemKey, aspectRatio)}
              />
            ) : (
              <ArchiveCard
                archive={item}
                index={index}
                priority={index < 2}
                disableContentVisibility
                coverHeight={sharedCoverHeight}
                selectable
                selectionMode={selectionMode}
                selected={selectedArchiveIds.has(item.arcid)}
                onRequestEnterSelection={enterSelectionMode}
                onToggleSelect={(selected) => toggleArchiveSelect(item.arcid, selected)}
                onCoverAspectRatioChange={(aspectRatio) => reportAspectRatio(itemKey, aspectRatio)}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}

function HomePageContent() {
  const { t, language } = useLanguage();
  const { success: showSuccess, error: showError, info: showInfo } = useToast();
  const { confirm } = useConfirmContext();
  const searchParams = useSearchParams();
  const router = useRouter();
  const gridColumnCount = useGridColumnCount();
  const pageSize = 20;
  const categoryRowSize = Math.max(8, gridColumnCount * 2);
  const randomKey = `${categoryRowSize}:${language}`;
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
  const [sortBy, setSortBy] = useState(DEFAULT_SEARCH_SORT_BY);
  const [sortOrder, setSortOrder] = useState('desc');
  const [searchQuery, setSearchQuery] = useState('');
  const [newonly, setNewonly] = useState(false);
  const [untaggedonly, setUntaggedonly] = useState(false);
  const [favoriteonly, setFavoriteonly] = useState(false);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [groupByTanks, setGroupByTanks] = useState(true); // 默认启用Tankoubon分组
  const [categoryId, setCategoryId] = useState<string>('all');
  const [categories, setCategories] = useState<Category[]>([]);
  const [categoriesLoading, setCategoriesLoading] = useState(false);
  const [categoryRows, setCategoryRows] = useState<Record<string, (Archive | Tankoubon)[]>>({});
  const [categoryRowsLoading, setCategoryRowsLoading] = useState(false);
  const [categoryRowsRefreshKey, setCategoryRowsRefreshKey] = useState(0);
  const [isInitialized, setIsInitialized] = useState(false);
  const [filterDialogOpen, setFilterDialogOpen] = useState(false);
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedArchiveIds, setSelectedArchiveIds] = useState<Set<string>>(new Set());
  const [selectedTankoubonIds, setSelectedTankoubonIds] = useState<Set<string>>(new Set());
  const [batchEditOpen, setBatchEditOpen] = useState(false);
  const [batchEditApplying, setBatchEditApplying] = useState(false);
  const [metadataPlugins, setMetadataPlugins] = useState<Array<{ namespace: string; name: string }>>([]);
  const [batchActionRunning, setBatchActionRunning] = useState(false);
  const lastRandomKeyRef = useRef<string | null>(null);
  const archivesAbortRef = useRef<AbortController | null>(null);
  const archivesRequestIdRef = useRef(0);
  const categoryRowsRequestIdRef = useRef(0);

  // 读取URL参数
  const urlQuery = searchParams?.get('q') || '';
  const urlSortBy = normalizeSearchSortBy(searchParams?.get('sortby'), urlQuery ? 'relevance' : DEFAULT_SEARCH_SORT_BY);
  const urlSortOrder = searchParams?.get('order') || 'desc';
  const urlNewonly = searchParams?.get('newonly') === 'true';
  const urlUntaggedonly = searchParams?.get('untaggedonly') === 'true';
  const urlFavoriteonly = searchParams?.get('favoriteonly') === 'true';
  const urlDateFrom = searchParams?.get('date_from') || '';
  const urlDateTo = searchParams?.get('date_to') || '';
  const urlGroupByTanks = searchParams?.get('groupby_tanks') !== 'false'; // 默认为true
  const urlCategoryId = searchParams?.get('category_id') || 'all';
  const urlPage = parseInt(searchParams?.get('page') || '0', 10); // 从URL读取页码

  const effectiveCategoryId = searchQuery ? 'all' : categoryId;
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
      params.groupby_tanks = input.groupByTanks; // 添加Tankoubon分组参数
      params.lang = input.language; // 添加语言参数用于标签翻译

      const result = await ArchiveService.search(params, { signal: controller.signal });
      if (requestId !== archivesRequestIdRef.current) return;
      const data: (Archive | Tankoubon)[] = [...result.data];
      const totalRecordsAdjusted = result.recordsTotal;

      // NOTE: Previously we fetched ALL tankoubons to insert "name/tag-only matched" tankoubons
      // into the search result when groupby_tanks=true. This extra full-list request becomes
      // a major latency source on large libraries, so it was removed for performance.

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
      const archives = await ArchiveService.getRandom({ count: categoryRowSize, lang: language });
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
    setCategoryId(urlQuery ? 'all' : urlCategoryId);
    setCurrentPage(urlPage); // 从URL恢复页码

    // 标记为已初始化，避免在初始化期间同步URL
    setIsInitialized(true);
  }, [urlCategoryId, urlDateFrom, urlDateTo, urlFavoriteonly, urlGroupByTanks, urlNewonly, urlQuery, urlSortBy, urlSortOrder, urlUntaggedonly, urlPage]);

  // 同步状态到URL（仅在初始化完成后执行）
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
    if (typeof window !== 'undefined' && isInitialized && (searchQuery || categoryId !== 'all')) {
      fetchArchives(debouncedFetchInput);
    }
  }, [categoryId, debouncedFetchInput, fetchArchives, isInitialized, searchQuery]);

  useEffect(() => {
    if (!isInitialized) return;
    if (!searchQuery && categoryId === 'all') setLoading(false);
  }, [categoryId, isInitialized, searchQuery]);

  useEffect(() => {
    if (!batchEditOpen) return;
    let cancelled = false;
    (async () => {
      try {
        const plugins = await PluginService.getMetadataPlugins();
        if (cancelled) return;
        setMetadataPlugins(
          plugins
            .filter((plugin) => plugin.enabled)
            .map((plugin) => ({ namespace: plugin.namespace, name: plugin.name || plugin.namespace }))
        );
      } catch {
        if (!cancelled) setMetadataPlugins([]);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [batchEditOpen]);

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
      if (searchQuery || categoryId !== 'all') {
        fetchArchives(fetchInputRef.current);
      } else {
        setCategoryRowsRefreshKey((prev) => prev + 1);
      }
      if (!searchQuery) fetchRandomArchives({ force: true });
    };

    const handleArchivesRefresh = () => {
      if (searchQuery || categoryId !== 'all') {
        fetchArchives(fetchInputRef.current);
      } else {
        setCategoryRowsRefreshKey((prev) => prev + 1);
      }
      if (!searchQuery) fetchRandomArchives({ force: true });
    };

    const handleSearchReset = () => {
      // 重置所有搜索相关状态
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

    appEvents.on(AppEvents.UPLOAD_COMPLETED, handleUploadCompleted);
    appEvents.on(AppEvents.ARCHIVES_REFRESH, handleArchivesRefresh);
    appEvents.on(AppEvents.SEARCH_RESET, handleSearchReset);

    return () => {
      appEvents.off(AppEvents.UPLOAD_COMPLETED, handleUploadCompleted);
      appEvents.off(AppEvents.ARCHIVES_REFRESH, handleArchivesRefresh);
      appEvents.off(AppEvents.SEARCH_RESET, handleSearchReset);
    };
  }, [categoryId, fetchArchives, fetchRandomArchives, searchQuery]);

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
    return () => {
      cancelled = true;
    };
  }, []);

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
    const hasQueryParam = typeof params.query === 'string';
    if (hasQueryParam) {
      setSearchQuery(params.query ?? '');
      if (params.query) setCategoryId('all');
    }
    // 当有搜索查询且没有指定排序时，默认使用相关度排序
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
    // 移动端：应用筛选后自动关闭对话框
    setFilterDialogOpen(false);
  };

  const isSearchMode = Boolean(searchQuery);
  const showCategoryRows = !isSearchMode && categoryId === 'all';
  const showFilteredList = !showCategoryRows;

  const enabledCategories = useMemo(() => {
    return categories
      .filter((category) => category.enabled)
      .sort((a, b) => {
        if (a.sort_order !== b.sort_order) return a.sort_order - b.sort_order;
        return a.name.localeCompare(b.name);
      });
  }, [categories]);

  const visibleItemMap = useMemo(() => {
    const map = new Map<string, Archive | Tankoubon>();
    const pushItem = (item: Archive | Tankoubon) => {
      if (isTankoubonItem(item)) {
        map.set(`tankoubon:${item.tankoubon_id}`, item);
      } else {
        map.set(`archive:${item.arcid}`, item);
      }
    };

    archives.forEach((item) => pushItem(item as Archive | Tankoubon));
    randomArchives.forEach((item) => pushItem(item as Archive | Tankoubon));
    Object.values(categoryRows).forEach((items) => {
      items.forEach((item) => pushItem(item as Archive | Tankoubon));
    });

    return map;
  }, [archives, categoryRows, randomArchives]);

  const selectedArchives = useMemo(() => {
    return Array.from(selectedArchiveIds)
      .map((id) => visibleItemMap.get(`archive:${id}`))
      .filter((item): item is Archive => Boolean(item && !isTankoubonItem(item)));
  }, [selectedArchiveIds, visibleItemMap]);

  const selectedTankoubons = useMemo(() => {
    return Array.from(selectedTankoubonIds)
      .map((id) => visibleItemMap.get(`tankoubon:${id}`))
      .filter((item): item is Tankoubon => Boolean(item && isTankoubonItem(item)));
  }, [selectedTankoubonIds, visibleItemMap]);

  const selectedArchiveCount = selectedArchiveIds.size;
  const selectedTankoubonCount = selectedTankoubonIds.size;
  const selectedTotal = selectedArchiveCount + selectedTankoubonCount;
  const hasAnySelected = selectedTotal > 0;
  const canBatchDownload = selectedArchiveCount > 0;
  const allSelectedArchiveFavorited =
    selectedArchiveCount > 0 && selectedArchives.every((item) => Boolean(item.isfavorite));
  const allSelectedTankFavorited =
    selectedTankoubonCount > 0 && selectedTankoubons.every((item) => Boolean(item.isfavorite));
  const nextFavoriteState = !(allSelectedArchiveFavorited && allSelectedTankFavorited);
  const favoriteActionLabel = nextFavoriteState ? t('common.favorite') : t('common.unfavorite');
  const allSelectedArchiveIsNew =
    selectedArchiveCount > 0 && selectedArchives.every((item) => Boolean(item.isnew));

  const clearSelection = useCallback(() => {
    setSelectedArchiveIds(new Set());
    setSelectedTankoubonIds(new Set());
  }, []);

  const enterSelectionMode = useCallback(() => {
    setSelectionMode(true);
  }, []);

  const exitSelectionMode = useCallback(() => {
    setSelectionMode(false);
    setBatchEditOpen(false);
    clearSelection();
  }, [clearSelection]);

  const toggleArchiveSelect = useCallback((id: string, selected: boolean) => {
    setSelectedArchiveIds((prev) => {
      const next = new Set(prev);
      if (selected) next.add(id);
      else next.delete(id);
      return next;
    });
  }, []);

  const toggleTankoubonSelect = useCallback((id: string, selected: boolean) => {
    setSelectedTankoubonIds((prev) => {
      const next = new Set(prev);
      if (selected) next.add(id);
      else next.delete(id);
      return next;
    });
  }, []);

  const runBatchAction = useCallback(async (title: string, jobs: Array<() => Promise<void>>) => {
    if (jobs.length === 0) return;
    if (batchActionRunning) return;

    setBatchActionRunning(true);
    const settled = await Promise.allSettled(jobs.map((job) => job()));
    const successCount = settled.filter((item) => item.status === 'fulfilled').length;
    const failedCount = settled.length - successCount;
    if (failedCount > 0) {
      showError(`${title}: ${successCount}/${settled.length} ${t('home.batchDoneWithFailures')}`);
    } else {
      showSuccess(`${title}: ${successCount}/${settled.length}`);
    }
    appEvents.emit(AppEvents.ARCHIVES_REFRESH);
    setBatchActionRunning(false);
  }, [batchActionRunning, showError, showSuccess, t]);

  const mergeTags = useCallback((source: string[], add: string[], remove: string[]) => {
    const current = source.map((tag) => String(tag || '').trim()).filter(Boolean);
    const removeSet = new Set(remove.map((tag) => String(tag || '').trim()).filter(Boolean));
    const next = current.filter((tag) => !removeSet.has(tag));
    for (const tag of add.map((item) => String(item || '').trim()).filter(Boolean)) {
      if (!next.includes(tag)) next.push(tag);
    }
    return next;
  }, []);

  const applySummary = useCallback((current: string, mode: BatchEditPayload['summaryMode'], value: string) => {
    const rawCurrent = String(current || '');
    const rawValue = String(value || '');
    if (mode === 'clear') return '';
    if (mode === 'replace') return rawValue.trim();
    return rawCurrent.trim() ? `${rawCurrent}\n${rawValue}`.trim() : rawValue.trim();
  }, []);

  const applyBatchEdit = useCallback(async (payload: BatchEditPayload): Promise<boolean> => {
    if (!hasAnySelected || batchEditApplying) return false;
    if (payload.runMetadataPlugin && !payload.metadataPluginNamespace.trim()) {
      showError(t('archive.metadataPluginSelectRequired'));
      return false;
    }

    const applyToArchives = payload.scope !== 'tankoubon';
    const applyToTankoubons = payload.scope !== 'archive';
    const pluginArchiveCount = applyToArchives ? selectedArchiveIds.size : 0;
    const pluginTankCount = applyToTankoubons ? selectedTankoubonIds.size : 0;
    const pluginTargetCount = pluginArchiveCount + pluginTankCount;

    if (payload.runMetadataPlugin && pluginTargetCount > 0) {
      const pluginDisplay = payload.metadataPluginNamespace.trim();
      const confirmed = await confirm({
        title: t('home.batchMetadataPluginConfirmTitle'),
        description: t('home.batchMetadataPluginConfirmDescription')
          .replace('{plugin}', pluginDisplay)
          .replace('{count}', String(pluginTargetCount))
          .replace('{archives}', String(pluginArchiveCount))
          .replace('{tankoubons}', String(pluginTankCount)),
        confirmText: t('common.confirm'),
        cancelText: t('common.cancel'),
      });
      if (!confirmed) return false;
    }

    setBatchEditApplying(true);
    try {
      const archiveJobs: Array<() => Promise<void>> = applyToArchives
        ? Array.from(selectedArchiveIds).map((id) => async () => {
            if (payload.updateTitle || payload.updateSummary || payload.updateTags) {
              const metadata = await ArchiveService.getMetadata(id);
              const baseTitle = String(metadata.title || '');
              const nextTitle = payload.updateTitle
                ? `${payload.titlePrefix}${baseTitle}${payload.titleSuffix}`.trim()
                : baseTitle;
              const baseSummary = String(metadata.description || '');
              const nextSummary = payload.updateSummary
                ? applySummary(baseSummary, payload.summaryMode, payload.summaryValue)
                : baseSummary;
              const baseTags = Array.isArray(metadata.tags) ? metadata.tags : [];
              const nextTags = payload.updateTags
                ? mergeTags(baseTags, payload.tagsAdd, payload.tagsRemove)
                : baseTags;

              await ArchiveService.updateMetadata(id, {
                title: nextTitle || baseTitle,
                type: 0,
                description: nextSummary,
                tags: nextTags,
                assets: metadata.assets,
              });
            }

            if (payload.runMetadataPlugin) {
              await ArchiveService.runMetadataPluginForTarget(
                'archive',
                id,
                payload.metadataPluginNamespace,
                payload.metadataPluginParam,
                undefined,
                { writeBack: true }
              );
            }
          })
        : [];

      const tankoubonJobs: Array<() => Promise<void>> = applyToTankoubons
        ? Array.from(selectedTankoubonIds).map((id) => async () => {
            if (payload.updateTitle || payload.updateSummary || payload.updateTags) {
              const metadata = await TankoubonService.getMetadata(id);
              const baseTitle = String(metadata.title || '');
              const nextTitle = payload.updateTitle
                ? `${payload.titlePrefix}${baseTitle}${payload.titleSuffix}`.trim()
                : baseTitle;
              const baseSummary = String(metadata.description || '');
              const nextSummary = payload.updateSummary
                ? applySummary(baseSummary, payload.summaryMode, payload.summaryValue)
                : baseSummary;
              const baseTags = Array.isArray(metadata.tags) ? metadata.tags : [];
              const nextTags = payload.updateTags
                ? mergeTags(baseTags, payload.tagsAdd, payload.tagsRemove)
                : baseTags;

              await TankoubonService.updateMetadata(id, {
                title: nextTitle || baseTitle,
                type: 1,
                description: nextSummary,
                tags: nextTags,
                assets: metadata.assets,
                children: metadata.children,
              });
            }

            if (payload.runMetadataPlugin) {
              await ArchiveService.runMetadataPluginForTarget(
                'tankoubon',
                id,
                payload.metadataPluginNamespace,
                payload.metadataPluginParam,
                undefined,
                { writeBack: true }
              );
            }
          })
        : [];

      const jobs = [...archiveJobs, ...tankoubonJobs];
      const settled = await Promise.allSettled(jobs.map((job) => job()));
      const successCount = settled.filter((item) => item.status === 'fulfilled').length;
      const failedCount = settled.length - successCount;
      if (failedCount > 0) {
        showError(`${t('home.batchEditApplyResult')}: ${successCount}/${settled.length} ${t('home.batchDoneWithFailures')}`);
      } else {
        showSuccess(`${t('home.batchEditApplyResult')}: ${successCount}/${settled.length}`);
      }
      appEvents.emit(AppEvents.ARCHIVES_REFRESH);
      clearSelection();
      return true;
    } finally {
      setBatchEditApplying(false);
    }
  }, [
    confirm,
    applySummary,
    batchEditApplying,
    clearSelection,
    hasAnySelected,
    mergeTags,
    selectedArchiveIds,
    selectedTankoubonIds,
    showError,
    showSuccess,
    t,
  ]);

  const handleBatchDelete = useCallback(async () => {
    if (!hasAnySelected || batchActionRunning) return;
    const ok = await confirm({
      title: t('common.delete'),
      description: t('home.batchDeleteConfirm').replace('{count}', String(selectedTotal)),
      confirmText: t('common.delete'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    });
    if (!ok) return;

    const jobs: Array<() => Promise<void>> = [
      ...Array.from(selectedArchiveIds).map((id) => () => ArchiveService.deleteArchive(id)),
      ...Array.from(selectedTankoubonIds).map((id) => () => TankoubonService.deleteTankoubon(id)),
    ];
    await runBatchAction(t('common.delete'), jobs);
    clearSelection();
  }, [
    batchActionRunning,
    clearSelection,
    confirm,
    hasAnySelected,
    runBatchAction,
    selectedArchiveIds,
    selectedTankoubonIds,
    selectedTotal,
    t,
  ]);

  const handleBatchFavorite = useCallback(async () => {
    if (!hasAnySelected || batchActionRunning) return;
    const shouldFavorite = nextFavoriteState;
    const jobs: Array<() => Promise<void>> = [
      ...Array.from(selectedArchiveIds).map((id) => async () => {
        const ok = shouldFavorite
          ? await FavoriteService.addFavorite(id)
          : await FavoriteService.removeFavorite(id);
        if (!ok) throw new Error(`favorite archive failed: ${id}`);
      }),
      ...Array.from(selectedTankoubonIds).map((id) => async () => {
        const ok = shouldFavorite
          ? await FavoriteService.addTankoubonFavorite(id)
          : await FavoriteService.removeTankoubonFavorite(id);
        if (!ok) throw new Error(`favorite tankoubon failed: ${id}`);
      }),
    ];
    await runBatchAction(favoriteActionLabel, jobs);
  }, [
    batchActionRunning,
    favoriteActionLabel,
    hasAnySelected,
    nextFavoriteState,
    runBatchAction,
    selectedArchiveIds,
    selectedTankoubonIds,
  ]);

  const handleBatchReadStatus = useCallback(async () => {
    if (!canBatchDownload || batchActionRunning) return;
    const toRead = allSelectedArchiveIsNew;
    const title = toRead ? t('archive.markAsRead') : t('archive.markAsNew');
    const jobs: Array<() => Promise<void>> = Array.from(selectedArchiveIds).map((id) => {
      return () => (toRead ? ArchiveService.clearIsNew(id) : ArchiveService.setIsNew(id));
    });
    await runBatchAction(title, jobs);
  }, [
    allSelectedArchiveIsNew,
    batchActionRunning,
    canBatchDownload,
    runBatchAction,
    selectedArchiveIds,
    t,
  ]);

  const handleBatchDownload = useCallback(() => {
    if (!canBatchDownload) {
      showInfo(t('home.batchDownloadOnlyArchive'));
      return;
    }
    Array.from(selectedArchiveIds).forEach((id) => {
      window.open(ArchiveService.getDownloadUrl(id), '_blank');
    });
    showSuccess(
      t('home.batchDownloadStarted').replace('{count}', String(selectedArchiveIds.size))
    );
  }, [canBatchDownload, selectedArchiveIds, showInfo, showSuccess, t]);

  useEffect(() => {
    if (!showCategoryRows || enabledCategories.length === 0) {
      setCategoryRowsLoading(false);
      return;
    }

    const requestId = (categoryRowsRequestIdRef.current += 1);
    let cancelled = false;

    const loadCategoryRows = async () => {
      setCategoryRowsLoading(true);
      const rowData: Record<string, (Archive | Tankoubon)[]> = {};

      try {
        await Promise.all(
          enabledCategories.map(async (category) => {
            try {
              const params: any = {
                page: 1,
                pageSize: categoryRowSize,
                sortby: sortBy,
                order: sortOrder,
                groupby_tanks: groupByTanks,
                lang: language,
                category_id: category.catid,
              };

              if (newonly) params.newonly = true;
              if (untaggedonly) params.untaggedonly = true;
              if (favoriteonly) params.favoriteonly = true;
              if (dateFrom) params.date_from = dateFrom;
              if (dateTo) params.date_to = dateTo;

              const result = await ArchiveService.search(params);
              rowData[category.catid] = result.data || [];
            } catch (error) {
              rowData[category.catid] = [];
              logger.apiError(`fetch category row (${category.catid})`, error);
            }
          })
        );
      } finally {
        if (cancelled || requestId !== categoryRowsRequestIdRef.current) return;
        setCategoryRows(rowData);
        setCategoryRowsLoading(false);
      }
    };

    loadCategoryRows();
    return () => {
      cancelled = true;
    };
  }, [
    categoryRowSize,
    categoryRowsRefreshKey,
    dateFrom,
    dateTo,
    enabledCategories,
    favoriteonly,
    groupByTanks,
    language,
    newonly,
    showCategoryRows,
    sortBy,
    sortOrder,
    untaggedonly,
  ]);

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

  const handlePageChange = (page: number) => {
    setCurrentPage(page);
  };

  useEffect(() => {
    clearSelection();
  }, [clearSelection, currentPage, categoryId, searchQuery, sortBy, sortOrder, newonly, untaggedonly, favoriteonly, dateFrom, dateTo, groupByTanks]);

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

  const statsText = t('home.archivesCount')
    .replace('{count}', String(totalRecords))
    .replace('{page}', String(currentPage + 1))
    .replace('{totalPages}', String(totalPages));

  return (
    <div className="bg-background h-[calc(100dvh-var(--app-header-height,4rem))] overflow-hidden">
      {/* Use the real header height (CSS var) so the document never exceeds the viewport. */}
      <div className="flex h-full min-h-0">
        {/* 侧栏 - 桌面端显示 */}
        <aside className="hidden lg:block flex-shrink-0 border-r border-border w-72 min-h-0 pt-4">
          <AppSidebarNav
            mode="home"
            categories={categories}
            categoriesLoading={categoriesLoading}
            activeCategoryId={categoryId}
          />
        </aside>

        {/* 主内容区 - 独立滚动 */}
        {/* Reserve just enough space for the fixed mobile bottom nav (plus iOS safe-area). */}
        <main
          ref={mainScrollRef}
          className="flex-1 min-w-0 min-h-0 overflow-y-auto pb-[calc(env(safe-area-inset-bottom)+3.75rem)] lg:pb-2"
        >
          {/* Slightly tighter vertical padding so section headers don't feel "pushed down" on both desktop and mobile. */}
          <div className="px-4 pt-4 pb-2">
          {/* 随机推荐 - 仅在分类分行首页展示 */}
          {showCategoryRows && (
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
                selectionMode={selectionMode}
                selectedArchiveIds={selectedArchiveIds}
                selectedTankoubonIds={selectedTankoubonIds}
                enterSelectionMode={enterSelectionMode}
                toggleArchiveSelect={toggleArchiveSelect}
                toggleTankoubonSelect={toggleTankoubonSelect}
              />
            ) : !randomLoading ? (
              <div className="text-center py-12">
                <p className="text-muted-foreground">{t('home.noRecommendations')}</p>
              </div>
            ) : null}
          </section>
          )}

          {/* 筛选对话框 */}
          <Dialog open={filterDialogOpen} onOpenChange={setFilterDialogOpen}>
            <DialogContent className="w-full">
              <DialogHeader className="px-4 py-3 border-b">
                <DialogTitle>{t('home.advancedFilter')}</DialogTitle>
              </DialogHeader>
              <DialogBody>
                <SearchSidebar
                  noPadding
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

          {/* 分类分行展示 */}
          {showCategoryRows && (
            <section className="mb-10 space-y-8">
              {categoriesLoading ? (
                <div className="space-y-6">
                  {[0, 1].map((idx) => (
                    <div key={idx} className="space-y-3">
                      <Skeleton className="h-6 w-32" />
                      <div className="flex items-start gap-4 overflow-x-auto pb-2 pr-2">
                        {Array.from({ length: 6 }).map((_, i) => (
                          <div key={i} className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 flex-shrink-0 space-y-2">
                            <Skeleton className="aspect-[3/4] w-full" />
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
                  const rowItems = categoryRows[category.catid] || [];
                  const rowLoading = categoryRowsLoading && rowItems.length === 0;

                  return (
                    <div key={category.catid} className="space-y-3">
                      <div className="flex items-center justify-between gap-3">
                        <Link
                          href={buildCategoryUrl(category.catid)}
                          className="flex items-center gap-2 text-lg font-semibold hover:text-foreground"
                        >
                          {category.icon ? <span className="text-lg">{category.icon}</span> : null}
                          <span className="truncate">{category.name}</span>
                          <ChevronRight className="h-4 w-4 text-muted-foreground" />
                        </Link>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="gap-1"
                          asChild
                        >
                          <Link href={buildCategoryUrl(category.catid)}>
                            {t('home.viewMore')}
                            <ChevronRight className="h-4 w-4" />
                          </Link>
                        </Button>
                      </div>

                      {rowLoading ? (
                        <div className="flex items-start gap-4 overflow-x-auto pb-2 pr-2">
                          {Array.from({ length: Math.min(6, categoryRowSize) }).map((_, idx) => (
                            <div key={idx} className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 flex-shrink-0 space-y-2">
                              <Skeleton className="aspect-[3/4] w-full" />
                              <Skeleton className="h-4 w-full" />
                              <Skeleton className="h-4 w-2/3" />
                            </div>
                          ))}
                        </div>
                      ) : rowItems.length > 0 ? (
                        <HomeScrollableCardRow
                          items={rowItems}
                          selectionMode={selectionMode}
                          selectedArchiveIds={selectedArchiveIds}
                          selectedTankoubonIds={selectedTankoubonIds}
                          enterSelectionMode={enterSelectionMode}
                          toggleArchiveSelect={toggleArchiveSelect}
                          toggleTankoubonSelect={toggleTankoubonSelect}
                        />
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

          {/* 档案列表（搜索/筛选状态） */}
          {showFilteredList && (
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
                  <ArchiveGrid
                    archives={archives}
                    variant="home"
                    selectable
                    selectionMode={selectionMode}
                    selectedArchives={selectedArchiveIds}
                    selectedTankoubons={selectedTankoubonIds}
                    onToggleArchiveSelect={toggleArchiveSelect}
                    onToggleTankoubonSelect={toggleTankoubonSelect}
                    onRequestEnterSelection={enterSelectionMode}
                  />

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
          )}
          </div>
        </main>
      </div>

      <div
        className={[
          "fixed left-1/2 z-50 flex -translate-x-1/2 items-center gap-2 transition-all duration-250 ease-out",
          "bottom-[calc(env(safe-area-inset-bottom)+4.25rem)] lg:bottom-6",
          selectionMode ? "opacity-100 translate-y-0 pointer-events-auto" : "opacity-0 translate-y-4 pointer-events-none",
        ].join(" ")}
      >
        <div className="bg-background/95 backdrop-blur-sm border border-border rounded-full px-3 py-2 shadow-lg flex items-center gap-2">
          <span className="text-xs sm:text-sm whitespace-nowrap font-medium text-foreground px-1">
            {t('common.selected')}: {selectedTotal}
          </span>
        </div>

        <div className="bg-background/95 backdrop-blur-sm border border-border rounded-full p-1 shadow-lg flex items-center gap-1">
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3"
            disabled={!hasAnySelected || batchActionRunning || batchEditApplying}
            onClick={() => setBatchEditOpen(true)}
            title={t('common.edit')}
          >
            <Pencil className="mr-1 h-4 w-4" />
            <span className="hidden sm:inline">{t('common.edit')}</span>
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3"
            disabled={!hasAnySelected || batchActionRunning}
            onClick={() => void handleBatchFavorite()}
            title={favoriteActionLabel}
          >
            <Heart className="mr-1 h-4 w-4" />
            <span className="hidden sm:inline">{favoriteActionLabel}</span>
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3"
            disabled={!canBatchDownload || batchActionRunning}
            onClick={handleBatchDownload}
            title={t('archive.download')}
          >
            <Download className="mr-1 h-4 w-4" />
            <span className="hidden sm:inline">{t('archive.download')}</span>
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3"
            disabled={!canBatchDownload || batchActionRunning}
            onClick={() => void handleBatchReadStatus()}
            title={allSelectedArchiveIsNew ? t('archive.markAsRead') : t('archive.markAsNew')}
          >
            {allSelectedArchiveIsNew ? <Check className="mr-1 h-4 w-4" /> : <RotateCcw className="mr-1 h-4 w-4" />}
            <span className="hidden sm:inline">
              {allSelectedArchiveIsNew ? t('archive.markAsRead') : t('archive.markAsNew')}
            </span>
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="h-9 rounded-full px-3 text-destructive hover:text-destructive"
            disabled={!hasAnySelected || batchActionRunning}
            onClick={() => void handleBatchDelete()}
            title={t('common.delete')}
          >
            <Trash2 className="mr-1 h-4 w-4" />
            <span className="hidden sm:inline">{t('common.delete')}</span>
          </Button>
        </div>

        <div className="bg-background/95 backdrop-blur-sm border border-border rounded-full p-1 shadow-lg">
          <Button
            variant="ghost"
            size="sm"
            className="h-9 w-9 rounded-full p-0"
            onClick={exitSelectionMode}
            title={t('home.exitMultiSelect')}
          >
            <X className="h-4 w-4" />
          </Button>
        </div>
      </div>

      <BatchEditDialog
        open={batchEditOpen}
        onOpenChange={setBatchEditOpen}
        totalSelected={selectedTotal}
        selectedArchiveCount={selectedArchiveCount}
        selectedTankoubonCount={selectedTankoubonCount}
        metadataPluginOptions={metadataPlugins}
        applying={batchEditApplying}
        t={t}
        onApply={applyBatchEdit}
      />

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
