'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Spinner } from '@/components/ui/spinner';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogTrigger,
} from '@/components/ui/dialog';
import { TankoubonService } from '@/lib/tankoubon-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { Plus, BookOpen } from 'lucide-react';

interface TankoubonManagementDialogProps {
  onCreated?: (tankoubonId: string) => void;
  trigger?: React.ReactNode;
}

export function TankoubonManagementDialog({
  onCreated,
  trigger,
}: TankoubonManagementDialogProps) {
  const { t } = useLanguage();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState('');
  const [summary, setSummary] = useState('');
  const [tags, setTags] = useState('');
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState('');

  const handleCreate = async () => {
    if (!name.trim()) {
      setError(t('tankoubon.nameRequired'));
      return;
    }

    try {
      setCreating(true);
      setError('');

      const result = await TankoubonService.createTankoubon({ name: name.trim() });

      if (result.success && result.tankoubon_id) {
        // If summary or tags provided, update the tankoubon
        if (summary.trim() || tags.trim()) {
          await TankoubonService.updateTankoubon(result.tankoubon_id, {
            name: name.trim(),
            summary: summary.trim(),
            tags: tags.trim(),
          });
        }

        // Reset form
        setName('');
        setSummary('');
        setTags('');
        setOpen(false);

        // Callback
        onCreated?.(result.tankoubon_id);
      } else {
        setError(t('tankoubon.createFailed'));
      }
    } catch (err) {
      console.error('Failed to create tankoubon:', err);
      setError(t('tankoubon.createFailed'));
    } finally {
      setCreating(false);
    }
  };

  const handleOpenChange = (newOpen: boolean) => {
    setOpen(newOpen);
    if (!newOpen) {
      // Reset form when closing
      setName('');
      setSummary('');
      setTags('');
      setError('');
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        {trigger || (
          <Button>
            <Plus className="w-4 h-4 mr-2" />
            {t('tankoubon.createNew')}
          </Button>
        )}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <BookOpen className="w-5 h-5" />
            {t('tankoubon.createNew')}
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div>
            <label className="text-sm font-medium">
              {t('tankoubon.name')} <span className="text-destructive">*</span>
            </label>
            <Input
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                setError('');
              }}
              placeholder={t('tankoubon.namePlaceholder')}
              className="mt-1"
            />
          </div>

          <div>
            <label className="text-sm font-medium">{t('tankoubon.summary')}</label>
            <Textarea
              value={summary}
              onChange={(e) => setSummary(e.target.value)}
              placeholder={t('tankoubon.summaryPlaceholder')}
              rows={3}
              className="mt-1"
            />
          </div>

          <div>
            <label className="text-sm font-medium">{t('tankoubon.tags')}</label>
            <Input
              value={tags}
              onChange={(e) => setTags(e.target.value)}
              placeholder={t('tankoubon.tagsPlaceholder')}
              className="mt-1"
            />
            <p className="text-xs text-muted-foreground mt-1">
              {t('tankoubon.tagsHint')}
            </p>
          </div>

          {error && (
            <p className="text-sm text-destructive">{error}</p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={creating}>
            {t('common.cancel')}
          </Button>
          <Button onClick={handleCreate} disabled={creating || !name.trim()}>
            {creating ? <Spinner size="sm" className="mr-2" /> : null}
            {t('tankoubon.create')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
