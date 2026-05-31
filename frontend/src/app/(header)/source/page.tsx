'use client';

import { useEffect, useState, useCallback, useRef, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import {
  Search,
  Globe,
  Download,
  RefreshCw,
  ChevronLeft,
  ChevronRight,
  X,
  BookOpen,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Spinner } from '@/components/ui/spinner';
import { BaseMediaCard } from '@/components/ui/base-media-card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Skeleton } from '@/components/ui/skeleton';
import { useToast } from '@/hooks/use-toast';
import {
  SourcePluginService,
  type SourcePluginSummary,
  type SourceItem,
  type SourceBrowseResult,
  type SourceFilter,
} from '@/lib/services/source-plugin-service';
import { CategoryService, type Category } from '@/lib/services/category-service';
import { TaskPoolService } from '@/lib/services/taskpool-service';

function SourceMediaCard({
  item,
  onDownload,
  onToggleSelect,
  onRequestEnterSelection,
  selectionMode,
  selected,
  index = 0,
}: {
  item: SourceItem;
  onDownload?: (item: SourceItem) => void;
  onToggleSelect?: (item: SourceItem, selected: boolean) => void;
  onRequestEnterSelection?: () => void;
  selectionMode?: boolean;
  selected?: boolean;
  index?: number;
}) {
  const itemKey = `${item.source_namespace}:${item.remote_id}`;
  const cardRef = useRef<HTMLDivElement | null>(null);
  const [lazyCoverAssetId, setLazyCoverAssetId] = useState<number | undefined>(item.cover_asset_id);
  const [coverVisible, setCoverVisible] = useState(false);
  const coverAssetId = item.cover_asset_id ?? lazyCoverAssetId;
  const detailPath = item.kind === 'tankoubon'
    ? `/tankoubon?source=${encodeURIComponent(item.source_namespace)}&remote_id=${encodeURIComponent(item.remote_id)}`
    : `/archive?source=${encodeURIComponent(item.source_namespace)}&remote_id=${encodeURIComponent(item.remote_id)}`;
  const firstChild = item.kind === 'tankoubon'
    ? item.children?.find((child) => child.kind === 'archive')
    : undefined;
  const readerRemoteId = item.kind === 'archive' ? item.remote_id : firstChild?.remote_id;
  const readerNamespace = item.kind === 'archive' ? item.source_namespace : firstChild?.source_namespace;
  const readerPath = readerRemoteId && readerNamespace
    ? `/reader?source=${encodeURIComponent(readerNamespace)}&remote_id=${encodeURIComponent(readerRemoteId)}${item.kind === 'tankoubon' ? `&tankoubon=${encodeURIComponent(item.remote_id)}` : ''}`
    : detailPath;

  useEffect(() => {
    if (item.cover_asset_id || !item.cover) return;
    const element = cardRef.current;
    if (!element || typeof IntersectionObserver === 'undefined') {
      setCoverVisible(true);
      return;
    }

    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        setCoverVisible(true);
        observer.disconnect();
      }
    }, { rootMargin: '600px 0px' });
    observer.observe(element);
    return () => observer.disconnect();
  }, [item.cover, item.cover_asset_id, itemKey]);

  useEffect(() => {
    if (!coverVisible || item.cover_asset_id || !item.cover) return;

    let cancelled = false;
    SourcePluginService.coverAsset(item.source_namespace, item.remote_id, item.cover)
      .then((result) => {
        if (cancelled || !result.success || !result.data?.asset_id) return;
        setLazyCoverAssetId(result.data.asset_id);
      })
      .catch(() => {
        // Keep the text-first card visible; cover loading is best-effort.
      });

    return () => {
      cancelled = true;
    };
  }, [coverVisible, item.cover, item.cover_asset_id, item.remote_id, item.source_namespace]);

  return (
    <div ref={cardRef}>
    <BaseMediaCard
      id={itemKey}
      title={item.title || item.remote_id}
      thumbnailId={readerRemoteId || ''}
      thumbnailAssetId={coverAssetId}
      tags={(item.tags || []).join(', ')}
      summary={item.description || item.subtitle || ''}
      pagecount={item.page_count || item.reader?.page_count || 0}
      progress={0}
      isnew={false}
      isfavorite={false}
      type={item.kind}
      index={index}
      badge={item.kind === 'tankoubon' ? (
        <Badge className="bg-primary">
          <BookOpen className="w-3 h-3 mr-1" />
          合集
        </Badge>
      ) : undefined}
      extraBadge={item.kind === 'tankoubon' && item.children?.length ? (
        <Badge className="bg-black/70 text-white">
          {item.children.length} 档案
        </Badge>
      ) : undefined}
      detailsLabel="详情"
      pagesLabel={item.kind === 'tankoubon'
        ? `${item.children?.length || 0} 档案`
        : `${item.page_count || item.reader?.page_count || 0} 页`}
      detailPath={detailPath}
      readerPath={readerPath}
      onDownload={onDownload ? () => onDownload(item) : undefined}
      canDownload={Boolean(onDownload)}
      disableFavorite
      disableEdit
      disableDelete
      disableReadStatus
      selectable={Boolean(onToggleSelect)}
      selectionMode={selectionMode}
      selected={selected}
      onToggleSelect={(nextSelected) => onToggleSelect?.(item, nextSelected)}
      onRequestEnterSelection={onRequestEnterSelection}
    />
    </div>
  );
}

function SkeletonGrid() {
  return (
    <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-7 2xl:grid-cols-7 3xl:grid-cols-8 4xl:grid-cols-9 5xl:grid-cols-10 gap-4">
      {Array.from({ length: 12 }).map((_, i) => (
        <div key={i} className="space-y-2">
          <Skeleton className="aspect-[2/3] rounded-lg" />
          <Skeleton className="h-4 w-3/4" />
        </div>
      ))}
    </div>
  );
}

function SourceHomeGrid({
  items,
  loading,
  onDownload,
  onToggleSelect,
  onRequestEnterSelection,
  selectionMode,
  selectedIds,
  hasSearched,
}: {
  items: SourceItem[];
  loading: boolean;
  onDownload?: (item: SourceItem) => void;
  onToggleSelect?: (item: SourceItem, selected: boolean) => void;
  onRequestEnterSelection?: () => void;
  selectionMode?: boolean;
  selectedIds?: Set<string>;
  hasSearched: boolean;
}) {
  if (loading) {
    return <SkeletonGrid />;
  }

  if (items.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center text-muted-foreground">
        <Globe className="h-12 w-12 mb-4 opacity-40" />
        <p className="text-sm">{hasSearched ? '没有找到结果' : '请选择在线源插件并搜索'}</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-7 2xl:grid-cols-7 3xl:grid-cols-8 4xl:grid-cols-9 5xl:grid-cols-10 gap-4">
      {items.map((item, idx) => {
        const itemKey = `${item.source_namespace}:${item.remote_id}`;
        return (
          <SourceMediaCard
            key={itemKey}
            item={item}
            onDownload={onDownload}
            onToggleSelect={onToggleSelect}
            onRequestEnterSelection={onRequestEnterSelection}
            selectionMode={selectionMode}
            selected={selectedIds?.has(itemKey)}
            index={idx}
          />
        );
      })}
    </div>
  );
}

function readInitialSourceUrlState(): {
  plugin: string;
  query: string;
  page: number;
  sort: string;
  filters: Record<string, unknown>;
} {
  if (typeof window === 'undefined') {
    return { plugin: '', query: '', page: 1, sort: 'date', filters: {} };
  }
  const params = new URLSearchParams(window.location.search);
  const page = Number.parseInt(params.get('page') || '1', 10);
  const filters: Record<string, unknown> = {};
  params.forEach((value, key) => {
    if (key.startsWith('f_')) {
      filters[key.slice(2)] = value;
    }
  });
  return {
    plugin: params.get('plugin') || '',
    query: params.get('q') || '',
    page: Number.isNaN(page) ? 1 : page,
    sort: params.get('sort') || 'date',
    filters,
  };
}

export default function SourcePage() {
  const { success: toastSuccess, error: toastError } = useToast();
  const toastSuccessRef = useRef(toastSuccess);
  const toastErrorRef = useRef(toastError);

  useEffect(() => {
    toastSuccessRef.current = toastSuccess;
    toastErrorRef.current = toastError;
  });

  const router = useRouter();
  const pathname = typeof window !== 'undefined' ? window.location.pathname : '';
  const initialUrlState = useMemo(() => readInitialSourceUrlState(), []);

  const [plugins, setPlugins] = useState<SourcePluginSummary[]>([]);
  const [selectedPlugin, setSelectedPlugin] = useState<string>(initialUrlState.plugin);
  const [loadingPlugins, setLoadingPlugins] = useState(true);

  const [items, setItems] = useState<SourceItem[]>([]);
  const [loadingItems, setLoadingItems] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [searchQuery, setSearchQuery] = useState(initialUrlState.query);
  const [currentPage, setCurrentPage] = useState(initialUrlState.page);
  const [hasNextPage, setHasNextPage] = useState(false);
  const [sortValue, setSortValue] = useState<string>(initialUrlState.sort);

  // Dynamic filter schema from plugin
  const [filterSchema, setFilterSchema] = useState<SourceFilter[] | null>(null);
  const [filterValues, setFilterValues] = useState<Record<string, unknown>>(initialUrlState.filters);

  // Sync URL params when state changes
  const syncUrlParams = useCallback((plugin: string, q: string, page: number, sort: string, filters: Record<string, unknown>) => {
    if (typeof window === 'undefined') return;
    const params = new URLSearchParams();
    if (plugin) params.set('plugin', plugin);
    if (q.trim()) params.set('q', q.trim());
    if (page > 1) params.set('page', String(page));
    if (sort && sort !== 'date') params.set('sort', sort);
    for (const [key, value] of Object.entries(filters)) {
      if (value !== undefined && value !== null && value !== '') {
        params.set(`f_${key}`, String(value));
      }
    }
    const qs = params.toString();
    const newUrl = qs ? `${pathname}?${qs}` : pathname;
    router.replace(newUrl, { scroll: false });
  }, [pathname, router]);

  const [downloadOpen, setDownloadOpen] = useState(false);
  const [downloadItem, setDownloadItem] = useState<SourceItem | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string>('');
  const [downloading, setDownloading] = useState(false);
  const [quickDownloadId, setQuickDownloadId] = useState<string>('');

  // Selection mode
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  const selectedItems = useMemo(() => {
    return items.filter((item) => selectedIds.has(`${item.source_namespace}:${item.remote_id}`));
  }, [items, selectedIds]);

  // Active download tracking for completion toasts
  interface ActiveDownload {
    taskId: number;
    title: string;
    kind: 'archive' | 'tankoubon';
  }
  const [activeDownloads, setActiveDownloads] = useState<ActiveDownload[]>([]);
  const subscribedTaskIdsRef = useRef<Set<number>>(new Set());

  useEffect(() => {
    const unsubscribes: (() => void)[] = [];
    for (const dl of activeDownloads) {
      if (subscribedTaskIdsRef.current.has(dl.taskId)) continue;
      subscribedTaskIdsRef.current.add(dl.taskId);
      const unsub = TaskPoolService.subscribeTask(dl.taskId, {
        onDone: (task) => {
          setActiveDownloads((prev) => prev.filter((d) => d.taskId !== dl.taskId));
          subscribedTaskIdsRef.current.delete(dl.taskId);
          if (task.status === 'completed') {
            let archiveId: string | undefined;
            let tankoubonId: string | undefined;
            try {
              const result = JSON.parse(task.result || '{}') as Record<string, unknown>;
              // 同时接受 string 和 number 类型的 ID，兼容不同序列化路径
              const rawAid = result.archive_id;
              if (typeof rawAid === 'string' && rawAid) archiveId = rawAid;
              else if (typeof rawAid === 'number' && rawAid > 0) archiveId = String(rawAid);
              const rawTid = result.tankoubon_id;
              if (typeof rawTid === 'string' && rawTid) tankoubonId = rawTid;
              else if (typeof rawTid === 'number' && rawTid > 0) tankoubonId = String(rawTid);
            } catch {
              // ignore parse errors
            }
            const localId = dl.kind === 'tankoubon' ? tankoubonId : archiveId;
            const openPath = dl.kind === 'tankoubon' && localId
              ? `/tankoubon?id=${encodeURIComponent(localId)}`
              : archiveId
                ? `/archive?id=${encodeURIComponent(archiveId)}`
                : undefined;
            toastSuccessRef.current(`"${dl.title}" 下载完成`, {
              action: openPath
                ? {
                    label: '打开',
                    onClick: () => router.push(openPath),
                  }
                : undefined,
            });
          } else if (task.status === 'failed') {
            toastErrorRef.current(`"${dl.title}" 下载失败：${task.message || '未知错误'}`);
          }
        },
        onError: () => {
          setActiveDownloads((prev) => prev.filter((d) => d.taskId !== dl.taskId));
          subscribedTaskIdsRef.current.delete(dl.taskId);
        },
      });
      unsubscribes.push(unsub);
    }
    return () => {
      for (const unsub of unsubscribes) {
        unsub();
      }
    };
  }, [activeDownloads, router]);

  useEffect(() => {
    SourcePluginService.listSourcePlugins()
      .then((data) => {
        const enabled = data.filter((p) => p.enabled);
        setPlugins(enabled);
        if (!initialUrlState.plugin && enabled.length > 0) {
          setSelectedPlugin(enabled[0].namespace);
        }
      })
      .catch(() => toastErrorRef.current('加载在线源插件列表失败'))
      .finally(() => setLoadingPlugins(false));
  }, [initialUrlState.plugin]);

  const handleBrowseResult = useCallback((result: SourceBrowseResult) => {
    if (result.success && result.data?.items) {
      setItems(result.data.items);
      setHasNextPage(result.data.next_page != null);
    } else {
      setItems([]);
      setHasNextPage(false);
      if (result.error) {
        toastErrorRef.current(result.error);
      }
    }
  }, []);

  const loadHome = useCallback(async (page: number = 1) => {
    if (!selectedPlugin) return;
    setLoadingItems(true);
    setHasSearched(true);
    const result = await SourcePluginService.home(selectedPlugin, { page, sort: sortValue, ...filterValues });
    handleBrowseResult(result);
    setLoadingItems(false);
  }, [selectedPlugin, sortValue, filterValues, handleBrowseResult]);

  const handleSearch = useCallback(async (page: number = 1) => {
    if (!selectedPlugin || !searchQuery.trim()) return;
    setLoadingItems(true);
    setHasSearched(true);
    const result = await SourcePluginService.search(selectedPlugin, searchQuery.trim(), page, { sort: sortValue, ...filterValues });
    handleBrowseResult(result);
    setLoadingItems(false);
  }, [selectedPlugin, searchQuery, sortValue, filterValues, handleBrowseResult]);

  const handleNextPage = useCallback(() => {
    const next = currentPage + 1;
    setCurrentPage(next);
    syncUrlParams(selectedPlugin, searchQuery, next, sortValue, filterValues);
    if (searchQuery.trim()) {
      handleSearch(next);
    } else {
      loadHome(next);
    }
  }, [currentPage, searchQuery, sortValue, filterValues, selectedPlugin, handleSearch, loadHome, syncUrlParams]);

  const handlePrevPage = useCallback(() => {
    if (currentPage <= 1) return;
    const prev = currentPage - 1;
    setCurrentPage(prev);
    syncUrlParams(selectedPlugin, searchQuery, prev, sortValue, filterValues);
    if (searchQuery.trim()) {
      handleSearch(prev);
    } else {
      loadHome(prev);
    }
  }, [currentPage, searchQuery, sortValue, filterValues, selectedPlugin, handleSearch, loadHome, syncUrlParams]);

  const prevPluginRef = useRef<string>('');

  useEffect(() => {
    if (!selectedPlugin) return;
    if (prevPluginRef.current !== selectedPlugin) {
      prevPluginRef.current = selectedPlugin;
      setCurrentPage(1);
      setHasNextPage(false);
      setItems([]);
      setSearchQuery('');
      setSortValue('date');
      setFilterValues({});
      setFilterSchema(null);
      setSelectionMode(false);
      setSelectedIds(new Set());
      syncUrlParams(selectedPlugin, '', 1, 'date', {});
      // Load filter schema for this plugin
      SourcePluginService.getFilters(selectedPlugin).then((res) => {
        if (res.success && res.filters && res.filters.length > 0) {
          setFilterSchema(res.filters);
        }
      }).catch(() => {});
      loadHome(1);
    }
  }, [selectedPlugin, loadHome, syncUrlParams]);

  const enterSelectionMode = useCallback(() => {
    setSelectionMode(true);
    setSelectedIds(new Set());
  }, []);

  const exitSelectionMode = useCallback(() => {
    setSelectionMode(false);
    setSelectedIds(new Set());
  }, []);

  const handleToggleSelect = useCallback((item: SourceItem, forceSelected?: boolean) => {
    const key = `${item.source_namespace}:${item.remote_id}`;
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (forceSelected === true) {
        next.add(key);
      } else if (forceSelected === false) {
        next.delete(key);
      } else if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  }, []);

  const handleSelectAll = useCallback(() => {
    setSelectedIds(new Set(items.map((i) => `${i.source_namespace}:${i.remote_id}`)));
  }, [items]);

  const handleBatchDownload = useCallback(async () => {
    if (selectedItems.length === 0) return;
    setQuickDownloadId('batch');
    const failed: string[] = [];
    const newDownloads: ActiveDownload[] = [];

    // Auto-download with first enabled category
    let defaultCatId = 0;
    try {
      const cats = await CategoryService.getAllCategories();
      const enabledCats = cats.filter((c) => c.enabled !== false);
      if (enabledCats.length === 0) {
        toastErrorRef.current('没有可用的分类，请先在设置中启用一个分类');
        setQuickDownloadId('');
        return;
      }
      defaultCatId = enabledCats[0].id;
    } catch {
      // pass
    }

    for (const item of selectedItems) {
      try {
        const dlResult = await SourcePluginService.download(
          item.source_namespace,
          item.remote_id,
          defaultCatId,
          item.kind
        );
        if (dlResult.success && dlResult.task_id) {
          newDownloads.push({
            taskId: dlResult.task_id,
            title: item.title || item.remote_id,
            kind: item.kind,
          });
        } else {
          failed.push(item.remote_id);
        }
      } catch {
        failed.push(item.remote_id);
      }
    }

    if (newDownloads.length > 0) {
      setActiveDownloads((prev) => [...prev, ...newDownloads]);
    }

    const total = selectedItems.length;
    if (failed.length === 0) {
      toastSuccessRef.current(`已创建 ${total} 个下载任务`);
    } else {
      toastSuccessRef.current(`已创建 ${total - failed.length} 个任务，${failed.length} 个失败`);
    }
    setQuickDownloadId('');
    exitSelectionMode();
  }, [selectedItems, exitSelectionMode]);

  const openDownloadDialog = async (item: SourceItem) => {
    setDownloadItem(item);
    setDownloadOpen(true);
    setCategories([]);
    setSelectedCategory('');
    try {
      const cats = await CategoryService.getAllCategories();
      const enabledCats = cats.filter((c) => c.enabled !== false);
      setCategories(enabledCats);
      if (enabledCats.length === 1) {
        setSelectedCategory(String(enabledCats[0].id));
      }
    } catch {
      toastErrorRef.current('加载分类列表失败');
    }
  };

  const handleQuickDownload = async (item: SourceItem) => {
    if (!selectedPlugin || quickDownloadId) return;
    setQuickDownloadId(`${item.source_namespace}:${item.remote_id}`);
    await openDownloadDialog(item);
    setQuickDownloadId('');
  };

  const handleConfirmDownload = async () => {
    if (!downloadItem || !selectedCategory) return;
    setDownloading(true);
    const result = await SourcePluginService.download(
      downloadItem.source_namespace,
      downloadItem.remote_id,
      Number(selectedCategory),
      downloadItem.kind
    );
    if (result.success && result.task_id) {
      toastSuccessRef.current('下载任务已创建');
      setActiveDownloads((prev) => [
        ...prev,
        {
          taskId: result.task_id!,
          title: downloadItem.title || downloadItem.remote_id,
          kind: downloadItem.kind,
        },
      ]);
      setDownloadOpen(false);
    } else {
      toastErrorRef.current(result.error || '创建下载任务失败');
    }
    setDownloading(false);
  };

  return (
    <div className="container mx-auto px-4 py-4 max-w-[1600px]">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">在线源</h1>
          <p className="text-sm text-muted-foreground mt-1">浏览在线归档源并一键下载到服务器</p>
        </div>
        {hasSearched && (
          <div className="flex items-center gap-2">
            {!selectionMode ? (
              <Button variant="outline" size="sm" onClick={enterSelectionMode} disabled={loadingItems || items.length === 0}>
                多选
              </Button>
            ) : (
              <Button variant="ghost" size="sm" onClick={exitSelectionMode}>
                <X className="h-4 w-4 mr-1" />
                取消
              </Button>
            )}
            <Button variant="outline" size="sm" onClick={() => loadHome(currentPage)} disabled={loadingItems}>
              <RefreshCw className={`h-4 w-4 mr-2 ${loadingItems ? 'animate-spin' : ''}`} />
              刷新
            </Button>
          </div>
        )}
      </div>

      <div className="flex flex-col gap-3 mb-6">
        <div className="flex flex-col sm:flex-row gap-3">
          <Select value={selectedPlugin} onValueChange={setSelectedPlugin} disabled={loadingPlugins}>
            <SelectTrigger className="w-full sm:w-[240px]">
              <SelectValue placeholder={loadingPlugins ? '加载中...' : '选择在线源'} />
            </SelectTrigger>
            <SelectContent>
              {plugins.map((p) => (
                <SelectItem key={p.namespace} value={p.namespace}>
                  {p.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

          <div className="flex-1 flex gap-2">
            <Input
              placeholder="搜索在线归档..."
              value={searchQuery}
              onChange={(e) => {
                setSearchQuery(e.target.value);
                syncUrlParams(selectedPlugin, e.target.value, currentPage, sortValue, filterValues);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  syncUrlParams(selectedPlugin, searchQuery, 1, sortValue, filterValues);
                  handleSearch(1);
                }
              }}
              className="flex-1"
            />
            <Button onClick={() => {
              syncUrlParams(selectedPlugin, searchQuery, 1, sortValue, filterValues);
              handleSearch(1);
            }} disabled={loadingItems || !selectedPlugin}>
              <Search className="h-4 w-4 mr-2" />
              搜索
            </Button>
          </div>
        </div>

        {/* Dynamic filter bar */}
        {filterSchema && filterSchema.length > 0 && (
          <div className="flex flex-wrap gap-2 items-center">
            {filterSchema.map((filter) => {
              const val = filterValues[filter.key];
              const applyFilter = (next: Record<string, unknown>) => {
                setFilterValues(next);
                syncUrlParams(selectedPlugin, searchQuery, 1, sortValue, next);
                setCurrentPage(1);
                if (searchQuery.trim()) {
                  handleSearch(1);
                } else {
                  loadHome(1);
                }
              };
              if (filter.type === 'tabs') {
                const current = String(val ?? '');
                return (
                  <div key={filter.key} className="flex items-center gap-1">
                    <span className="text-xs text-muted-foreground mr-1">{filter.label}</span>
                    <Button
                      variant={current === '' ? 'default' : 'outline'}
                      size="sm"
                      onClick={() => applyFilter({ ...filterValues, [filter.key]: '' })}
                    >
                      全部
                    </Button>
                    {filter.options?.map((opt) => (
                      <Button
                        key={opt.value}
                        variant={current === opt.value ? 'default' : 'outline'}
                        size="sm"
                        onClick={() => applyFilter({ ...filterValues, [filter.key]: opt.value })}
                      >
                        {opt.label}
                      </Button>
                    ))}
                  </div>
                );
              }
              if (filter.type === 'select') {
                return (
                  <Select
                    key={filter.key}
                    value={val === '' || val == null ? '_all' : String(val)}
                    onValueChange={(v) => applyFilter({ ...filterValues, [filter.key]: v === '_all' ? '' : v })}
                  >
                    <SelectTrigger className="w-auto min-w-[120px]">
                      <SelectValue placeholder={filter.label} />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="_all">全部</SelectItem>
                      {filter.options?.map((opt) => (
                        opt.value !== '' && (
                        <SelectItem key={opt.value} value={opt.value}>
                          {opt.label}
                        </SelectItem>
                        )
                      ))}
                    </SelectContent>
                  </Select>
                );
              }
              if (filter.type === 'multi-select') {
                const currentSet = new Set(
                  typeof val === 'string' && val.trim() !== '' ? val.split(',') : []
                );
                return (
                  <div key={filter.key} className="flex items-center gap-1 flex-wrap">
                    <span className="text-xs text-muted-foreground mr-1">{filter.label}</span>
                    {filter.options?.map((opt) => {
                      const active = currentSet.has(opt.value);
                      return (
                        <Button
                          key={opt.value}
                          variant={active ? 'default' : 'outline'}
                          size="sm"
                          onClick={() => {
                            const nextSet = new Set(currentSet);
                            if (active) {
                              nextSet.delete(opt.value);
                            } else {
                              nextSet.add(opt.value);
                            }
                            const nextVal = Array.from(nextSet).join(',');
                            applyFilter({ ...filterValues, [filter.key]: nextVal });
                          }}
                        >
                          {opt.label}
                        </Button>
                      );
                    })}
                  </div>
                );
              }
              if (filter.type === 'toggle') {
                const active = Boolean(val);
                return (
                  <Button
                    key={filter.key}
                    variant={active ? 'default' : 'outline'}
                    size="sm"
                    onClick={() => applyFilter({ ...filterValues, [filter.key]: active ? '' : '1' })}
                  >
                    {filter.label}
                  </Button>
                );
              }
              if (filter.type === 'text') {
                return (
                  <Input
                    key={filter.key}
                    placeholder={filter.label}
                    value={String(val ?? '')}
                    onChange={(e) => {
                      const next = { ...filterValues, [filter.key]: e.target.value };
                      setFilterValues(next);
                      syncUrlParams(selectedPlugin, searchQuery, currentPage, sortValue, next);
                    }}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        const next = { ...filterValues, [filter.key]: e.currentTarget.value };
                        applyFilter(next);
                      }
                    }}
                    className="w-[180px]"
                  />
                );
              }
              if (filter.type === 'range') {
                const [minVal = '', maxVal = ''] = typeof val === 'string' ? val.split(',') : [];
                return (
                  <div key={filter.key} className="flex items-center gap-1">
                    <span className="text-xs text-muted-foreground">{filter.label}</span>
                    <Input
                      type="number"
                      placeholder="最小"
                      value={minVal}
                      onChange={(e) => {
                        const next = { ...filterValues, [filter.key]: `${e.target.value},${maxVal}` };
                        setFilterValues(next);
                        syncUrlParams(selectedPlugin, searchQuery, currentPage, sortValue, next);
                      }}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          const next = { ...filterValues, [filter.key]: `${e.currentTarget.value},${maxVal}` };
                          applyFilter(next);
                        }
                      }}
                      className="w-[80px]"
                    />
                    <span className="text-muted-foreground">-</span>
                    <Input
                      type="number"
                      placeholder="最大"
                      value={maxVal}
                      onChange={(e) => {
                        const next = { ...filterValues, [filter.key]: `${minVal},${e.target.value}` };
                        setFilterValues(next);
                        syncUrlParams(selectedPlugin, searchQuery, currentPage, sortValue, next);
                      }}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          const next = { ...filterValues, [filter.key]: `${minVal},${e.currentTarget.value}` };
                          applyFilter(next);
                        }
                      }}
                      className="w-[80px]"
                    />
                  </div>
                );
              }
              return null;
            })}
          </div>
        )}
      </div>

      <SourceHomeGrid
        items={items}
        loading={loadingItems}
        onDownload={handleQuickDownload}
        onToggleSelect={handleToggleSelect}
        onRequestEnterSelection={enterSelectionMode}
        selectionMode={selectionMode}
        selectedIds={selectedIds}
        hasSearched={hasSearched}
      />

      {items.length > 0 && (
        <div className="flex items-center justify-center gap-3 mt-6">
          <Button
            variant="outline"
            size="sm"
            disabled={currentPage <= 1 || loadingItems}
            onClick={handlePrevPage}
          >
            <ChevronLeft className="h-4 w-4 mr-1" />
            上一页
          </Button>
          <span className="text-sm text-muted-foreground min-w-[3rem] text-center">
            第 {currentPage} 页
          </span>
          <Button
            variant="outline"
            size="sm"
            disabled={!hasNextPage || loadingItems}
            onClick={handleNextPage}
          >
            下一页
            <ChevronRight className="h-4 w-4 ml-1" />
          </Button>
        </div>
      )}

      <Dialog open={downloadOpen} onOpenChange={setDownloadOpen}>
        <DialogContent className="max-w-md p-0 gap-0">
          <DialogHeader className="p-6 pb-0">
            <DialogTitle>选择目标分类</DialogTitle>
            <DialogDescription>
              将 <span className="font-medium text-foreground">{downloadItem?.title || '归档'}</span> 下载到本地
            </DialogDescription>
          </DialogHeader>

          <div className="p-6 space-y-6">
            <div className="space-y-2">
              <label className="text-sm font-medium">目标分类</label>
              <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                <SelectTrigger>
                  <SelectValue placeholder="选择分类..." />
                </SelectTrigger>
                <SelectContent>
                  {categories
                    .filter((c) => c.enabled !== false)
                    .map((c) => (
                      <SelectItem key={c.id} value={String(c.id)}>
                        {c.name}
                      </SelectItem>
                    ))}
                </SelectContent>
              </Select>
            </div>

            <div className="flex items-center justify-end gap-3">
              <Button variant="ghost" size="sm" onClick={() => setDownloadOpen(false)} disabled={downloading}>
                取消
              </Button>
              <Button
                size="sm"
                onClick={handleConfirmDownload}
                disabled={downloading || !selectedCategory}
              >
                {downloading ? <Spinner className="h-4 w-4 mr-2" /> : <Download className="h-4 w-4 mr-2" />}
                确认下载
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Selection toolbar */}
      {selectionMode && (
        <div className="fixed bottom-6 left-1/2 z-50 -translate-x-1/2">
          <div className="flex items-center gap-3 rounded-full border bg-background/95 px-5 py-2.5 shadow-lg backdrop-blur-sm">
            <span className="text-sm font-medium min-w-[4rem] text-center">
              已选 {selectedIds.size}
            </span>
            <div className="h-5 w-px bg-border" />
            <Button
              variant="ghost"
              size="sm"
              className="h-8 px-3 text-xs"
              onClick={handleSelectAll}
            >
              全选
            </Button>
            <Button
              variant="secondary"
              size="sm"
              className="h-8 px-4 text-xs"
              disabled={selectedIds.size === 0 || quickDownloadId === 'batch'}
              onClick={handleBatchDownload}
            >
              {quickDownloadId === 'batch' ? (
                <Spinner className="h-3.5 w-3.5 mr-1.5" />
              ) : (
                <Download className="h-3.5 w-3.5 mr-1.5" />
              )}
              下载
            </Button>
            <div className="h-5 w-px bg-border" />
            <Button variant="ghost" size="sm" className="h-8 px-3 text-xs" onClick={exitSelectionMode}>
              <X className="h-3.5 w-3.5 mr-1" />
              取消
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
