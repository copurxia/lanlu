'use client';

import { useState, useEffect, useMemo } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Spinner } from '@/components/ui/spinner';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogTrigger,
} from '@/components/ui/dialog';
import { TankoubonService } from '@/lib/tankoubon-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { BookOpen, Plus, Check, X, Search } from 'lucide-react';
import type { Tankoubon } from '@/types/tankoubon';

interface AddToTankoubonDialogProps {
  archiveId: string;
  archiveTitle: string;
  onAdded?: () => void;
  trigger?: React.ReactElement;
  fullWidth?: boolean;
}

export function AddToTankoubonDialog({
  archiveId,
  archiveTitle,
  onAdded,
  trigger,
  fullWidth = false,
}: AddToTankoubonDialogProps) {
  const { t } = useLanguage();
  const [open, setOpen] = useState(false);
  const [tankoubons, setTankoubons] = useState<Tankoubon[]>([]);
  const [loading, setLoading] = useState(false);
  const [adding, setAdding] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [newTankoubonName, setNewTankoubonName] = useState('');
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [query, setQuery] = useState('');

  const filteredTankoubons = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return tankoubons;
    return tankoubons.filter((tankoubon) => String(tankoubon.name || '').toLowerCase().includes(q));
  }, [query, tankoubons]);

  function handleOpenChange(newOpen: boolean) {
    setOpen(newOpen);
    if (!newOpen) {
      setShowCreateForm(false);
      setNewTankoubonName('');
      setQuery('');
    }
  }

  // Fetch all tankoubons
  const fetchTankoubons = async () => {
    try {
      setLoading(true);
      const data = await TankoubonService.getAllTankoubons();
      setTankoubons(data);
    } catch (error) {
      console.error('Failed to fetch tankoubons:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (open) {
      fetchTankoubons();
    }
  }, [open]);

  // Add archive to existing tankoubon
  const handleAddToTankoubon = async (tankoubonId: string) => {
    try {
      setAdding(tankoubonId);
      await TankoubonService.addArchiveToTankoubon(tankoubonId, archiveId);
      handleOpenChange(false);
      onAdded?.();
    } catch (error) {
      console.error('Failed to add archive to tankoubon:', error);
    } finally {
      setAdding(null);
    }
  };

  // Create new tankoubon and add archive
  const handleCreateAndAdd = async () => {
    if (!newTankoubonName.trim()) return;

    try {
      setCreating(true);
      const result = await TankoubonService.createTankoubon({ name: newTankoubonName.trim() });

      if (result.success && result.tankoubon_id) {
        await TankoubonService.addArchiveToTankoubon(result.tankoubon_id, archiveId);
        setNewTankoubonName('');
        setShowCreateForm(false);
        handleOpenChange(false);
        onAdded?.();
      }
    } catch (error) {
      console.error('Failed to create tankoubon:', error);
    } finally {
      setCreating(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        {trigger ?? (
          <Button variant="outline" size="sm" className={fullWidth ? 'w-full' : undefined}>
            <BookOpen className="w-4 h-4 mr-2" />
            {t('tankoubon.addToCollection')}
          </Button>
        )}
      </DialogTrigger>
      <DialogContent className="w-[92vw] max-w-xl p-0">
        <div className="flex flex-col max-h-[85vh]">
          <div className="flex items-start justify-between gap-4 px-6 py-4 border-b">
            <div className="min-w-0 space-y-1">
              <DialogTitle className="flex items-center gap-2">
                <BookOpen className="w-5 h-5" />
                {t('tankoubon.addToCollection')}
              </DialogTitle>
              <DialogDescription className="line-clamp-2 break-words">
                {t('tankoubon.addArchiveToCollection').replace('{title}', archiveTitle)}
              </DialogDescription>
            </div>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              onClick={() => handleOpenChange(false)}
              className="shrink-0"
              aria-label={t('common.close')}
            >
              <X className="w-4 h-4" />
            </Button>
          </div>

          <div className="flex-1 overflow-y-auto px-6 py-4 space-y-4">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={t('tankoubon.searchCollectionsPlaceholder')}
                className="pl-9"
              />
            </div>

            <div className="rounded-lg border p-4">
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-sm font-medium">{t('tankoubon.createNew')}</p>
                  <p className="text-xs text-muted-foreground mt-1">{t('tankoubon.createNewAndAddHint')}</p>
                </div>
                <Button
                  type="button"
                  variant={showCreateForm ? 'secondary' : 'outline'}
                  onClick={() => {
                    const next = !showCreateForm;
                    setShowCreateForm(next);
                    if (!next) setNewTankoubonName('');
                  }}
                  className="shrink-0"
                >
                  <Plus className="w-4 h-4 mr-2" />
                  {t('tankoubon.createNewCollection')}
                </Button>
              </div>

              {showCreateForm ? (
                <div className="mt-4 space-y-3">
                  <Input
                    value={newTankoubonName}
                    onChange={(e) => setNewTankoubonName(e.target.value)}
                    placeholder={t('tankoubon.namePlaceholder')}
                    onKeyDown={(e) => e.key === 'Enter' && handleCreateAndAdd()}
                    disabled={creating}
                  />
                  <div className="flex justify-end gap-2">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => {
                        setShowCreateForm(false);
                        setNewTankoubonName('');
                      }}
                      disabled={creating}
                    >
                      {t('common.cancel')}
                    </Button>
                    <Button
                      type="button"
                      onClick={handleCreateAndAdd}
                      disabled={creating || !newTankoubonName.trim()}
                    >
                      {creating ? <Spinner size="sm" className="mr-2" /> : <Plus className="w-4 h-4 mr-2" />}
                      {creating ? t('common.creating') : t('tankoubon.create')}
                    </Button>
                  </div>
                </div>
              ) : null}
            </div>

            <div className="rounded-lg border overflow-hidden">
              <div className="flex items-center justify-between gap-2 px-4 py-3 bg-muted/30 border-b">
                <p className="text-sm font-medium">{t('tankoubon.existingCollections')}</p>
                <p className="text-xs text-muted-foreground tabular-nums">
                  {filteredTankoubons.length}/{tankoubons.length}
                </p>
              </div>

              {loading ? (
                <div className="flex items-center justify-center py-14">
                  <Spinner />
                </div>
              ) : filteredTankoubons.length === 0 ? (
                <div className="py-14 text-center text-sm text-muted-foreground">
                  {tankoubons.length === 0 ? t('tankoubon.noCollectionsYet') : t('tankoubon.noCollectionsFound')}
                </div>
              ) : (
                <div className="max-h-[42vh] overflow-y-auto divide-y">
                  {filteredTankoubons.map((tankoubon) => {
                    const isInTankoubon = tankoubon.archives?.includes(archiveId);
                    const count = tankoubon.archive_count || tankoubon.archives?.length || 0;

                    return (
                      <div
                        key={tankoubon.tankoubon_id}
                        className="flex items-center justify-between gap-3 px-4 py-3"
                      >
                        <div className="min-w-0 flex-1">
                          <p className="font-medium truncate">{tankoubon.name}</p>
                          <p className="text-xs text-muted-foreground">
                            {count} {t('tankoubon.archives')}
                          </p>
                        </div>

                        {isInTankoubon ? (
                          <Badge variant="secondary" className="shrink-0">
                            <Check className="w-3 h-3 mr-1" />
                            {t('tankoubon.alreadyAdded')}
                          </Badge>
                        ) : (
                          <Button
                            type="button"
                            size="sm"
                            onClick={() => handleAddToTankoubon(tankoubon.tankoubon_id)}
                            disabled={adding === tankoubon.tankoubon_id}
                            className="shrink-0"
                          >
                            {adding === tankoubon.tankoubon_id ? <Spinner size="sm" /> : t('common.add')}
                          </Button>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>

          <div className="px-6 py-4 border-t">
            <DialogFooter className="px-0 pb-0">
              <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
                {t('common.close')}
              </Button>
            </DialogFooter>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
