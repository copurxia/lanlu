'use client';

import { useState, useEffect, useMemo, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Spinner } from '@/components/ui/spinner';
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogFooter,
  DialogTrigger,
} from '@/components/ui/dialog';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { useConfirm } from '@/hooks/use-confirm';
import { useToast } from '@/hooks/use-toast';
import { BookOpen, Plus, Search } from 'lucide-react';
import type { Tankoubon } from '@/types/tankoubon';

interface AddToTankoubonDialogProps {
  archiveId: string;
  onAdded?: () => void;
  trigger?: React.ReactElement;
  fullWidth?: boolean;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}

export function AddToTankoubonDialog({
  archiveId,
  onAdded,
  trigger,
  fullWidth = false,
  open: controlledOpen,
  onOpenChange: controlledOnOpenChange,
}: AddToTankoubonDialogProps) {
  const { t } = useLanguage();
  const { confirm, ConfirmComponent } = useConfirm();
  const { error: showError, success: showSuccess } = useToast();
  const isControlled = typeof controlledOpen === 'boolean';
  const [openInternal, setOpenInternal] = useState(false);
  const open = isControlled ? (controlledOpen as boolean) : openInternal;
  const [tankoubons, setTankoubons] = useState<Tankoubon[]>([]);
  const [loading, setLoading] = useState(false);
  const [adding, setAdding] = useState<string | null>(null);
  const [removing, setRemoving] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [newTankoubonName, setNewTankoubonName] = useState('');
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [query, setQuery] = useState('');
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = useState(false);

  // 设置mounted状态
  useEffect(() => {
    setMounted(true);
  }, []);

  const filteredTankoubons = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return tankoubons;
    return tankoubons.filter((tankoubon) => String(tankoubon.name || '').toLowerCase().includes(q));
  }, [query, tankoubons]);

  function handleOpenChange(newOpen: boolean) {
    if (!mounted) return;
    if (isControlled) {
      controlledOnOpenChange?.(newOpen);
    } else {
      setOpenInternal(newOpen);
    }
    if (!newOpen) {
      setShowCreateForm(false);
      setNewTankoubonName('');
      setQuery('');
    }
  }

  // Fetch all tankoubons
  const fetchTankoubons = useCallback(async () => {
    if (!mounted) return;
    try {
      setLoading(true);
      const data = await TankoubonService.getAllTankoubons();
      setTankoubons(data);
    } catch (error) {
      console.error('Failed to fetch tankoubons:', error);
    } finally {
      setLoading(false);
    }
  }, [mounted]);

  useEffect(() => {
    if (open && mounted) {
      fetchTankoubons();
    }
  }, [open, mounted, fetchTankoubons]);

  // Add archive to existing tankoubon
  const handleAddToTankoubon = async (tankoubonId: string) => {
    if (!mounted) return;
    try {
      setAdding(tankoubonId);
      const result = await TankoubonService.addArchiveToTankoubon(tankoubonId, archiveId);

      if (result.success) {
        handleOpenChange(false);
        onAdded?.();
        showSuccess('成功添加到合集');
      } else {
        console.error('添加失败:', result.error);
        showError(`添加失败: ${result.error || '未知错误'}`);
      }
    } catch (error) {
      console.error('Failed to add archive to tankoubon:', error);
      showError('添加失败: 网络错误或服务器异常');
    } finally {
      setAdding(null);
    }
  };

  // Create new tankoubon and add archive
  const handleCreateAndAdd = async () => {
    if (!mounted || !newTankoubonName.trim()) return;

    try {
      setCreating(true);
      const result = await TankoubonService.createTankoubon({ name: newTankoubonName.trim() });

      if (result.success && result.tankoubon_id) {
        const addResult = await TankoubonService.addArchiveToTankoubon(result.tankoubon_id, archiveId);

        if (addResult.success) {
          setNewTankoubonName('');
          setShowCreateForm(false);
          handleOpenChange(false);
          onAdded?.();
          showSuccess('成功创建合集并添加');
        } else {
          console.error('添加失败:', addResult.error);
          showError(`添加失败: ${addResult.error || '未知错误'}`);
        }
      }
    } catch (error) {
      console.error('Failed to create tankoubon:', error);
      showError('创建失败: 网络错误或服务器异常');
    } finally {
      setCreating(false);
    }
  };

  // Remove archive from tankoubon with confirmation
  const handleRemoveFromTankoubon = async (tankoubonId: string) => {
    if (!mounted) return;

    // Get tankoubon name for confirmation message
    const tankoubonName = tankoubons.find(t => t.tankoubon_id === tankoubonId)?.name || '';
    const confirmed = await confirm({
      title: '确认移除',
      description: `确定要从合集"${tankoubonName}"中移除当前档案吗？`,
      confirmText: '移除',
      cancelText: '取消',
      variant: 'destructive',
    });

    if (!confirmed) return;

    try {
      setRemoving(tankoubonId);
      await TankoubonService.removeArchiveFromTankoubon(tankoubonId, archiveId);

      // 刷新合集列表以更新UI
      await fetchTankoubons();
      showSuccess('成功从合集中移除');
    } catch (error) {
      console.error('Failed to remove archive from tankoubon:', error);
      showError('移除失败: 网络错误或服务器异常');
    } finally {
      setRemoving(null);
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      {/* When controlled, the parent may choose to render no trigger and toggle `open` itself. */}
      {!isControlled ? (
        <DialogTrigger asChild>
          {trigger ?? (
            <Button variant="outline" size="sm" className={fullWidth ? 'w-full' : undefined}>
              <BookOpen className="w-4 h-4 mr-2" />
              {t('tankoubon.addToCollection')}
            </Button>
          )}
        </DialogTrigger>
      ) : trigger ? (
        <DialogTrigger asChild>{trigger}</DialogTrigger>
      ) : null}
      <DialogContent size="fluid">
        <DialogBody>
          <div className="space-y-4">
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
                          <Button
                            type="button"
                            variant="destructive"
                            size="sm"
                            onClick={() => handleRemoveFromTankoubon(tankoubon.tankoubon_id)}
                            disabled={removing === tankoubon.tankoubon_id}
                            className="shrink-0"
                          >
                            {removing === tankoubon.tankoubon_id ? <Spinner size="sm" /> : t('common.remove')}
                          </Button>
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
        </DialogBody>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
            {t('common.close')}
          </Button>
        </DialogFooter>
      </DialogContent>
      <ConfirmComponent />
    </Dialog>
  );
}
