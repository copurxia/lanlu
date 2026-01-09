'use client';

import { useMemo, useState, useEffect } from 'react';
import { Clock, RefreshCw, Plus, Play, Square } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { CronService, CronServiceStatus } from '@/lib/cron-service';
import { ScheduledTaskList } from '@/components/cron/ScheduledTaskList';
import { ScheduledTaskDialog } from '@/components/cron/ScheduledTaskDialog';
import { StartupTaskSettings } from '@/components/cron/StartupTaskSettings';
import { useToast } from '@/hooks/use-toast';

export default function SettingsCronPage() {
  const { t } = useLanguage();
  const { user, isAuthenticated } = useAuth();
  const { success, error: toastError } = useToast();
  const [refreshKey, setRefreshKey] = useState(0);
  const [status, setStatus] = useState<CronServiceStatus | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingTaskId, setEditingTaskId] = useState<number | null>(null);

  const isAdmin = useMemo(() => {
    return isAuthenticated && user?.isAdmin === true;
  }, [isAuthenticated, user?.isAdmin]);

  useEffect(() => {
    if (isAdmin) {
      CronService.getStatus()
        .then(setStatus)
        .catch((e) => console.error('Failed to fetch cron service status:', e));
    }
  }, [isAdmin, refreshKey]);

  const handleRefresh = () => {
    setRefreshKey(prev => prev + 1);
  };

  const handleStartService = async () => {
    const result = await CronService.start();
    if (result) {
      success(t('settings.cronManagement.serviceRunning'));
      handleRefresh();
    } else {
      toastError(t('common.error'));
    }
  };

  const handleStopService = async () => {
    const result = await CronService.stop();
    if (result) {
      success(t('settings.cronManagement.serviceStopped'));
      handleRefresh();
    } else {
      toastError(t('common.error'));
    }
  };

  const handleCreateTask = () => {
    setEditingTaskId(null);
    setDialogOpen(true);
  };

  const handleEditTask = (taskId: number) => {
    setEditingTaskId(taskId);
    setDialogOpen(true);
  };

  const handleDialogClose = () => {
    setDialogOpen(false);
    setEditingTaskId(null);
  };

  const handleTaskSaved = () => {
    handleDialogClose();
    handleRefresh();
  };

  if (!isAuthenticated) {
    return (
      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle>{t('settings.cron')}</CardTitle>
            <CardDescription>{t('auth.loginToManageTokens')}</CardDescription>
          </CardHeader>
        </Card>
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle>{t('settings.cron')}</CardTitle>
            <CardDescription>{t('common.accessDenied')}</CardDescription>
          </CardHeader>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="space-y-1">
        <div className="flex items-start justify-between gap-3">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <Clock className="w-5 h-5" />
              {t('settings.cronManagement.title')}
            </h2>
          </div>
          <div className="flex items-center gap-2">
            {/* Mobile: icon buttons */}
            <Button
              variant="outline"
              size="icon"
              onClick={handleRefresh}
              className="sm:hidden"
              aria-label={t('common.refresh')}
              title={t('common.refresh')}
            >
              <RefreshCw className="w-4 h-4" />
            </Button>
            <Button
              size="icon"
              onClick={handleCreateTask}
              className="sm:hidden"
              aria-label={t('settings.cronManagement.createTask')}
              title={t('settings.cronManagement.createTask')}
            >
              <Plus className="w-4 h-4" />
            </Button>

            {/* Desktop: text buttons */}
            <Button variant="outline" onClick={handleRefresh} className="hidden sm:inline-flex">
              <RefreshCw className="w-4 h-4 mr-2" />
              {t('common.refresh')}
            </Button>
            <Button onClick={handleCreateTask} className="hidden sm:inline-flex">
              <Plus className="w-4 h-4 mr-2" />
              {t('settings.cronManagement.createTask')}
            </Button>
          </div>
        </div>
        <p className="text-sm text-muted-foreground">{t('settings.cronManagement.description')}</p>
      </div>

      {/* Service Status Card */}
      <Card>
        <CardHeader className="pb-4">
          {/* Row 1: title + badge */}
          <div className="flex items-center gap-2">
            <CardTitle className="text-base">{t('settings.cronManagement.serviceStatus')}</CardTitle>
            {status?.running ? (
              <Badge variant="default" className="bg-green-500 whitespace-nowrap">
                {t('settings.cronManagement.serviceRunning')}
              </Badge>
            ) : (
              <Badge variant="secondary" className="whitespace-nowrap">
                {t('settings.cronManagement.serviceStopped')}
              </Badge>
            )}
          </div>

          {/* Row 2: action + stats */}
          <div className="flex items-center justify-between gap-3">
            {status?.running ? (
              <Button variant="outline" size="sm" onClick={handleStopService} className="whitespace-nowrap">
                <Square className="w-4 h-4 mr-1" />
                {t('settings.cronManagement.stopService')}
              </Button>
            ) : (
              <Button variant="outline" size="sm" onClick={handleStartService} className="whitespace-nowrap">
                <Play className="w-4 h-4 mr-1" />
                {t('settings.cronManagement.startService')}
              </Button>
            )}

            <div className="grid grid-cols-2 gap-4 text-sm">
              <div className="text-right">
                <span className="text-muted-foreground">{t('settings.cronManagement.totalTasks')}: </span>
                <span className="font-medium">{status?.totalTasks ?? 0}</span>
              </div>
              <div className="text-right">
                <span className="text-muted-foreground">{t('settings.cronManagement.enabledTasks')}: </span>
                <span className="font-medium">{status?.enabledTasks ?? 0}</span>
              </div>
            </div>
          </div>
        </CardHeader>
      </Card>

      {/* Tabs for Scheduled Tasks and Startup Settings */}
      <Tabs defaultValue="scheduled" className="w-full">
        <TabsList className="w-full justify-start overflow-x-auto">
          <TabsTrigger value="scheduled" className="flex-1 sm:flex-none">
            {t('settings.cronManagement.scheduledTasks')}
          </TabsTrigger>
          <TabsTrigger value="startup" className="flex-1 sm:flex-none">
            {t('settings.cronManagement.startupTasks')}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="scheduled" className="mt-4">
          <ScheduledTaskList
            key={refreshKey}
            onEdit={handleEditTask}
            onRefresh={handleRefresh}
          />
        </TabsContent>

        <TabsContent value="startup" className="mt-4">
          <StartupTaskSettings />
        </TabsContent>
      </Tabs>

      {/* Create/Edit Dialog */}
      <ScheduledTaskDialog
        open={dialogOpen}
        taskId={editingTaskId}
        onClose={handleDialogClose}
        onSaved={handleTaskSaved}
      />
    </div>
  );
}
