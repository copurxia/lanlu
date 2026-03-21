'use client';

import { useRef, useState, type DragEvent, type ChangeEvent } from 'react';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useLanguage } from '@/contexts/LanguageContext';
import { PluginService } from '@/lib/services/plugin-service';
import { Download } from 'lucide-react';

interface PluginInstallDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onInstalled?: () => void;
}

export function PluginInstallDialog({
  open,
  onOpenChange,
  onInstalled,
}: PluginInstallDialogProps) {
  const { t } = useLanguage();
  const [url, setUrl] = useState('');
  const [installing, setInstalling] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [error, setError] = useState('');
  const fileInputRef = useRef<HTMLInputElement | null>(null);

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
    } catch (e: any) {
      setError(e?.response?.data?.error || e?.message || t('settings.pluginInstallFailed'));
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
    } catch (e: any) {
      setError(e?.response?.data?.error || e?.message || t('settings.pluginUploadFailed'));
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
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center space-x-2">
            <Download className="w-5 h-5" />
            <span>{t('settings.pluginInstall')}</span>
          </DialogTitle>
        </DialogHeader>

        <DialogBody className="space-y-4">
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
