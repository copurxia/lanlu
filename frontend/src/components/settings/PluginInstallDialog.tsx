'use client';

import { useCallback, useEffect, useMemo, useRef, useState, type DragEvent, type ChangeEvent } from 'react';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Spinner } from '@/components/ui/spinner';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useLanguage } from '@/contexts/LanguageContext';
import {
  PluginService,
  type PluginCatalogEntry,
  type PluginCatalogSource,
} from '@/lib/services/plugin-service';
import { Download, Package, RefreshCw, Search, Check, AlertTriangle } from 'lucide-react';
import { extractApiError } from '@/lib/utils/api-utils';

interface PluginInstallDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onInstalled?: () => void;
}

type CatalogEntry = PluginCatalogEntry & { source_url: string };

function formatBytes(bytes?: number): string {
  if (!bytes || bytes <= 0) return '';
  const mb = bytes / (1024 * 1024);
  if (mb >= 1) return `${mb.toFixed(1)} MB`;
  return `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function entryName(entry: PluginCatalogEntry): string {
  return (entry.plugin || entry.artifact || '')
    .replace(/-wasip1\.wasm$/, '')
    .replace(/-wasip1$/, '');
}

/** release 资产名：优先用清单里的 asset，否则按 <plugin>.wasm 拼 */
function releaseAsset(entry: PluginCatalogEntry): string {
  if (entry.asset) return entry.asset;
  const base = entry.plugin || '';
  if (base) return base.toLowerCase().endsWith('.wasm') ? base : `${base}.wasm`;
  return entry.artifact || '';
}

function entryNamespace(entry: PluginCatalogEntry): string {
  return (entry.namespace || entryName(entry)).trim().toLowerCase();
}

function entryKey(entry: PluginCatalogEntry): string {
  return entryNamespace(entry) || releaseAsset(entry).toLowerCase();
}

/** 合并多源同名插件时优先保留元数据更完整的一条 */
function catalogRichness(entry: PluginCatalogEntry): number {
  return (entry.namespace ? 1 : 0)
    + (entry.name ? 1 : 0)
    + (entry.description ? 1 : 0)
    + (entry.icon ? 1 : 0)
    + ((entry.pre?.length ?? 0) > 0 ? 1 : 0);
}

export function PluginInstallDialog({
  open,
  onOpenChange,
  onInstalled,
}: PluginInstallDialogProps) {
  const { t } = useLanguage();
  const tRef = useRef(t);
  const [activeTab, setActiveTab] = useState('store');

  // 自定义安装（URL / 上传）
  const [url, setUrl] = useState('');
  const [installing, setInstalling] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [error, setError] = useState('');
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  // 插件商店
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [catalogError, setCatalogError] = useState('');
  const [sources, setSources] = useState<PluginCatalogSource[]>([]);
  const [failedSources, setFailedSources] = useState<PluginCatalogSource[]>([]);
  const [entries, setEntries] = useState<CatalogEntry[]>([]);
  const [sourceFilter, setSourceFilter] = useState('');
  const [query, setQuery] = useState('');
  const [installingKey, setInstallingKey] = useState('');
  const [installedNamespaces, setInstalledNamespaces] = useState<Set<string>>(new Set());
  const [installedAssets, setInstalledAssets] = useState<Record<string, boolean>>({});
  const [brokenIcons, setBrokenIcons] = useState<Record<string, boolean>>({});

  useEffect(() => {
    tRef.current = t;
  }, [t]);

  const loadCatalog = useCallback(async () => {
    setCatalogLoading(true);
    setCatalogError('');
    try {
      const [catalogSources, installed] = await Promise.all([
        PluginService.getCatalog(),
        PluginService.getAllPlugins().catch(() => []),
      ]);
      const okSources = catalogSources.filter(
        (s) => s.ok && s.catalog && Array.isArray(s.catalog.plugins)
      );
      const failed = catalogSources.filter((s) => !s.ok);

      const merged: CatalogEntry[] = [];
      const indexByAsset = new Map<string, number>();
      for (const source of okSources) {
        for (const plugin of source.catalog!.plugins) {
          const key = releaseAsset(plugin).toLowerCase();
          if (!key) continue;
          const candidate: CatalogEntry = { ...plugin, source_url: source.url };
          const existingIndex = indexByAsset.get(key);
          if (existingIndex === undefined) {
            indexByAsset.set(key, merged.length);
            merged.push(candidate);
          } else if (catalogRichness(candidate) > catalogRichness(merged[existingIndex])) {
            merged[existingIndex] = candidate;
          }
        }
      }

      setSources(okSources);
      setFailedSources(failed);
      setEntries(merged);
      setSourceFilter('');
      setInstalledNamespaces(
        new Set(
          installed
            .filter((p) => p.installed !== false)
            .map((p) => (p.namespace || '').trim().toLowerCase())
            .filter((ns) => ns.length > 0)
        )
      );
      setInstalledAssets({});
      setBrokenIcons({});

      if (okSources.length === 0 && failed.length > 0) {
        setCatalogError(
          failed.map((s) => `${s.url}: ${s.error || 'failed'}`).join('\n')
        );
      }
    } catch (e) {
      setSources([]);
      setFailedSources([]);
      setEntries([]);
      setCatalogError(extractApiError(e, tRef.current('settings.pluginStoreLoadFailed')));
    } finally {
      setCatalogLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    setActiveTab('store');
    setUrl('');
    setFile(null);
    setError('');
    setQuery('');
    void loadCatalog();
  }, [open, loadCatalog]);

  const byNamespace = useMemo(() => {
    const map = new Map<string, CatalogEntry>();
    for (const entry of entries) {
      const ns = entryNamespace(entry);
      if (ns && !map.has(ns)) map.set(ns, entry);
    }
    return map;
  }, [entries]);

  const resolvePlan = useCallback(
    (entry: CatalogEntry): { plan: CatalogEntry[]; missing: string[] } => {
      const plan: CatalogEntry[] = [];
      const missing: string[] = [];
      const visited = new Set<string>();
      const walk = (current: CatalogEntry, depth: number) => {
        if (depth > 5) return;
        const selfNs = entryNamespace(current);
        for (const raw of current.pre || []) {
          const ns = (raw || '').trim().toLowerCase();
          if (!ns || ns === selfNs || visited.has(ns)) continue;
          if (installedNamespaces.has(ns)) continue;
          const dep = byNamespace.get(ns);
          if (!dep) {
            if (!missing.includes(ns)) missing.push(ns);
            continue;
          }
          visited.add(ns);
          walk(dep, depth + 1);
          plan.push(dep);
        }
      };
      walk(entry, 0);
      return { plan, missing };
    },
    [byNamespace, installedNamespaces]
  );

  const filteredEntries = useMemo(() => {
    const q = query.trim().toLowerCase();
    return entries.filter((entry) => {
      if (sourceFilter && entry.source_url !== sourceFilter) return false;
      if (!q) return true;
      return [entry.name, entry.namespace, entryName(entry), entry.description, entry.artifact]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(q));
    });
  }, [entries, query, sourceFilter]);

  const markInstalled = (entry: PluginCatalogEntry) => {
    const ns = entryNamespace(entry);
    if (ns) {
      setInstalledNamespaces((prev) => {
        const next = new Set(prev);
        next.add(ns);
        return next;
      });
    }
    const asset = releaseAsset(entry);
    if (asset) {
      setInstalledAssets((prev) => ({ ...prev, [asset]: true }));
    }
  };

  const handleCatalogInstall = async (entry: CatalogEntry) => {
    const asset = releaseAsset(entry);
    if (!entry.source_url || !asset) return;

    const { plan, missing } = resolvePlan(entry);
    if (missing.length > 0) {
      setCatalogError(`${t('settings.pluginStoreMissingDep')}: ${missing.join(', ')}`);
      return;
    }

    setInstallingKey(entryKey(entry));
    setCatalogError('');
    try {
      for (const dep of plan) {
        const depAsset = releaseAsset(dep);
        if (!dep.source_url || !depAsset) continue;
        await PluginService.installPlugin(`${dep.source_url}/${depAsset}`);
        markInstalled(dep);
      }
      await PluginService.installPlugin(`${entry.source_url}/${asset}`);
      markInstalled(entry);
      onInstalled?.();
    } catch (e) {
      setCatalogError(extractApiError(e, t('settings.pluginInstallFailed')));
    } finally {
      setInstallingKey('');
    }
  };

  const handleInstallFromUrl = async () => {
    if (!url.trim()) {
      setError(t('settings.pluginInstallUrlRequired') || 'URL is required');
      return;
    }

    if (!url.toLowerCase().endsWith('.wasm')) {
      setError(t('settings.pluginInstallUrlInvalid') || 'URL must point to a .wasm file');
      return;
    }

    setInstalling(true);
    setError('');

    try {
      await PluginService.installPlugin(url);
      onOpenChange(false);
      setUrl('');
      setFile(null);
      onInstalled?.();
    } catch (e) {
      setError(extractApiError(e, t('settings.pluginInstallFailed')));
    } finally {
      setInstalling(false);
    }
  };

  const setSelectedFile = (next: File | null) => {
    setError('');
    if (!next) {
      setFile(null);
      return;
    }
    if (!next.name.toLowerCase().endsWith('.wasm')) {
      setError(t('settings.pluginUploadFileInvalid') || 'Please select a .wasm plugin file');
      setFile(null);
      return;
    }
    setFile(next);
  };

  const handleFileChange = (event: ChangeEvent<HTMLInputElement>) => {
    const next = event.target.files?.[0] ?? null;
    event.target.value = '';
    setSelectedFile(next);
  };

  const handleDrop = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    event.stopPropagation();
    setDragging(false);
    const next = event.dataTransfer.files?.[0] ?? null;
    setSelectedFile(next);
  };

  const handleDragOver = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    event.stopPropagation();
    setDragging(true);
  };

  const handleDragLeave = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    event.stopPropagation();
    setDragging(false);
  };

  const handleUploadInstall = async () => {
    if (!file) {
      setError(t('settings.pluginUploadFileInvalid') || 'Please select a .wasm plugin file');
      return;
    }
    setUploading(true);
    setError('');
    try {
      await PluginService.uploadPlugin(file);
      onOpenChange(false);
      setUrl('');
      setFile(null);
      onInstalled?.();
    } catch (e) {
      setError(extractApiError(e, t('settings.pluginUploadFailed')));
    } finally {
      setUploading(false);
    }
  };

  const handleCancel = () => {
    setUrl('');
    setFile(null);
    setError('');
    onOpenChange(false);
  };

  const renderIcon = (entry: CatalogEntry) => {
    const icon = (entry.icon || '').trim();
    const key = entryKey(entry);
    const letter = (entry.name || entryName(entry) || '?').trim().charAt(0).toUpperCase();
    if (icon && !brokenIcons[key]) {
      return (
        <img
          src={icon}
          alt=""
          className="h-9 w-9 shrink-0 rounded-md border object-cover"
          onError={() => setBrokenIcons((prev) => ({ ...prev, [key]: true }))}
        />
      );
    }
    return (
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-muted text-sm font-semibold text-muted-foreground">
        {letter || <Package className="h-4 w-4" />}
      </div>
    );
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center space-x-2">
            <Download className="w-5 h-5" />
            <span>{t('settings.pluginInstall')}</span>
          </DialogTitle>
        </DialogHeader>

        <DialogBody>
          <Tabs value={activeTab} onValueChange={setActiveTab}>
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="store">{t('settings.pluginStore')}</TabsTrigger>
              <TabsTrigger value="custom">{t('settings.pluginCustomInstall')}</TabsTrigger>
            </TabsList>

            <TabsContent value="store" className="mt-4 space-y-3">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0 text-xs text-muted-foreground">
                  {sources.length === 1 ? (
                    <div className="truncate">
                      {t('settings.pluginStoreSource')}: {sources[0].url}
                    </div>
                  ) : sources.length > 1 ? (
                    <div className="truncate">
                      {t('settings.pluginStoreSource')}: {sources.length}
                      {failedSources.length > 0 ? ` (+${failedSources.length} failed)` : ''}
                    </div>
                  ) : (
                    <div>{t('settings.pluginStoreSourceHint')}</div>
                  )}
                </div>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => void loadCatalog()}
                  disabled={catalogLoading}
                >
                  <RefreshCw className={`mr-1 h-4 w-4 ${catalogLoading ? 'animate-spin' : ''}`} />
                  {t('settings.pluginStoreRefresh')}
                </Button>
              </div>

              <div className="flex gap-2">
                <div className="relative flex-1">
                  <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                  <Input
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder={t('settings.pluginStoreSearch')}
                    className="pl-9"
                  />
                </div>
                {sources.length > 1 && (
                  <select
                    value={sourceFilter}
                    onChange={(e) => setSourceFilter(e.target.value)}
                    className="h-9 max-w-[40%] rounded-md border border-input bg-background px-2 text-sm"
                  >
                    <option value="">{t('settings.pluginStoreSourceFilterAll')}</option>
                    {sources.map((source) => (
                      <option key={source.url} value={source.url}>
                        {source.url.replace(/^https?:\/\//, '').replace(/\/releases\/.*$/, '')}
                      </option>
                    ))}
                  </select>
                )}
              </div>

              {failedSources.length > 0 && !catalogLoading && (
                <div className="flex items-start gap-2 rounded-md border border-amber-500/40 bg-amber-500/5 p-3 text-xs text-amber-700 dark:text-amber-300">
                  <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                  <div className="min-w-0">
                    <div className="font-medium">{t('settings.pluginStoreFailedSources')}</div>
                    {failedSources.map((source) => (
                      <div key={source.url} className="truncate">
                        {source.url}: {source.error || 'failed'}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {catalogError && !catalogLoading && (
                <div className="space-y-1 rounded-md border border-dashed p-4 text-sm">
                  <p className="text-red-600 dark:text-red-400 whitespace-pre-line">{catalogError}</p>
                  {entries.length === 0 && (
                    <p className="text-muted-foreground">{t('settings.pluginStoreSourceHint')}</p>
                  )}
                </div>
              )}

              {catalogLoading ? (
                <div className="flex h-40 items-center justify-center">
                  <Spinner />
                </div>
              ) : filteredEntries.length === 0 ? (
                <div className="flex h-32 items-center justify-center text-sm text-muted-foreground">
                  {t('settings.pluginStoreEmpty')}
                </div>
              ) : (
                <div className="max-h-[48vh] space-y-2 overflow-y-auto pr-1">
                  {filteredEntries.map((entry) => {
                    const key = entryKey(entry);
                    const asset = releaseAsset(entry);
                    const ns = entryNamespace(entry);
                    const installed = !!installedAssets[asset] || (!!ns && installedNamespaces.has(ns));
                    const isInstalling = installingKey === key;
                    const { plan, missing } = resolvePlan(entry);
                    const pre = (entry.pre || []).filter(Boolean);
                    const subtitle = [
                      entry.version ? `v${entry.version.replace(/^v/, '')}` : '',
                      entry.type || '',
                      formatBytes(entry.size_bytes),
                    ].filter(Boolean).join(' · ');

                    return (
                      <div
                        key={key || asset}
                        className="flex items-start gap-3 rounded-md border p-3"
                      >
                        {renderIcon(entry)}
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2">
                            <div className="truncate text-sm font-medium">
                              {entry.name || entryName(entry)}
                            </div>
                            {subtitle && (
                              <div className="shrink-0 text-[11px] text-muted-foreground">
                                {subtitle}
                              </div>
                            )}
                          </div>
                          {entry.description && (
                            <div className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">
                              {entry.description}
                            </div>
                          )}
                          {pre.length > 0 && (
                            <div className={`mt-1 text-[11px] ${missing.length > 0 ? 'text-amber-600 dark:text-amber-400' : 'text-muted-foreground'}`}>
                              {t('settings.pluginStoreDepends')}: {pre.join(', ')}
                              {missing.length > 0
                                ? ` · ${t('settings.pluginStoreMissingDep')}: ${missing.join(', ')}`
                                : ''}
                              {missing.length === 0 && plan.length > 0
                                ? ` · ${t('settings.pluginStoreWillInstallDeps')}: ${plan.map((d) => entryName(d)).join(', ')}`
                                : ''}
                            </div>
                          )}
                        </div>
                        <Button
                          type="button"
                          size="sm"
                          variant={installed ? 'outline' : 'default'}
                          disabled={installed || isInstalling || !asset || !entry.source_url}
                          onClick={() => void handleCatalogInstall(entry)}
                        >
                          {installed ? (
                            <>
                              <Check className="mr-1 h-3.5 w-3.5" />
                              {t('settings.pluginStoreInstalled')}
                            </>
                          ) : isInstalling ? (
                            t('settings.pluginInstalling')
                          ) : (
                            <>
                              <Download className="mr-1 h-3.5 w-3.5" />
                              {t('settings.pluginStoreInstall')}
                            </>
                          )}
                        </Button>
                      </div>
                    );
                  })}
                </div>
              )}
            </TabsContent>

            <TabsContent value="custom" className="mt-4 space-y-4">
              <div className="space-y-2">
                <Label>{t('settings.pluginUpload')}</Label>
                <div
                  className={`rounded-md border border-dashed p-4 text-sm cursor-pointer transition-colors ${
                    dragging ? 'border-primary bg-primary/5' : 'border-border'
                  }`}
                  onClick={() => fileInputRef.current?.click()}
                  onDrop={handleDrop}
                  onDragOver={handleDragOver}
                  onDragLeave={handleDragLeave}
                >
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept=".wasm,application/wasm"
                    className="hidden"
                    onChange={handleFileChange}
                  />
                  {file ? (
                    <div className="flex items-center justify-between gap-3">
                      <span className="truncate">{file.name}</span>
                      <Button type="button" variant="outline" size="sm" onClick={(e) => {
                        e.stopPropagation();
                        setFile(null);
                      }}>
                        {t('common.clear') || 'Clear'}
                      </Button>
                    </div>
                  ) : (
                    <span>{t('settings.pluginUploadDropHint') || 'Drag and drop .wasm file here, or click to select'}</span>
                  )}
                </div>
                <Button type="button" onClick={handleUploadInstall} disabled={uploading || installing || !file} className="w-full">
                  {uploading ? (t('settings.pluginUploading') || 'Uploading...') : (t('settings.pluginUpload') || 'Upload Plugin')}
                </Button>
              </div>

              <div className="text-center text-xs text-muted-foreground">{t('settings.pluginInstallOr') || 'OR'}</div>

              <div className="space-y-2">
                <Label htmlFor="plugin-url">{t('settings.pluginInstallUrl')}</Label>
                <Input
                  id="plugin-url"
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  placeholder={t('settings.pluginInstallUrlPlaceholder')}
                />
              </div>

              <Button type="button" onClick={handleInstallFromUrl} disabled={installing || uploading} className="w-full">
                {installing ? t('settings.pluginInstalling') : t('settings.pluginInstall')}
              </Button>

              {error && (
                <div className="text-sm text-red-600 dark:text-red-400">
                  {error}
                </div>
              )}
            </TabsContent>
          </Tabs>
        </DialogBody>

        <DialogFooter>
          <Button variant="outline" onClick={handleCancel} disabled={installing || uploading}>
            {t('common.cancel')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
