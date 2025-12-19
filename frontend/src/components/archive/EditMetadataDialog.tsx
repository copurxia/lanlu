'use client';

import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { TagInput } from '@/components/ui/tag-input';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { ArchiveMetadata } from '@/types/archive';
import { ArchiveService } from '@/lib/archive-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';

interface EditMetadataDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  metadata: ArchiveMetadata | null;
  onMetadataUpdated: () => void;
}

export function EditMetadataDialog({
  open,
  onOpenChange,
  metadata,
  onMetadataUpdated,
}: EditMetadataDialogProps) {
  const { t } = useLanguage();
  const { token } = useAuth();
  const { error: showError } = useToast();
  const [isLoading, setIsLoading] = useState(false);
  const [formData, setFormData] = useState({
    title: '',
    tags: [] as string[],
    summary: '',
  });

  // 当对话框打开或 metadata 变化时，更新表单数据
  useEffect(() => {
    if (metadata && open) {
      setFormData({
        title: metadata.title || '',
        tags: metadata.tags ? metadata.tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [],
        summary: metadata.summary || '',
      });
    }
  }, [metadata, open]);

  const handleInputChange = (field: string, value: string | string[]) => {
    setFormData(prev => ({
      ...prev,
      [field]: value,
    }));
  };

  const handleTagsChange = (tags: string[]) => {
    setFormData(prev => ({
      ...prev,
      tags,
    }));
  };

  const handleSubmit = async () => {
    if (!metadata || !token) return;

    setIsLoading(true);
    try {
      // 将标签数组转换为逗号分隔的字符串
      const submitData = {
        ...formData,
        tags: formData.tags.join(', ')
      };
      await ArchiveService.updateMetadata(metadata.arcid, submitData);
      onOpenChange(false);
      onMetadataUpdated();
    } catch (error) {
      console.error('Failed to update metadata:', error);
      showError(t('archive.updateFailed'));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{t('archive.editMetadata')}</DialogTitle>
          <DialogDescription>
            {t('archive.editMetadataDescription')}
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 py-4">
          <div className="grid gap-2">
            <Label htmlFor="title">{t('archive.title')}</Label>
            <Input
              id="title"
              value={formData.title}
              onChange={(e) => handleInputChange('title', e.target.value)}
              disabled={isLoading}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="tags">{t('archive.tags')}</Label>
            <TagInput
              id="tags"
              value={formData.tags}
              onChange={handleTagsChange}
              disabled={isLoading}
              placeholder={t('archive.tagsPlaceholder')}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="summary">{t('archive.summary')}</Label>
            <Textarea
              id="summary"
              value={formData.summary}
              onChange={(e) => handleInputChange('summary', e.target.value)}
              disabled={isLoading}
              placeholder={t('archive.summaryPlaceholder')}
            />
          </div>
        </div>
        <DialogFooter>
          <Button
            type="button"
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={isLoading}
          >
            {t('common.cancel')}
          </Button>
          <Button
            type="button"
            onClick={handleSubmit}
            disabled={isLoading}
          >
            {isLoading ? t('common.saving') : t('common.save')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}