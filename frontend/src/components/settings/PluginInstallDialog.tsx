'use client';

import { useState } from 'react';
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
  const [error, setError] = useState('');

  const handleInstall = async () => {
    if (!url.trim()) {
      setError(t('settings.pluginInstallUrlRequired') || 'URL is required');
      return;
    }

    if (!url.endsWith('.ts')) {
      setError(t('settings.pluginInstallUrlInvalid') || 'URL must point to a .ts file');
      return;
    }

    setInstalling(true);
    setError('');

    try {
      await PluginService.installPlugin(url);
      onOpenChange(false);
      setUrl('');
      onInstalled?.();
    } catch (e: any) {
      setError(e?.response?.data?.error || e?.message || t('settings.pluginInstallFailed'));
    } finally {
      setInstalling(false);
    }
  };

  const handleCancel = () => {
    setUrl('');
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
            <Label htmlFor="plugin-url">{t('settings.pluginInstallUrl')}</Label>
            <Input
              id="plugin-url"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              placeholder={t('settings.pluginInstallUrlPlaceholder')}
            />
          </div>

          {error && (
            <div className="text-sm text-red-600 dark:text-red-400">
              {error}
            </div>
          )}
        </DialogBody>

        <DialogFooter>
          <Button variant="outline" onClick={handleCancel} disabled={installing}>
            {t('common.cancel')}
          </Button>
          <Button onClick={handleInstall} disabled={installing}>
            {installing ? t('settings.pluginInstalling') : t('settings.pluginInstall')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
