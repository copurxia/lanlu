'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import { useRouter } from 'next/navigation';
import {
  Search,
  Globe,
  Download,
  RefreshCw,
  ChevronLeft,
  ChevronRight,
  Check,
  Square,
  X,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Spinner } from '@/components/ui/spinner';
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
  type SourceDetailResult,
  type SourceArchive,
} from '@/lib/services/source-plugin-service';
import { CategoryService, type Category } from '@/lib/services/category-service';

function SourceItemCard({
  item,
  onClick,
  onDownload,
  onToggleSelect,
  isDownloading,
  selectionMode,
  selected,
  index = 0,
}: {
  item: SourceItem;
  onClick: (item: SourceItem) => void;
  onDownload?: (item: SourceItem) => void;
  onToggleSelect?: (item: SourceItem) => void;
  isDownloading?: boolean;
  selectionMode?: boolean;
  selected?: boolean;
  index?: number;
}) {
  const shouldAnimate = index < 24;
  const delay = shouldAnimate ? Math.min(index * 50, 500) : 0;
  const [menuOpen, setMenuOpen] = useState(false);
  const [menuPos, setMenuPos] = useState({ x: 0, y: 0 });

  useEffect(() => {
    if (!menuOpen) return;
    const close = () => setMenuOpen(false);
    window.addEventListener('click', close, { once: true });
    return () => window.removeEventListener('click', close);
  }, [menuOpen]);

  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    if (selectionMode) {
      onToggleSelect?.(item);
      return;
    }
    if (!onDownload) return;
    setMenuPos({ x: e.clientX, y: e.clientY });
    setMenuOpen(true);
  };

  const handleClick = () => {
    if (selectionMode) {
      onToggleSelect?.(item);
      return;
    }
    onClick(item);
  };

  return (
    <>
      <div
        className={[
          'group motion-reduce:animate-none',
          shouldAnimate ? 'motion-safe:animate-archive-card-in' : '',
          selectionMode ? 'cursor-pointer' : 'cursor-pointer',
        ].filter(Boolean).join(' ')}
        style={{
          animationDelay: shouldAnimate ? `${delay}ms` : undefined,
          contentVisibility: 'auto',
          containIntrinsicSize: '220px 420px',
        }}
        onClick={handleClick}
        onContextMenu={handleContextMenu}
      >
        <Card className={[
          'overflow-hidden bg-transparent transition-shadow dark:bg-transparent',
          selected ? 'ring-2 ring-primary' : 'hover:shadow-lg',
        ].filter(Boolean).join(' ')}>
          <div className="bg-muted relative aspect-[2/3]">
            {item.cover ? (
              <img
                src={item.cover}
                alt={item.title}
                loading="lazy"
                className="absolute inset-0 h-full w-full object-cover select-none"
                style={{
                  WebkitTouchCallout: 'none',
                  WebkitUserSelect: 'none',
                  userSelect: 'none',
                }}
                onContextMenu={(e) => e.preventDefault()}
                onDragStart={(e) => e.preventDefault()}
              />
            ) : (
              <div className="absolute inset-0 flex items-center justify-center">
                <Globe className="h-10 w-10 text-muted-foreground/40" />
              </div>
            )}

            {/* Selection checkbox */}
            {selectionMode && (
              <div className="absolute top-2 left-2 z-30">
                <div
                  className={[
                    'inline-flex h-7 w-7 items-center justify-center rounded-full border transition-colors',
                    selected
                      ? 'bg-primary text-primary-foreground border-primary/60 shadow-xs'
                      : 'bg-black/50 text-white border-white/40 hover:bg-black/65',
                  ].join(' ')}
                >
                  {selected ? <Check className="h-4 w-4" /> : <Square className="h-4 w-4" />}
                </div>
              </div>
            )}

            <div className="pointer-events-none absolute inset-0 z-10 flex items-end bg-linear-to-t from-black/70 via-black/30 to-transparent opacity-0 transition-opacity group-hover:opacity-100">
              <div className="w-full p-3 pb-8">
                {item.page_count && item.page_count > 0 && (
                  <span className="rounded bg-white/15 px-1.5 py-0.5 text-[11px] text-white">
                    {item.page_count}P
                  </span>
                )}
              </div>
            </div>
          </div>
        </Card>

        <div className="pt-3">
          <div className="h-5 mb-1">
            <span className="block w-full truncate text-left font-semibold text-sm">
              {item.title}
            </span>
          </div>
          {item.subtitle && (
            <div className="text-xs text-muted-foreground truncate">
              {item.subtitle}
            </div>
          )}
        </div>
      </div>

      {menuOpen && onDownload && !selectionMode && (
        <div
          className="fixed z-50 min-w-[140px] rounded-lg border bg-popover p-1 shadow-lg"
          style={{ left: menuPos.x, top: menuPos.y }}
        >
          <button
            type="button"
            className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm transition-colors hover:bg-accent disabled:opacity-50"
            onClick={(e) => {
              e.stopPropagation();
              onDownload(item);
              setMenuOpen(false);
            }}
            disabled={isDownloading}
          >
            {isDownloading ? (
              <Spinner className="h-4 w-4" />
            ) : (
              <Download className="h-4 w-4 text-muted-foreground" />
            )}
            下载
          </button>
        </div>
      )}
    </>
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
  onItemClick,
  onDownload,
  onToggleSelect,
  quickDownloadId,
  selectionMode,
  selectedIds,
  hasSearched,
}: {
  items: SourceItem[];
  loading: boolean;
  onItemClick: (item: SourceItem) => void;
  onDownload?: (item: SourceItem) => void;
  onToggleSelect?: (item: SourceItem) => void;
  quickDownloadId?: string;
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
      {items.map((item, idx) => (
        <SourceItemCard
          key={item.id}
          item={item}
          onClick={onItemClick}
          onDownload={onDownload}
          onToggleSelect={onToggleSelect}
          isDownloading={quickDownloadId === item.id}
          selectionMode={selectionMode}
          selected={selectedIds?.has(item.id)}
          index={idx}
        />
      ))}
    </div>
  );
}

function ArchiveDownloadRow({
  archive,
  onDownload,
  loading,
}: {
  archive: SourceArchive;
  onDownload: (archive: SourceArchive) => void;
  loading: boolean;
}) {
  return (
    <div className="flex items-center gap-3 p-3 rounded-xl border bg-card hover:bg-accent/40 transition-colors">
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium truncate">{archive.title}</p>
        <div className="flex items-center gap-2 mt-0.5">
          {archive.filename && (
            <p className="text-xs text-muted-foreground truncate">{archive.filename}</p>
          )}
          {archive.size != null && (
            <span className="text-xs text-muted-foreground shrink-0">
              {formatSize(archive.size)}
            </span>
          )}
        </div>
      </div>
      <Button
        size="sm"
        variant="secondary"
        disabled={loading}
        onClick={() => onDownload(archive)}
        className="shrink-0"
      >
        {loading ? <Spinner className="h-3.5 w-3.5" /> : <Download className="h-3.5 w-3.5 mr-1.5" />}
        下载
      </Button>
    </div>
  );
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
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

  const [plugins, setPlugins] = useState<SourcePluginSummary[]>([]);
  const [selectedPlugin, setSelectedPlugin] = useState<string>('');
  const [loadingPlugins, setLoadingPlugins] = useState(true);

  const [items, setItems] = useState<SourceItem[]>([]);
  const [loadingItems, setLoadingItems] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [currentPage, setCurrentPage] = useState(1);
  const [hasNextPage, setHasNextPage] = useState(false);

  const [detailItem, setDetailItem] = useState<SourceDetailResult['data'] | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailOpen, setDetailOpen] = useState(false);

  const [downloadOpen, setDownloadOpen] = useState(false);
  const [downloadArchive, setDownloadArchive] = useState<SourceArchive | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string>('');
  const [downloading, setDownloading] = useState(false);
  const [quickDownloadId, setQuickDownloadId] = useState<string>('');

  // Selection mode
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    SourcePluginService.listSourcePlugins()
      .then((data) => {
        const enabled = data.filter((p) => p.enabled);
        setPlugins(enabled);
        if (enabled.length > 0) {
          setSelectedPlugin(enabled[0].namespace);
        }
      })
      .catch(() => toastErrorRef.current('加载在线源插件列表失败'))
      .finally(() => setLoadingPlugins(false));
  }, []);

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
    const result = await SourcePluginService.home(selectedPlugin, { page });
    handleBrowseResult(result);
    setLoadingItems(false);
  }, [selectedPlugin, handleBrowseResult]);

  const handleSearch = useCallback(async (page: number = 1) => {
    if (!selectedPlugin || !searchQuery.trim()) return;
    setLoadingItems(true);
    setHasSearched(true);
    const result = await SourcePluginService.search(selectedPlugin, searchQuery.trim(), page);
    handleBrowseResult(result);
    setLoadingItems(false);
  }, [selectedPlugin, searchQuery, handleBrowseResult]);

  const handleNextPage = useCallback(() => {
    const next = currentPage + 1;
    setCurrentPage(next);
    if (searchQuery.trim()) {
      handleSearch(next);
    } else {
      loadHome(next);
    }
  }, [currentPage, searchQuery, handleSearch, loadHome]);

  const handlePrevPage = useCallback(() => {
    if (currentPage <= 1) return;
    const prev = currentPage - 1;
    setCurrentPage(prev);
    if (searchQuery.trim()) {
      handleSearch(prev);
    } else {
      loadHome(prev);
    }
  }, [currentPage, searchQuery, handleSearch, loadHome]);

  const prevPluginRef = useRef<string>('');

  useEffect(() => {
    if (!selectedPlugin) return;
    if (prevPluginRef.current !== selectedPlugin) {
      prevPluginRef.current = selectedPlugin;
      setCurrentPage(1);
      setHasNextPage(false);
      setItems([]);
      setSearchQuery('');
      setSelectionMode(false);
      setSelectedIds(new Set());
      loadHome(1);
    }
  }, [selectedPlugin, loadHome]);

  const enterSelectionMode = useCallback(() => {
    setSelectionMode(true);
    setSelectedIds(new Set());
  }, []);

  const exitSelectionMode = useCallback(() => {
    setSelectionMode(false);
    setSelectedIds(new Set());
  }, []);

  const handleToggleSelect = useCallback((item: SourceItem) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(item.id)) {
        next.delete(item.id);
      } else {
        next.add(item.id);
      }
      return next;
    });
  }, []);

  const handleSelectAll = useCallback(() => {
    setSelectedIds(new Set(items.map((i) => i.id)));
  }, [items]);

  const handleBatchDownload = useCallback(async () => {
    if (!selectedPlugin || selectedIds.size === 0) return;
    setQuickDownloadId('batch');
    const ids = Array.from(selectedIds);
    const failed: string[] = [];
    for (const id of ids) {
      try {
        const result = await SourcePluginService.detail(selectedPlugin, id);
        if (result.success && result.data?.archives && result.data.archives.length > 0) {
          // Auto-download first archive with first enabled category
          const cats = await CategoryService.getAllCategories();
          const enabledCats = cats.filter((c) => c.enabled !== false);
          if (enabledCats.length === 0) {
            failed.push(id);
            continue;
          }
          const catId = String(enabledCats[0].id);
          const dlResult = await SourcePluginService.download(
            selectedPlugin,
            result.data.id,
            result.data.archives[0].id,
            Number(catId)
          );
          if (!dlResult.success) {
            failed.push(id);
          }
        } else {
          failed.push(id);
        }
      } catch {
        failed.push(id);
      }
    }
    if (failed.length === 0) {
      toastSuccessRef.current(`已创建 ${ids.length} 个下载任务`);
    } else {
      toastSuccessRef.current(`已创建 ${ids.length - failed.length} 个任务，${failed.length} 个失败`);
    }
    setQuickDownloadId('');
    exitSelectionMode();
  }, [selectedPlugin, selectedIds, exitSelectionMode]);

  const handleItemClick = async (item: SourceItem) => {
    if (!selectedPlugin) return;
    setDetailOpen(true);
    setDetailLoading(true);
    setDetailItem(null);
    const result = await SourcePluginService.detail(selectedPlugin, item.id);
    if (result.success && result.data) {
      setDetailItem(result.data);
    } else {
      toastErrorRef.current(result.error || '获取详情失败');
    }
    setDetailLoading(false);
  };

  const openDownloadDialog = async (archive: SourceArchive, autoRemoteId?: string) => {
    setDownloadArchive(archive);
    setDownloadOpen(true);
    setCategories([]);
    setSelectedCategory('');
    if (autoRemoteId) {
      setDetailItem({ id: autoRemoteId, title: archive.title, archives: [archive] } as SourceDetailResult['data']);
    }
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
    setQuickDownloadId(item.id);
    try {
      const result = await SourcePluginService.detail(selectedPlugin, item.id);
      if (result.success && result.data?.archives && result.data.archives.length > 0) {
        await openDownloadDialog(result.data.archives[0], result.data.id);
      } else {
        toastErrorRef.current(result.error || '无可下载归档');
      }
    } catch {
      toastErrorRef.current('获取详情失败');
    }
    setQuickDownloadId('');
  };

  const handleConfirmDownload = async () => {
    if (!selectedPlugin || !downloadArchive || !selectedCategory) return;
    setDownloading(true);
    const remoteId = detailItem?.id || '';
    const result = await SourcePluginService.download(
      selectedPlugin,
      remoteId,
      downloadArchive.id,
      Number(selectedCategory)
    );
    if (result.success) {
      toastSuccessRef.current('下载任务已创建');
      setDownloadOpen(false);
      router.push('/settings/tasks');
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

      <div className="flex flex-col sm:flex-row gap-3 mb-6">
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
            onChange={(e) => setSearchQuery(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
            className="flex-1"
          />
          <Button onClick={() => handleSearch()} disabled={loadingItems || !selectedPlugin}>
            <Search className="h-4 w-4 mr-2" />
            搜索
          </Button>
        </div>
      </div>

      <SourceHomeGrid
        items={items}
        loading={loadingItems}
        onItemClick={handleItemClick}
        onDownload={handleQuickDownload}
        onToggleSelect={handleToggleSelect}
        quickDownloadId={quickDownloadId}
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

      <Dialog open={detailOpen} onOpenChange={setDetailOpen}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto p-0 gap-0">
          {detailLoading ? (
            <div className="flex items-center justify-center py-12">
              <Spinner />
            </div>
          ) : detailItem ? (
            <>
              {/* Cover */}
              {detailItem.cover && (
                <div className="relative w-full bg-muted">
                  <img
                    src={detailItem.cover}
                    alt={detailItem.title}
                    className="w-full h-auto max-h-[360px] object-cover object-top"
                    onContextMenu={(e) => e.preventDefault()}
                  />
                </div>
              )}

              <div className="p-6 space-y-5">
                {/* Title */}
                <div>
                  <h2 className="text-lg font-semibold leading-snug">{detailItem.title}</h2>
                </div>

                {/* Tags */}
                {detailItem.tags && detailItem.tags.length > 0 && (
                  <div className="flex flex-wrap gap-2">
                    {detailItem.tags.map((tag) => (
                      <Badge key={tag} variant="outline" className="text-xs font-normal px-2.5 py-0.5 rounded-full">
                        {tag}
                      </Badge>
                    ))}
                  </div>
                )}

                {/* Description */}
                {detailItem.description && (
                  <div className="rounded-xl border bg-card p-4 space-y-1.5">
                    {detailItem.description.split('\n').filter(Boolean).map((line, i) => (
                      <p key={i} className="text-sm text-muted-foreground leading-relaxed">
                        {line}
                      </p>
                    ))}
                  </div>
                )}

                {/* Archives */}
                {detailItem.archives && detailItem.archives.length > 0 && (
                  <div className="space-y-3 pt-1">
                    <h3 className="text-sm font-semibold">可下载归档</h3>
                    <div className="space-y-2">
                      {detailItem.archives.map((archive) => (
                        <ArchiveDownloadRow
                          key={archive.id}
                          archive={archive}
                          onDownload={(a) => openDownloadDialog(a)}
                          loading={false}
                        />
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </>
          ) : (
            <div className="text-center py-8 text-muted-foreground text-sm">无法加载详情</div>
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={downloadOpen} onOpenChange={setDownloadOpen}>
        <DialogContent className="max-w-md p-0 gap-0">
          <DialogHeader className="p-6 pb-0">
            <DialogTitle>选择目标分类</DialogTitle>
            <DialogDescription>
              将 <span className="font-medium text-foreground">{downloadArchive?.title || '归档'}</span> 下载到本地
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
