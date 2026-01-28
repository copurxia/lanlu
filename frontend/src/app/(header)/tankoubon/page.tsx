'use client';

import { useState, useEffect, useCallback, Suspense, useMemo } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { MobileBottomNav } from '@/components/layout/MobileBottomNav';
import { ArchiveCard } from '@/components/archive/ArchiveCard';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Spinner } from '@/components/ui/spinner';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Progress } from '@/components/ui/progress';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { TagInput } from '@/components/ui/tag-input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { ArchiveService } from '@/lib/services/archive-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { PluginService, type Plugin } from '@/lib/services/plugin-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { logger } from '@/lib/utils/logger';
import { ArrowLeft, Edit, Trash2, Plus, BookOpen, Heart, Search, Play } from 'lucide-react';
import type { Tankoubon } from '@/types/tankoubon';
import type { Archive } from '@/types/archive';
import Image from 'next/image';

function TankoubonDetailContent() {
  const { t, language } = useLanguage();
  const searchParams = useSearchParams();
  const router = useRouter();
  const tankoubonId = searchParams?.get('id') ?? null;

  const [tankoubon, setTankoubon] = useState<Tankoubon | null>(null);
  const [archives, setArchives] = useState<Archive[]>([]);
  const [loading, setLoading] = useState(true);
  const [archivesLoading, setArchivesLoading] = useState(false);
  const [isFavorite, setIsFavorite] = useState(false);
  const [favoriteLoading, setFavoriteLoading] = useState(false);

  // Edit dialog state
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [editName, setEditName] = useState('');
  const [editSummary, setEditSummary] = useState('');
  const [editTags, setEditTags] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);

  // Metadata plugin state (preview mode: fill edit form without DB write-back)
  const [metadataPlugins, setMetadataPlugins] = useState<Plugin[]>([]);
  const [selectedMetadataPlugin, setSelectedMetadataPlugin] = useState<string>('');
  const [metadataPluginParam, setMetadataPluginParam] = useState<string>('');
  const [isMetadataPluginRunning, setIsMetadataPluginRunning] = useState(false);
  const [metadataPluginProgress, setMetadataPluginProgress] = useState<number | null>(null);
  const [metadataPluginMessage, setMetadataPluginMessage] = useState<string>('');

  // Delete dialog state
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);

  // Remove archive state
  const [removeDialogOpen, setRemoveDialogOpen] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<Archive | null>(null);
  const [removingArcids, setRemovingArcids] = useState<Set<string>>(new Set());

  // Add archive dialog state
  const [addArchiveDialogOpen, setAddArchiveDialogOpen] = useState(false);
  const [availableArchives, setAvailableArchives] = useState<Archive[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchLoading, setSearchLoading] = useState(false);
  const [selectedArchives, setSelectedArchives] = useState<Set<string>>(new Set());
  const [addingArchives, setAddingArchives] = useState(false);

  // Archive filter (within this collection)
  const [archiveFilter, setArchiveFilter] = useState('');

  // Fetch tankoubon details
  const fetchTankoubon = useCallback(async () => {
    if (!tankoubonId) return;

    try {
      setLoading(true);
      const data = await TankoubonService.getTankoubonById(tankoubonId);

      // Prefer translated tags coming from the search endpoint (avoids /api/tags/translations)
      try {
        const searchResult = await ArchiveService.search({
          tankoubon_id: tankoubonId,
          groupby_tanks: true,
          start: 0,
          count: 1,
          sortby: 'tank_order',
          order: 'asc',
          lang: language,
        });
        const tankItem = searchResult.data.find(
          (item): item is Tankoubon => Boolean(item) && typeof item === 'object' && 'tankoubon_id' in item
        );
        if (tankItem && tankItem.tankoubon_id === tankoubonId && typeof tankItem.tags === 'string') {
          data.tags = tankItem.tags;
        }
      } catch {
        // Ignore; fall back to untranslated tags
      }

      setTankoubon(data);
      setIsFavorite(data.isfavorite || false);

      // Set edit form values
      setEditName(data.name);
      setEditSummary(data.summary || '');
      setEditTags(
        (data.tags || '')
          .split(',')
          .map((tag) => tag.trim())
          .filter((tag) => tag)
      );
    } catch (error) {
      logger.apiError('fetch tankoubon', error);
    } finally {
      setLoading(false);
    }
  }, [tankoubonId, language]);

  // Fetch archives in tankoubon
  const fetchArchives = useCallback(async () => {
    if (!tankoubon?.tankoubon_id || !tankoubon?.archives || tankoubon.archives.length === 0) {
      setArchives([]);
      return;
    }

    try {
      setArchivesLoading(true);
      const result = await ArchiveService.search({
        tankoubon_id: tankoubon.tankoubon_id,
        sortby: 'tank_order',
        order: 'asc',
        start: 0,
        count: 10000,
        groupby_tanks: false,
        lang: language,
      });
      const archiveItems = result.data.filter(
        (item): item is Archive => Boolean(item) && typeof item === 'object' && 'arcid' in item
      );
      setArchives(archiveItems || []);
    } catch (error) {
      logger.apiError('fetch archives', error);
    } finally {
      setArchivesLoading(false);
    }
  }, [tankoubon?.archives, tankoubon?.tankoubon_id, language]);

  useEffect(() => {
    fetchTankoubon();
  }, [fetchTankoubon]);

  useEffect(() => {
    if (tankoubon) {
      fetchArchives();
    }
  }, [tankoubon, fetchArchives]);

  // Helper function to display translated tag
  const displayTag = useCallback((tag: string): string => {
    const key = String(tag || '').trim();
    if (!key) return '';
    const idx = key.indexOf(':');
    return idx > 0 ? key.slice(idx + 1) : key;
  }, []);

  const handleFavoriteClick = async () => {
    if (!tankoubon || favoriteLoading) return;
    setFavoriteLoading(true);
    try {
      const success = await FavoriteService.toggleTankoubonFavorite(tankoubon.tankoubon_id, isFavorite);
      if (success) {
        setIsFavorite(!isFavorite);
        setTankoubon({ ...tankoubon, isfavorite: !isFavorite });
      }
    } catch (error) {
      logger.operationFailed('toggle tankoubon favorite', error);
    } finally {
      setFavoriteLoading(false);
    }
  };

  // Handle edit
  const handleEdit = async () => {
    if (!tankoubon) return;

    try {
      setSaving(true);
      await TankoubonService.updateTankoubon(tankoubon.tankoubon_id, {
        name: editName,
        summary: editSummary,
        tags: editTags.join(', '),
      });
      setEditDialogOpen(false);
      fetchTankoubon();
    } catch (error) {
      logger.operationFailed('update tankoubon', error);
    } finally {
      setSaving(false);
    }
  };

  // Load metadata plugins when opening the edit dialog
  useEffect(() => {
    if (!editDialogOpen) return;
    let cancelled = false;
    (async () => {
      try {
        const metas = await PluginService.getMetadataPlugins();
        if (cancelled) return;
        setMetadataPlugins(metas);
        if (!selectedMetadataPlugin && metas.length > 0) {
          setSelectedMetadataPlugin(metas[0].namespace);
        }
      } catch (e) {
        logger.apiError('load metadata plugins', e);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [editDialogOpen, selectedMetadataPlugin]);

  const runMetadataPlugin = useCallback(async () => {
    if (!tankoubon) return;
    if (!selectedMetadataPlugin) return;

    setIsMetadataPluginRunning(true);
    setMetadataPluginProgress(0);
    setMetadataPluginMessage(t('archive.metadataPluginEnqueued'));

    try {
      const finalTask = await ArchiveService.runMetadataPluginForTarget(
        'tankoubon',
        tankoubon.tankoubon_id,
        selectedMetadataPlugin,
        metadataPluginParam,
        {
          onUpdate: (task) => {
            setMetadataPluginProgress(typeof task.progress === 'number' ? task.progress : 0);
            setMetadataPluginMessage(task.message || '');
          },
        },
        { writeBack: false }
      );

      if (finalTask.status !== 'completed') {
        const err = finalTask.result || finalTask.message || t('archive.metadataPluginFailed');
        logger.operationFailed('run metadata plugin (tankoubon)', new Error(err));
        return;
      }

      // Preview mode: parse plugin output and fill the edit form (no DB write-back).
      try {
        const out = finalTask.result ? JSON.parse(finalTask.result) : null;
        const ok = out?.success === true || out?.success === 1 || out?.success === '1' || out?.success === 'true';
        if (!ok) {
          const err = out?.error || finalTask.result || finalTask.message || t('archive.metadataPluginFailed');
          logger.operationFailed('run metadata plugin (tankoubon)', new Error(err));
          return;
        }

        const data = out?.data || {};
        const nextTitle = typeof data.title === 'string' ? data.title : '';
        const nextSummary = typeof data.summary === 'string' ? data.summary : '';
        const nextTags = typeof data.tags === 'string' ? data.tags : '';

        if (nextTitle.trim()) setEditName(nextTitle);
        if (nextSummary.trim()) setEditSummary(nextSummary);
        if (nextTags.trim()) {
          setEditTags(
            nextTags
              .split(',')
              .map((tag: string) => tag.trim())
              .filter((tag: string) => tag)
          );
        }
      } catch {
        // ignore parse errors
      }

      setMetadataPluginMessage(t('archive.metadataPluginCompleted'));
      setMetadataPluginProgress(100);
    } catch (e) {
      logger.operationFailed('run metadata plugin (tankoubon)', e);
    } finally {
      setIsMetadataPluginRunning(false);
    }
  }, [tankoubon, selectedMetadataPlugin, metadataPluginParam, t]);

  // Handle delete
  const handleDelete = async () => {
    if (!tankoubon) return;

    try {
      setDeleting(true);
      await TankoubonService.deleteTankoubon(tankoubon.tankoubon_id);
      router.push('/');
    } catch (error) {
      logger.operationFailed('delete tankoubon', error);
      setDeleting(false);
    }
  };

  // Handle remove archive from tankoubon
  const handleRemoveArchive = async (arcid: string) => {
    if (!tankoubon) return;

    try {
      setRemovingArcids((prev) => new Set(prev).add(arcid));
      await TankoubonService.removeArchiveFromTankoubon(tankoubon.tankoubon_id, arcid);
      fetchTankoubon();
    } catch (error) {
      logger.operationFailed('remove archive', error);
    } finally {
      setRemovingArcids((prev) => {
        const next = new Set(prev);
        next.delete(arcid);
        return next;
      });
    }
  };

  const confirmRemoveArchive = async () => {
    if (!removeTarget) return;
    await handleRemoveArchive(removeTarget.arcid);
    setRemoveDialogOpen(false);
    setRemoveTarget(null);
  };

  // Search for archives to add
  const searchArchives = async () => {
    try {
      setSearchLoading(true);
      const result = await ArchiveService.search({
        filter: searchQuery,
        count: 50,
        groupby_tanks: false, // Don't group by tanks when searching for archives to add
        lang: language,
      });

      // Filter out archives already in this tankoubon
      const existingArcids = new Set(tankoubon?.archives || []);
      const filtered = result.data
        .filter((item): item is Archive => Boolean(item) && typeof item === 'object' && 'arcid' in item)
        .filter((a) => !existingArcids.has(a.arcid));
      setAvailableArchives(filtered);
    } catch (error) {
      logger.apiError('search archives', error);
    } finally {
      setSearchLoading(false);
    }
  };

  // Handle add archives
  const handleAddArchives = async () => {
    if (!tankoubon || selectedArchives.size === 0) return;

    try {
      setAddingArchives(true);
      const promises = Array.from(selectedArchives).map((arcid) =>
        TankoubonService.addArchiveToTankoubon(tankoubon.tankoubon_id, arcid)
      );
      await Promise.all(promises);
      setAddArchiveDialogOpen(false);
      setSelectedArchives(new Set());
      setAvailableArchives([]);
      setSearchQuery('');
      fetchTankoubon();
    } catch (error) {
      logger.operationFailed('add archives', error);
    } finally {
      setAddingArchives(false);
    }
  };

  // Toggle archive selection
  const toggleArchiveSelection = (arcid: string) => {
    const newSelected = new Set(selectedArchives);
    if (newSelected.has(arcid)) {
      newSelected.delete(arcid);
    } else {
      newSelected.add(arcid);
    }
    setSelectedArchives(newSelected);
  };

  const filteredArchives = useMemo(() => {
    const q = archiveFilter.trim().toLowerCase();
    if (!q) return archives;
    return archives.filter((a) => {
      const title = String(a.title || '').toLowerCase();
      const tags = String(a.tags || '').toLowerCase();
      return title.includes(q) || tags.includes(q);
    });
  }, [archives, archiveFilter]);

  if (loading) {
    return (
      <div className="min-h-screen bg-background">
        <main className="container mx-auto px-4 py-8">
          <div className="flex justify-center items-center h-64">
            <Spinner size="lg" />
          </div>
        </main>
      </div>
    );
  }

  if (!tankoubon) {
    return (
      <div className="min-h-screen bg-background">
        <main className="container mx-auto px-4 py-8">
          <div className="text-center py-12">
            <p className="text-muted-foreground">{t('tankoubon.notFound')}</p>
            <Button onClick={() => router.push('/')} className="mt-4">
              <ArrowLeft className="w-4 h-4 mr-2" />
              {t('common.back')}
            </Button>
          </div>
        </main>
      </div>
    );
  }

  const allTags = tankoubon.tags
    ? tankoubon.tags.split(',').map((tag) => tag.trim()).filter((tag) => tag)
    : [];

  const archiveCount = typeof tankoubon.archive_count === 'number' ? tankoubon.archive_count : archives.length;
  const totalPages = typeof tankoubon.pagecount === 'number' ? tankoubon.pagecount : 0;
  const progressPercent = Math.max(0, Math.min(100, Math.round(tankoubon.progress ?? 0)));
  const coverUrl = `/api/tankoubons/${tankoubon.tankoubon_id}/thumbnail`;

  return (
    <div className="min-h-screen bg-background pb-20 lg:pb-0">
      <main className="container mx-auto px-4 py-8">
        {/* Header / hero */}
        <div className="relative mb-8">
          <div className="relative rounded-2xl border bg-card/70 backdrop-blur">
            <div className="p-4 md:p-5">
              <div className="flex flex-col gap-6 md:flex-row md:items-start md:justify-between">
                <div className="flex min-w-0 gap-4">
                  <div className="relative h-40 w-28 shrink-0 overflow-hidden rounded-xl border bg-muted md:h-52 md:w-36">
                    <Image
                      src={coverUrl}
                      alt={tankoubon.name}
                      fill
                      className="object-cover"
                      sizes="(max-width: 768px) 112px, 144px"
                      // Tankoubon thumbnail endpoint may redirect (to assets or archive thumbnail),
                      // and may serve non-avif images; bypass optimizer to avoid strict content-type checks.
                      unoptimized
                    />
                  </div>

                  <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-3">
                    <Badge className="bg-primary">
                      <BookOpen className="w-3 h-3 mr-1" />
                      {t('tankoubon.collection')}
                    </Badge>
                    <h1 className="text-xl md:text-2xl font-bold tracking-tight break-words">
                      {tankoubon.name}
                    </h1>
                  </div>

                  {tankoubon.summary ? (
                    <p className="mt-2 text-sm text-muted-foreground max-w-3xl line-clamp-2">
                      {tankoubon.summary}
                    </p>
                  ) : null}

                  {allTags.length > 0 ? (
                    <div className="mt-3 flex flex-wrap gap-2">
                      {allTags.map((tag, index) => (
                        <Badge key={index} variant="secondary" className="max-w-full" title={tag}>
                          <span className="truncate">{displayTag(tag)}</span>
                        </Badge>
                      ))}
                    </div>
                  ) : null}
                  </div>
                </div>

                <div className="flex shrink-0 flex-wrap items-center gap-2">
                  <Button
                    size="sm"
                    variant="outline"
                    className={`px-3 ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
                    title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
                    disabled={favoriteLoading}
                    onClick={handleFavoriteClick}
                  >
                    <Heart className={`w-4 h-4 ${isFavorite ? 'fill-current' : ''}`} />
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-9 w-9 p-0"
                    title={t('common.edit')}
                    onClick={() => setEditDialogOpen(true)}
                  >
                    <Edit className="w-4 h-4" />
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-9 w-9 p-0 text-destructive"
                    title={t('common.delete')}
                    onClick={() => setDeleteDialogOpen(true)}
                  >
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
              </div>

              <div className="mt-4 grid gap-2 sm:grid-cols-3">
                <div className="rounded-xl border bg-background/60 p-3">
                  <p className="text-xs text-muted-foreground">{t('tankoubon.archiveCount')}</p>
                  <p className="mt-0.5 text-xl font-semibold tabular-nums">{archiveCount}</p>
                </div>
                <div className="rounded-xl border bg-background/60 p-3">
                  <p className="text-xs text-muted-foreground">{t('tankoubon.totalPagesLabel')}</p>
                  <p className="mt-0.5 text-xl font-semibold tabular-nums">{totalPages}</p>
                </div>
                <div className="rounded-xl border bg-background/60 p-3">
                  <div className="flex items-center justify-between">
                    <p className="text-xs text-muted-foreground">{t('tankoubon.progress')}</p>
                    <p className="text-xs text-muted-foreground tabular-nums">{progressPercent}%</p>
                  </div>
                  <Progress className="mt-1.5" value={progressPercent} />
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Archives section */}
        <div className="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-baseline gap-2">
            <h2 className="text-xl font-semibold">{t('tankoubon.archivesTitle')}</h2>
            <Badge variant="secondary" className="tabular-nums">
              {archiveFilter.trim() ? `${filteredArchives.length}/${archives.length}` : String(archives.length)}
            </Badge>
          </div>

          <div className="flex w-full gap-2 sm:w-auto">
            <div className="relative flex-1 sm:w-72">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={archiveFilter}
                onChange={(e) => setArchiveFilter(e.target.value)}
                placeholder={t('tankoubon.filterPlaceholder')}
                className="pl-9"
              />
            </div>
            <Button onClick={() => setAddArchiveDialogOpen(true)} className="shrink-0">
              <Plus className="w-4 h-4 mr-2" />
              {t('tankoubon.addArchive')}
            </Button>
          </div>
        </div>

        {archivesLoading ? (
          <div className="flex justify-center items-center h-32">
            <Spinner />
          </div>
        ) : archives.length === 0 ? (
          <div className="text-center py-12 bg-muted/50 rounded-lg">
            <p className="text-muted-foreground mb-4">{t('tankoubon.noArchives')}</p>
            <Button onClick={() => setAddArchiveDialogOpen(true)}>
              <Plus className="w-4 h-4 mr-2" />
              {t('tankoubon.addArchive')}
            </Button>
          </div>
        ) : filteredArchives.length === 0 ? (
          <div className="text-center py-12 bg-muted/30 rounded-lg border">
            <p className="text-muted-foreground mb-1">{t('tankoubon.noMatchingArchives')}</p>
            <Button variant="ghost" onClick={() => setArchiveFilter('')}>
              {t('common.reset')}
            </Button>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9 gap-4">
              {filteredArchives.map((archive, index) => {
                const isRemoving = removingArcids.has(archive.arcid);
                return (
                  <div key={archive.arcid} className="relative group">
                    <ArchiveCard archive={archive} index={index} />
                    <Button
                      type="button"
                      variant="secondary"
                      size="icon"
                      className="absolute right-2 top-2 h-8 w-8 rounded-full opacity-0 shadow-sm transition-opacity group-hover:opacity-100 focus:opacity-100"
                      title={t('tankoubon.removeArchive')}
                      disabled={isRemoving}
                      onClick={() => {
                        setRemoveTarget(archive);
                        setRemoveDialogOpen(true);
                      }}
                    >
                      {isRemoving ? <Spinner size="sm" /> : <Trash2 className="h-4 w-4" />}
                    </Button>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        <ConfirmDialog
          open={removeDialogOpen}
          onOpenChange={(open) => {
            setRemoveDialogOpen(open);
            if (!open) setRemoveTarget(null);
          }}
          title={t('tankoubon.removeArchiveConfirmTitle')}
          description={t('tankoubon.removeArchiveConfirmMessage').replace('{title}', removeTarget?.title ?? '')}
          onConfirm={confirmRemoveArchive}
          confirmText={t('common.remove')}
          cancelText={t('common.cancel')}
          variant="destructive"
        />

        {/* Edit Dialog */}
        <Dialog open={editDialogOpen} onOpenChange={setEditDialogOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>{t('tankoubon.editTankoubon')}</DialogTitle>
            </DialogHeader>
            <DialogBody className="pt-0">
              <div className="space-y-4">
                <div>
                  <label className="text-sm font-medium">{t('tankoubon.name')}</label>
                  <Input
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    placeholder={t('tankoubon.namePlaceholder')}
                  />
                </div>
                <div>
                  <label className="text-sm font-medium">{t('tankoubon.summary')}</label>
                  <Textarea
                    value={editSummary}
                    onChange={(e) => setEditSummary(e.target.value)}
                    placeholder={t('tankoubon.summaryPlaceholder')}
                    rows={3}
                  />
                </div>
                <div>
                  <label className="text-sm font-medium">{t('tankoubon.metadataPluginLabel')}</label>
                  <div className="mt-2 flex flex-col gap-2">
                    <div className="flex flex-col sm:flex-row gap-2">
                      <div className="sm:w-[220px]">
                        <Select value={selectedMetadataPlugin} onValueChange={setSelectedMetadataPlugin}>
                          <SelectTrigger disabled={saving || isMetadataPluginRunning || metadataPlugins.length === 0}>
                            <SelectValue placeholder={t('archive.metadataPluginSelectPlaceholder')} />
                          </SelectTrigger>
                          <SelectContent>
                            {metadataPlugins.map((p) => (
                              <SelectItem key={p.namespace} value={p.namespace}>
                                {p.name} ({p.namespace})
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <Input
                        value={metadataPluginParam}
                        onChange={(e) => setMetadataPluginParam(e.target.value)}
                        disabled={saving || isMetadataPluginRunning}
                        placeholder={t('archive.metadataPluginParamPlaceholder')}
                      />
                      <Button
                        type="button"
                        onClick={runMetadataPlugin}
                        disabled={saving || isMetadataPluginRunning || metadataPlugins.length === 0 || !selectedMetadataPlugin}
                      >
                        <Play className="w-4 h-4 mr-2" />
                        {isMetadataPluginRunning ? t('archive.metadataPluginRunning') : t('archive.metadataPluginRun')}
                      </Button>
                    </div>
                    {(metadataPluginProgress !== null || metadataPluginMessage) && (
                      <div className="text-xs text-muted-foreground flex items-center justify-between gap-2">
                        <span className="truncate" title={metadataPluginMessage}>
                          {metadataPluginMessage || ''}
                        </span>
                        {metadataPluginProgress !== null && (
                          <span className="tabular-nums">{Math.max(0, Math.min(100, metadataPluginProgress))}%</span>
                        )}
                      </div>
                    )}
                    {metadataPlugins.length === 0 && (
                      <div className="text-xs text-muted-foreground">{t('archive.metadataPluginNoPlugins')}</div>
                    )}
                  </div>
                </div>
                <div>
                  <label className="text-sm font-medium">{t('tankoubon.tags')}</label>
                  <TagInput
                    value={editTags}
                    onChange={setEditTags}
                    placeholder={t('tankoubon.tagsPlaceholder')}
                    disabled={saving}
                  />
                  <p className="text-xs text-muted-foreground mt-1">{t('tankoubon.tagsHint')}</p>
                </div>
              </div>
            </DialogBody>
            <DialogFooter>
              <Button variant="outline" onClick={() => setEditDialogOpen(false)}>
                {t('common.cancel')}
              </Button>
              <Button onClick={handleEdit} disabled={saving || !editName.trim()}>
                {saving ? <Spinner size="sm" className="mr-2" /> : null}
                {t('common.save')}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        {/* Delete Confirmation Dialog */}
        <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>{t('tankoubon.deleteConfirmTitle')}</AlertDialogTitle>
              <AlertDialogDescription>
                {t('tankoubon.deleteConfirmMessage')}
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>{t('common.cancel')}</AlertDialogCancel>
              <AlertDialogAction
                onClick={handleDelete}
                className="bg-destructive text-destructive-foreground"
                disabled={deleting}
              >
                {deleting ? <Spinner size="sm" className="mr-2" /> : null}
                {t('common.delete')}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>

        {/* Add Archive Dialog */}
        <Dialog open={addArchiveDialogOpen} onOpenChange={setAddArchiveDialogOpen}>
          <DialogContent className="max-w-3xl max-h-[80vh]">
            <DialogHeader>
              <DialogTitle>{t('tankoubon.addArchive')}</DialogTitle>
            </DialogHeader>
            <DialogBody className="pt-0 space-y-4">
              <div className="flex gap-2">
                <Input
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder={t('tankoubon.searchArchivesPlaceholder')}
                  onKeyDown={(e) => e.key === 'Enter' && searchArchives()}
                />
                <Button onClick={searchArchives} disabled={searchLoading}>
                  {searchLoading ? <Spinner size="sm" /> : t('common.search')}
                </Button>
              </div>

              {availableArchives.length > 0 && (
                <div className="border rounded-lg p-4">
                  <p className="text-sm text-muted-foreground mb-3">
                    {t('tankoubon.selectArchives')} ({selectedArchives.size} {t('common.selected')})
                  </p>
                  <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 max-h-96 overflow-y-auto">
                    {availableArchives.map((archive) => (
                      <div
                        key={archive.arcid}
                        className={`p-3 border rounded-lg cursor-pointer transition-colors ${
                          selectedArchives.has(archive.arcid)
                            ? 'border-primary bg-primary/10'
                            : 'hover:border-muted-foreground'
                        }`}
                        onClick={() => toggleArchiveSelection(archive.arcid)}
                      >
                        <p className="text-sm font-medium line-clamp-2">{archive.title}</p>
                        <p className="text-xs text-muted-foreground mt-1">
                          {archive.pagecount} {t('archive.pages').replace('{count}', '')}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {availableArchives.length === 0 && searchQuery && !searchLoading && (
                <p className="text-center text-muted-foreground py-8">{t('tankoubon.noArchivesFound')}</p>
              )}
            </DialogBody>
            <DialogFooter>
              <Button variant="outline" onClick={() => setAddArchiveDialogOpen(false)}>
                {t('common.cancel')}
              </Button>
              <Button
                onClick={handleAddArchives}
                disabled={addingArchives || selectedArchives.size === 0}
              >
                {addingArchives ? <Spinner size="sm" className="mr-2" /> : null}
                {t('tankoubon.addSelected')} ({selectedArchives.size})
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </main>

      <MobileBottomNav />
    </div>
  );
}

export default function TankoubonDetailPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-background pb-20 lg:pb-0">
        <main className="container mx-auto px-4 py-8">
          <div className="flex items-center justify-center py-12">
            <Spinner size="lg" />
          </div>
        </main>
        <MobileBottomNav />
      </div>
    }>
      <TankoubonDetailContent />
    </Suspense>
  );
}
