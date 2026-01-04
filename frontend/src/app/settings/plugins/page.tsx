'use client';

import { useEffect, useState, useCallback } from 'react';
import { PluginCard } from '@/components/settings/PluginCard';
import { logger } from '@/lib/logger';
import { PluginConfigDialog } from '@/components/settings/PluginConfigDialog';
import { SettingsPageWrapper } from '@/components/settings/SettingsPageWrapper';
import { PluginService, Plugin } from '@/lib/plugin-service';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Spinner } from '@/components/ui/spinner';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Package, RefreshCw } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';

const TYPE_ORDER = ['metadata', 'download', 'login', 'script'];

export default function SettingsPluginsPage() {
  const { t } = useLanguage();

  const [plugins, setPlugins] = useState<Plugin[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedPlugin, setSelectedPlugin] = useState<Plugin | null>(null);
  const [configDialogOpen, setConfigDialogOpen] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [activeType, setActiveType] = useState('all');

  const fetchPlugins = useCallback(async () => {
    try {
      setLoading(true);
      const pluginsData = await PluginService.getAllPlugins();
      setPlugins(pluginsData);
    } catch (error) {
      logger.apiError('fetch plugins', error);
      logger.operationFailed('settings.loadPluginsError', error);
      setPlugins([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      fetchPlugins();
    }
  }, [fetchPlugins]);

  const handleTogglePluginStatus = async (namespace: string, enabled: boolean) => {
    try {
      await PluginService.togglePluginStatus(namespace, enabled);
      await fetchPlugins();
    } catch (error) {
      logger.operationFailed('toggle plugin status', error);
      logger.operationFailed('settings.toggleStatusError', error);
    }
  };

  const handleOpenConfig = (plugin: Plugin) => {
    setSelectedPlugin(plugin);
    setConfigDialogOpen(true);
  };

  const handleConfigSaved = async () => {
    await fetchPlugins();
  };

  const handleRefresh = async () => {
    try {
      setRefreshing(true);
      await fetchPlugins();
    } finally {
      setRefreshing(false);
    }
  };

  const availableTypes = Array.from(
    new Set(
      plugins
        .map((p) => (p?.plugin_type ?? '').toString().trim().toLowerCase())
        .filter((x) => x.length > 0)
    )
  ).sort((a, b) => {
    const aIndex = TYPE_ORDER.indexOf(a);
    const bIndex = TYPE_ORDER.indexOf(b);
    if (aIndex === -1 && bIndex === -1) return a.localeCompare(b);
    if (aIndex === -1) return 1;
    if (bIndex === -1) return -1;
    return aIndex - bIndex;
  });

  const filteredPlugins =
    activeType === 'all'
      ? plugins
      : plugins.filter((p) => (p?.plugin_type ?? '').toString().trim().toLowerCase() === activeType);

  const getPluginTypeColor = (type: string) => {
    switch (type.toLowerCase()) {
      case 'metadata':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      case 'download':
        return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200';
      case 'login':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200';
      case 'script':
        return 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200';
      default:
        return 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200';
    }
  };

  const getPluginTypeLabel = (type: string) => {
    switch (type.toLowerCase()) {
      case 'metadata':
        return t('settings.metadata');
      case 'download':
        return t('settings.download');
      case 'login':
        return t('settings.login');
      case 'script':
        return t('settings.script');
      default:
        return type;
    }
  };

  const refreshButton = (
    <Button
      variant="outline"
      onClick={handleRefresh}
      disabled={refreshing}
      className="flex items-center space-x-2"
    >
      <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
      <span>{t('common.refresh')}</span>
    </Button>
  );

  return (
    <SettingsPageWrapper
      title={t('settings.plugins')}
      description={t('settings.pluginsDescription')}
      icon={<Package className="w-5 h-5" />}
      requireAdmin
      actions={refreshButton}
    >
      <Tabs value={activeType} onValueChange={setActiveType}>
        <TabsList className="flex flex-wrap justify-start h-auto">
          <TabsTrigger value="all">{t('settings.all')}</TabsTrigger>
          {availableTypes.map((type) => (
            <TabsTrigger key={type} value={type}>
              {getPluginTypeLabel(type)}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>

      {loading ? (
        <div className="text-center py-12">
          <Spinner size="lg" />
          <p className="text-muted-foreground mt-4">{t('common.loading')}</p>
        </div>
      ) : filteredPlugins.length > 0 ? (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {filteredPlugins.map((plugin) => (
            <PluginCard
              key={plugin.id}
              plugin={plugin}
              onToggleStatus={handleTogglePluginStatus}
              onOpenConfig={handleOpenConfig}
              getPluginTypeColor={getPluginTypeColor}
              getPluginTypeLabel={getPluginTypeLabel}
            />
          ))}
        </div>
      ) : (
        <div className="text-center py-12">
          <Package className="w-12 h-12 text-muted-foreground mx-auto mb-4" />
          <p className="text-muted-foreground">{t('settings.noPlugins')}</p>
        </div>
      )}

      <PluginConfigDialog
        open={configDialogOpen}
        onOpenChange={setConfigDialogOpen}
        plugin={selectedPlugin}
        onConfigSaved={handleConfigSaved}
      />
    </SettingsPageWrapper>
  );
}
