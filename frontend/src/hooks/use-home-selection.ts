import { useState, useCallback, useMemo } from 'react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { appEvents, AppEvents } from '@/lib/utils/events';
import type { BatchEditPayload } from '@/components/archive/BatchEditDialog';
import { Archive } from '@/types/archive';
import { Tankoubon } from '@/types/tankoubon';

function isTankoubonItem(item: any): item is Tankoubon {
  return item && 'tankoubon_id' in item;
}

export interface UseHomeSelectionVisibleItems {
  archives: Array<Archive | Tankoubon>;
  randomArchives: Array<Archive | Tankoubon>;
  categoryRows: Record<string, (Archive | Tankoubon)[]>;
}

async function loadArchiveService() {
  return (await import('@/lib/services/archive-service')).ArchiveService;
}

async function loadTankoubonService() {
  return (await import('@/lib/services/tankoubon-service')).TankoubonService;
}

async function loadFavoriteService() {
  return (await import('@/lib/services/favorite-service')).FavoriteService;
}

async function loadPluginService() {
  return (await import('@/lib/services/plugin-service')).PluginService;
}

export function useHomeSelection(
  getVisibleItems: () => UseHomeSelectionVisibleItems,
) {
  const { t } = useLanguage();
  const { success: showSuccess, error: showError, info: showInfo } = useToast();
  const { confirm } = useConfirmContext();

  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedArchiveIds, setSelectedArchiveIds] = useState<Set<string>>(new Set());
  const [selectedTankoubonIds, setSelectedTankoubonIds] = useState<Set<string>>(new Set());
  const [batchEditOpen, setBatchEditOpen] = useState(false);
  const [batchEditApplying, setBatchEditApplying] = useState(false);
  const [metadataPlugins, setMetadataPlugins] = useState<Array<{ namespace: string; name: string }>>([]);
  const [batchActionRunning, setBatchActionRunning] = useState(false);

  const visibleItemMap = useMemo(() => {
    const { archives, randomArchives, categoryRows } = getVisibleItems();
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
  }, [getVisibleItems]);

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

  // Load metadata plugins when batch edit dialog opens
  const openBatchEdit = useCallback(() => {
    setBatchEditOpen(true);
  }, []);

  // Watch batchEditOpen to load plugins
  // This is done via a separate useEffect in the page, or we can do it inline.
  // We'll keep it as a callback that the page calls in a useEffect.
  const loadMetadataPlugins = useCallback(async () => {
    try {
      const PluginService = await loadPluginService();
      const plugins = await PluginService.getMetadataPlugins();
      setMetadataPlugins(
        plugins
          .filter((plugin) => plugin.enabled)
          .map((plugin) => ({ namespace: plugin.namespace, name: plugin.name || plugin.namespace }))
      );
    } catch {
      setMetadataPlugins([]);
    }
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
      const [ArchiveService, TankoubonService] = await Promise.all([
        loadArchiveService(),
        loadTankoubonService(),
      ]);

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

    const [ArchiveService, TankoubonService] = await Promise.all([
      loadArchiveService(),
      loadTankoubonService(),
    ]);
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
    const FavoriteService = await loadFavoriteService();
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
    const ArchiveService = await loadArchiveService();
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

  const handleBatchDownload = useCallback(async () => {
    if (!canBatchDownload) {
      showInfo(t('home.batchDownloadOnlyArchive'));
      return;
    }
    const ArchiveService = await loadArchiveService();
    Array.from(selectedArchiveIds).forEach((id) => {
      window.open(ArchiveService.getDownloadUrl(id), '_blank');
    });
    showSuccess(
      t('home.batchDownloadStarted').replace('{count}', String(selectedArchiveIds.size))
    );
  }, [canBatchDownload, selectedArchiveIds, showInfo, showSuccess, t]);

  return {
    // State
    selectionMode,
    selectedArchiveIds,
    selectedTankoubonIds,
    batchEditOpen,
    setBatchEditOpen,
    batchEditApplying,
    metadataPlugins,
    batchActionRunning,
    // Derived
    selectedArchiveCount,
    selectedTankoubonCount,
    selectedTotal,
    hasAnySelected,
    canBatchDownload,
    favoriteActionLabel,
    allSelectedArchiveIsNew,
    // Actions
    clearSelection,
    enterSelectionMode,
    exitSelectionMode,
    toggleArchiveSelect,
    toggleTankoubonSelect,
    openBatchEdit,
    loadMetadataPlugins,
    handleBatchDelete,
    handleBatchFavorite,
    handleBatchReadStatus,
    handleBatchDownload,
    applyBatchEdit,
  };
}
