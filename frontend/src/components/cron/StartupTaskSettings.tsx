'use client';

import { useState, useEffect } from 'react';
import { useLanguage } from '@/contexts/LanguageContext';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { SystemSettingsApi } from '@/lib/system-settings-api';
import { useToast } from '@/hooks/use-toast';

export function StartupTaskSettings() {
  const { t } = useLanguage();
  const { success, error: toastError } = useToast();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [enableInitialScan, setEnableInitialScan] = useState(false);
  const [enableInitialDbCheck, setEnableInitialDbCheck] = useState(false);
  const [enableInitialPluginScan, setEnableInitialPluginScan] = useState(true);

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    setLoading(true);
    try {
      const settings = await SystemSettingsApi.getAllSettings();
      const scanSetting = settings.find((s: any) => s.key === 'ENABLE_INITIAL_SCAN');
      const dbCheckSetting = settings.find((s: any) => s.key === 'ENABLE_INITIAL_DB_CHECK');
      const pluginScanSetting = settings.find((s: any) => s.key === 'ENABLE_INITIAL_PLUGIN_SCAN');

      setEnableInitialScan(scanSetting?.value === 'true');
      setEnableInitialDbCheck(dbCheckSetting?.value === 'true');
      // 默认为 true，如果设置不存在或值为 'true'
      setEnableInitialPluginScan(pluginScanSetting?.value !== 'false');
    } catch (e) {
      console.error('Failed to load startup settings:', e);
    } finally {
      setLoading(false);
    }
  };

  const handleToggleScan = async (checked: boolean) => {
    setSaving(true);
    try {
      await SystemSettingsApi.updateSetting('ENABLE_INITIAL_SCAN', checked ? 'true' : 'false');
      setEnableInitialScan(checked);
      success(t('settings.cronManagement.startupSettings.saveSuccess'));
    } catch (e) {
      console.error('Failed to update setting:', e);
      toastError(t('settings.cronManagement.startupSettings.saveFailed'));
    } finally {
      setSaving(false);
    }
  };

  const handleToggleDbCheck = async (checked: boolean) => {
    setSaving(true);
    try {
      await SystemSettingsApi.updateSetting('ENABLE_INITIAL_DB_CHECK', checked ? 'true' : 'false');
      setEnableInitialDbCheck(checked);
      success(t('settings.cronManagement.startupSettings.saveSuccess'));
    } catch (e) {
      console.error('Failed to update setting:', e);
      toastError(t('settings.cronManagement.startupSettings.saveFailed'));
    } finally {
      setSaving(false);
    }
  };

  const handleTogglePluginScan = async (checked: boolean) => {
    setSaving(true);
    try {
      await SystemSettingsApi.updateSetting('ENABLE_INITIAL_PLUGIN_SCAN', checked ? 'true' : 'false');
      setEnableInitialPluginScan(checked);
      success(t('settings.cronManagement.startupSettings.saveSuccess'));
    } catch (e) {
      console.error('Failed to update setting:', e);
      toastError(t('settings.cronManagement.startupSettings.saveFailed'));
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-muted-foreground">
          {t('common.loading')}
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{t('settings.cronManagement.startupSettings.title')}</CardTitle>
        <CardDescription>{t('settings.cronManagement.startupSettings.description')}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Enable Initial Scan */}
        <div className="flex items-center justify-between">
          <div className="space-y-0.5">
            <Label htmlFor="enableInitialScan" className="text-base">
              {t('settings.cronManagement.startupSettings.enableInitialScan')}
            </Label>
            <p className="text-sm text-muted-foreground">
              {t('settings.cronManagement.startupSettings.enableInitialScanDesc')}
            </p>
          </div>
          <Switch
            id="enableInitialScan"
            checked={enableInitialScan}
            onCheckedChange={handleToggleScan}
            disabled={saving}
          />
        </div>

        {/* Enable Initial DB Check */}
        <div className="flex items-center justify-between">
          <div className="space-y-0.5">
            <Label htmlFor="enableInitialDbCheck" className="text-base">
              {t('settings.cronManagement.startupSettings.enableInitialDbCheck')}
            </Label>
            <p className="text-sm text-muted-foreground">
              {t('settings.cronManagement.startupSettings.enableInitialDbCheckDesc')}
            </p>
          </div>
          <Switch
            id="enableInitialDbCheck"
            checked={enableInitialDbCheck}
            onCheckedChange={handleToggleDbCheck}
            disabled={saving}
          />
        </div>

        {/* Enable Initial Plugin Scan */}
        <div className="flex items-center justify-between">
          <div className="space-y-0.5">
            <Label htmlFor="enableInitialPluginScan" className="text-base">
              {t('settings.cronManagement.startupSettings.enableInitialPluginScan')}
            </Label>
            <p className="text-sm text-muted-foreground">
              {t('settings.cronManagement.startupSettings.enableInitialPluginScanDesc')}
            </p>
          </div>
          <Switch
            id="enableInitialPluginScan"
            checked={enableInitialPluginScan}
            onCheckedChange={handleTogglePluginScan}
            disabled={saving}
          />
        </div>
      </CardContent>
    </Card>
  );
}
