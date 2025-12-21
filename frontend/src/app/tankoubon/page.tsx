'use client';

import { useState, useEffect, useCallback, Suspense } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { Header } from '@/components/layout/Header';
import { ArchiveGrid } from '@/components/archive/ArchiveGrid';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Spinner } from '@/components/ui/spinner';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
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
import { TankoubonService } from '@/lib/tankoubon-service';
import { ArchiveService } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { logger } from '@/lib/logger';
import { ArrowLeft, Edit, Trash2, Plus, BookOpen, Heart } from 'lucide-react';
import type { Tankoubon } from '@/types/tankoubon';
import type { Archive } from '@/types/archive';

function TankoubonDetailContent() {
  const { t } = useLanguage();
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
  const [editTags, setEditTags] = useState('');
  const [saving, setSaving] = useState(false);

  // Delete dialog state
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);

  // Add archive dialog state
  const [addArchiveDialogOpen, setAddArchiveDialogOpen] = useState(false);
  const [availableArchives, setAvailableArchives] = useState<Archive[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchLoading, setSearchLoading] = useState(false);
  const [selectedArchives, setSelectedArchives] = useState<Set<string>>(new Set());
  const [addingArchives, setAddingArchives] = useState(false);

  // Fetch tankoubon details
  const fetchTankoubon = useCallback(async () => {
    if (!tankoubonId) return;

    try {
      setLoading(true);
      const data = await TankoubonService.getTankoubonById(tankoubonId);
      setTankoubon(data);
      setIsFavorite(data.isfavorite || false);

      // Set edit form values
      setEditName(data.name);
      setEditSummary(data.summary || '');
      setEditTags(data.tags || '');
    } catch (error) {
      logger.apiError('fetch tankoubon', error);
    } finally {
      setLoading(false);
    }
  }, [tankoubonId]);

  // Fetch archives in tankoubon
  const fetchArchives = useCallback(async () => {
    if (!tankoubon?.archives || tankoubon.archives.length === 0) {
      setArchives([]);
      return;
    }

    try {
      setArchivesLoading(true);
      // Fetch each archive's details
      const archivePromises = tankoubon.archives.map(async (arcid) => {
        try {
          const archive = await ArchiveService.getArchive(arcid);
          return archive;
        } catch {
          return null;
        }
      });

      const results = await Promise.all(archivePromises);
      setArchives(results.filter((a): a is Archive => a !== null));
    } catch (error) {
      logger.apiError('fetch archives', error);
    } finally {
      setArchivesLoading(false);
    }
  }, [tankoubon?.archives]);

  useEffect(() => {
    fetchTankoubon();
  }, [fetchTankoubon]);

  useEffect(() => {
    if (tankoubon) {
      fetchArchives();
    }
  }, [tankoubon, fetchArchives]);

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
        tags: editTags,
      });
      setEditDialogOpen(false);
      fetchTankoubon();
    } catch (error) {
      logger.operationFailed('update tankoubon', error);
    } finally {
      setSaving(false);
    }
  };

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
      await TankoubonService.removeArchiveFromTankoubon(tankoubon.tankoubon_id, arcid);
      fetchTankoubon();
    } catch (error) {
      logger.operationFailed('remove archive', error);
    }
  };

  // Search for archives to add
  const searchArchives = async () => {
    try {
      setSearchLoading(true);
      const result = await ArchiveService.search({
        filter: searchQuery,
        count: 50,
        groupby_tanks: false, // Don't group by tanks when searching for archives to add
      });

      // Filter out archives already in this tankoubon
      const existingArcids = new Set(tankoubon?.archives || []);
      const filtered = result.data.filter((a: Archive) => !existingArcids.has(a.arcid));
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

  if (loading) {
    return (
      <div className="min-h-screen bg-background">
        <Header />
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
        <Header />
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

  return (
    <div className="min-h-screen bg-background">
      <Header />
      <main className="container mx-auto px-4 py-8">
        {/* Back button */}
        <Button variant="ghost" onClick={() => router.push('/')} className="mb-6">
          <ArrowLeft className="w-4 h-4 mr-2" />
          {t('common.back')}
        </Button>

        {/* Tankoubon header */}
        <div className="bg-card rounded-lg p-6 mb-8 border">
          <div className="flex items-start justify-between">
            <div className="flex-1">
              <div className="flex items-center gap-3 mb-2">
                <Badge className="bg-primary">
                  <BookOpen className="w-3 h-3 mr-1" />
                  {t('tankoubon.collection')}
                </Badge>
                <h1 className="text-2xl font-bold">{tankoubon.name}</h1>
              </div>

              {tankoubon.summary && (
                <p className="text-muted-foreground mb-4">{tankoubon.summary}</p>
              )}

              {allTags.length > 0 && (
                <div className="flex flex-wrap gap-2 mb-4">
                  {allTags.map((tag, index) => (
                    <Badge key={index} variant="secondary">
                      {tag}
                    </Badge>
                  ))}
                </div>
              )}

              <div className="flex gap-6 text-sm text-muted-foreground">
                <span>
                  {t('tankoubon.archiveCount')}: {tankoubon.archive_count || archives.length}
                </span>
                <span>
                  {t('tankoubon.totalPages').replace('{count}', String(tankoubon.pagecount || 0))}
                </span>
                {(tankoubon.progress ?? 0) > 0 && (
                  <span>
                    {t('common.progress')}: {Math.round(tankoubon.progress ?? 0)}%
                  </span>
                )}
              </div>
            </div>

            <div className="flex gap-2">
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
              <Button variant="outline" size="sm" onClick={() => setEditDialogOpen(true)}>
                <Edit className="w-4 h-4 mr-2" />
                {t('common.edit')}
              </Button>
              <Button
                variant="outline"
                size="sm"
                className="text-destructive"
                onClick={() => setDeleteDialogOpen(true)}
              >
                <Trash2 className="w-4 h-4 mr-2" />
                {t('common.delete')}
              </Button>
            </div>
          </div>
        </div>

        {/* Archives section */}
        <div className="mb-6 flex items-center justify-between">
          <h2 className="text-xl font-semibold">
            {archives.length} {t('tankoubon.archives')}
          </h2>
          <Button onClick={() => setAddArchiveDialogOpen(true)}>
            <Plus className="w-4 h-4 mr-2" />
            {t('tankoubon.addArchive')}
          </Button>
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
        ) : (
          <div className="space-y-4">
            <ArchiveGrid archives={archives} variant="default" />

            {/* Remove buttons for each archive */}
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
              {archives.map((archive) => (
                <Button
                  key={archive.arcid}
                  variant="outline"
                  size="sm"
                  className="text-destructive"
                  onClick={() => handleRemoveArchive(archive.arcid)}
                >
                  <Trash2 className="w-3 h-3 mr-1" />
                  {t('tankoubon.removeArchive')}
                </Button>
              ))}
            </div>
          </div>
        )}

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
	                  <label className="text-sm font-medium">{t('tankoubon.tags')}</label>
	                  <Input
	                    value={editTags}
	                    onChange={(e) => setEditTags(e.target.value)}
	                    placeholder={t('tankoubon.tagsPlaceholder')}
	                  />
	                  <p className="text-xs text-muted-foreground mt-1">
	                    {t('tankoubon.tagsHint')}
	                  </p>
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
	                <p className="text-center text-muted-foreground py-8">
	                  {t('tankoubon.noArchivesFound')}
	                </p>
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
    </div>
  );
}

export default function TankoubonDetailPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-background">
        <Header />
        <main className="container mx-auto px-4 py-8">
          <div className="flex items-center justify-center py-12">
            <Spinner size="lg" />
          </div>
        </main>
      </div>
    }>
      <TankoubonDetailContent />
    </Suspense>
  );
}
