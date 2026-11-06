'use client';

import { useCallback, useEffect, useMemo, useRef, useState, type DragEvent, type ChangeEvent } from 'react';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Spinner } from '@/components/ui/spinner';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useLanguage } from '@/contexts/LanguageContext';
import { PluginService, type PluginCatalogEntry } from '@/lib/services/plugin-service';
import { Download, Package, RefreshCw, Search, Check } from 'lucide-react';
import { extractApiError } from '@/lib/utils/api-utils';

interface PluginInstallDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onInstalled?: () => void;
}

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
  const [sourceUrl, setSourceUrl] = useState('');
  const [entries, setEntries] = useState<PluginCatalogEntry[]>([]);
  const [commit, setCommit] = useState('');
  const [query, setQuery] = useState('');
  const [installingArtifact, setInstallingArtifact] = useState('');
  const [installedArtifacts, setInstalledArtifacts] = useState<Record<string, boolean>>({});

  useEffect(() => {
    tRef.current = t;
  }, [t]);

  const loadCatalog = useCallback(async () => {
    setCatalogLoading(true);
    setCatalogError('');
    try {
      const result = await PluginService.getCatalog();
      setSourceUrl(result.sourceUrl);
      setEntries(result.catalog.plugins || []);
      setCommit(result.catalog.commit || result.catalog.version || '');
    } catch (e) {
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
    setInstalledArtifacts({});
    void loadCatalog();
  }, [open, loadCatalog]);

  const filteredEntries = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return entries;
    return entries.filter((entry) =>
      entryName(entry).toLowerCase().includes(q)
      || (entry.artifact || '').toLowerCase().includes(q)
    );
  }, [entries, query]);

  const handleCatalogInstall = async (entry: PluginCatalogEntry) => {
    if (!sourceUrl || !entry.artifact) return;
    setInstallingArtifact(entry.artifact);
    setCatalogError('');
    try {
      await PluginService.installPlugin(`${sourceUrl}/${entry.artifact}`);
      setInstalledArtifacts((prev) => ({ ...prev, [entry.artifact]: true }));
      onInstalled?.();
    } catch (e) {
      setCatalogError(extractApiError(e, t('settings.pluginInstallFailed')));
    } finally {
      setInstallingArtifact('');
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
                  <div className="truncate">
                    {t('settings.pluginStoreSource')}: {sourceUrl || '—'}
                  </div>
                  {commit && (
                    <div className="truncate">
                      {t('settings.pluginStoreBuild')}: {commit.slice(0, 12)}
                    </div>
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

              <div className="relative">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder={t('settings.pluginStoreSearch')}
                  className="pl-9"
                />
              </div>

              {catalogLoading ? (
                <div className="flex h-40 items-center justify-center">
                  <Spinner />
                </div>
              ) : catalogError ? (
                <div className="space-y-2 rounded-md border border-dashed p-4 text-sm">
                  <p className="text-red-600 dark:text-red-400">{catalogError}</p>
                  {entries.length === 0 && (
                    <p className="text-muted-foreground">{t('settings.pluginStoreSourceHint')}</p>
                  )}
                </div>
              ) : filteredEntries.length === 0 ? (
                <div className="flex h-32 items-center justify-center text-sm text-muted-foreground">
                  {t('settings.pluginStoreEmpty')}
                </div>
              ) : (
                <div className="max-h-[45vh] space-y-2 overflow-y-auto pr-1">
                  {filteredEntries.map((entry) => {
                    const artifact = entry.artifact || '';
                    const installed = !!installedArtifacts[artifact];
                    const isInstalling = installingArtifact === artifact;
                    return (
                      <div
                        key={artifact || entry.plugin}
                        className="flex items-center gap-3 rounded-md border p-3"
                      >
                        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-muted">
                          <Package className="h-4 w-4 text-muted-foreground" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="truncate text-sm font-medium">{entryName(entry)}</div>
                          <div className="truncate text-xs text-muted-foreground">
                            {formatBytes(entry.size_bytes)}
                            {entry.sha256 ? ` · ${entry.sha256.slice(0, 8)}` : ''}
                          </div>
                        </div>
                        <Button
                          type="button"
                          size="sm"
                          variant={installed ? 'outline' : 'default'}
                          disabled={installed || isInstalling || !sourceUrl}
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
