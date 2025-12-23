'use client';

import { useMemo, useState, useEffect } from 'react';
import { Clock, RefreshCw, Plus, Play, Square } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
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
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            <Clock className="w-5 h-5" />
            {t('settings.cronManagement.title')}
          </h2>
          <p className="text-sm text-muted-foreground">{t('settings.cronManagement.description')}</p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" onClick={handleRefresh}>
            <RefreshCw className="w-4 h-4 mr-2" />
            {t('common.refresh')}
          </Button>
          <Button onClick={handleCreateTask}>
            <Plus className="w-4 h-4 mr-2" />
            {t('settings.cronManagement.createTask')}
          </Button>
        </div>
      </div>

      {/* Service Status Card */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="text-base">{t('settings.cronManagement.serviceStatus')}</CardTitle>
            </div>
            <div className="flex items-center gap-2">
              {status?.running ? (
                <>
                  <Badge variant="default" className="bg-green-500">
                    {t('settings.cronManagement.serviceRunning')}
                  </Badge>
                  <Button variant="outline" size="sm" onClick={handleStopService}>
                    <Square className="w-4 h-4 mr-1" />
                    {t('settings.cronManagement.stopService')}
                  </Button>
                </>
              ) : (
                <>
                  <Badge variant="secondary">
                    {t('settings.cronManagement.serviceStopped')}
                  </Badge>
                  <Button variant="outline" size="sm" onClick={handleStartService}>
                    <Play className="w-4 h-4 mr-1" />
                    {t('settings.cronManagement.startService')}
                  </Button>
                </>
              )}
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="flex gap-6 text-sm">
            <div>
              <span className="text-muted-foreground">{t('settings.cronManagement.totalTasks')}: </span>
              <span className="font-medium">{status?.totalTasks ?? 0}</span>
            </div>
            <div>
              <span className="text-muted-foreground">{t('settings.cronManagement.enabledTasks')}: </span>
              <span className="font-medium">{status?.enabledTasks ?? 0}</span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Tabs for Scheduled Tasks and Startup Settings */}
      <Tabs defaultValue="scheduled" className="w-full">
        <TabsList>
          <TabsTrigger value="scheduled">{t('settings.cronManagement.scheduledTasks')}</TabsTrigger>
          <TabsTrigger value="startup">{t('settings.cronManagement.startupTasks')}</TabsTrigger>
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
