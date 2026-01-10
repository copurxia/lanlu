'use client';

import { useState, useEffect } from 'react';
import { Play, Pencil, Trash2, ToggleLeft, ToggleRight, Clock, CheckCircle, XCircle } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { CronService, ScheduledTask } from '@/lib/services/cron-service';
import { useToast } from '@/hooks/use-toast';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';

interface ScheduledTaskListProps {
  onEdit: (taskId: number) => void;
  onRefresh: () => void;
}

export function ScheduledTaskList({ onEdit, onRefresh }: ScheduledTaskListProps) {
  const { t } = useLanguage();
  const { success, error: toastError } = useToast();
  const [tasks, setTasks] = useState<ScheduledTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [deleteTaskId, setDeleteTaskId] = useState<number | null>(null);

  const fetchTasks = async () => {
    setLoading(true);
    try {
      const result = await CronService.getTasks(1, 100);
      setTasks(result.tasks);
    } catch (e) {
      console.error('Failed to fetch scheduled tasks:', e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchTasks();
  }, []);

  const handleTrigger = async (taskId: number) => {
    const result = await CronService.triggerTask(taskId);
    if (result) {
      success(t('settings.cronManagement.triggerSuccess'));
      // 立即刷新任务列表以更新上次执行时间
      fetchTasks();
    } else {
      toastError(t('settings.cronManagement.triggerFailed'));
    }
  };

  const handleToggleEnabled = async (task: ScheduledTask) => {
    let result: boolean;
    if (task.enabled) {
      result = await CronService.disableTask(task.id);
      if (result) {
        success(t('settings.cronManagement.disableSuccess'));
      }
    } else {
      result = await CronService.enableTask(task.id);
      if (result) {
        success(t('settings.cronManagement.enableSuccess'));
      }
    }
    if (result) {
      fetchTasks();
      onRefresh();
    } else {
      toastError(t('settings.cronManagement.toggleFailed'));
    }
  };

  const handleDelete = async () => {
    if (deleteTaskId === null) return;
    const result = await CronService.deleteTask(deleteTaskId);
    if (result) {
      success(t('settings.cronManagement.deleteSuccess'));
      fetchTasks();
      onRefresh();
    } else {
      toastError(t('settings.cronManagement.deleteFailed'));
    }
    setDeleteTaskId(null);
  };

  const formatDateTime = (dateStr: string) => {
    if (!dateStr) return t('settings.cronManagement.neverRun');
    try {
      const date = new Date(dateStr);
      return date.toLocaleString();
    } catch {
      return dateStr;
    }
  };

  const getTaskTypeLabel = (taskType: string) => {
    const key = `settings.cronManagement.taskTypes.${taskType}`;
    const translated = t(key);
    return translated !== key ? translated : CronService.getTaskTypeLabel(taskType);
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

  if (tasks.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 text-center">
          <Clock className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
          <p className="text-muted-foreground">{t('settings.cronManagement.noScheduledTasks')}</p>
          <p className="text-sm text-muted-foreground mt-1">{t('settings.cronManagement.noScheduledTasksHint')}</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <>
      <div className="space-y-3">
        {tasks.map((task) => (
          <Card key={task.id}>
            <CardContent className="py-4">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
                {/* Task Info */}
                <div className="flex-1 min-w-0">
                  <div className="flex flex-wrap items-center gap-2 mb-2">
                    <h3 className="font-medium truncate max-w-full">{task.name}</h3>
                    <Badge variant={task.enabled ? 'default' : 'secondary'}>
                      {task.enabled ? t('settings.cronManagement.enabled') : t('settings.cronManagement.disabled')}
                    </Badge>
                    <Badge variant="outline" className={CronService.getTaskTypeColor(task.taskType)}>
                      {getTaskTypeLabel(task.taskType)}
                    </Badge>
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-x-4 gap-y-1 text-sm">
                    <div>
                      <span className="text-muted-foreground">{t('settings.cronManagement.cronExpression')}: </span>
                      <code className="bg-muted px-1 rounded text-xs font-mono break-all whitespace-pre-wrap">
                        {task.cronExpression}
                      </code>
                    </div>
                    <div>
                      <span className="text-muted-foreground">{t('settings.cronManagement.priority')}: </span>
                      <span>{task.priority}</span>
                    </div>
                    <div>
                      <span className="text-muted-foreground">{t('settings.cronManagement.runCount')}: </span>
                      <span>{task.runCount}</span>
                    </div>
                    <div className="flex flex-wrap items-center gap-1 min-w-0">
                      <span className="text-muted-foreground">{t('settings.cronManagement.lastRunAt')}: </span>
                      {task.lastRunAt ? (
                        <>
                          <span className="text-xs break-words">{formatDateTime(task.lastRunAt)}</span>
                          {task.lastRunSuccess ? (
                            <CheckCircle className="w-3 h-3 text-green-500" />
                          ) : (
                            <XCircle className="w-3 h-3 text-red-500" />
                          )}
                        </>
                      ) : (
                        <span className="text-xs">{t('settings.cronManagement.neverRun')}</span>
                      )}
                    </div>
                  </div>

                  {task.nextRunAt && task.enabled && (
                    <div className="mt-2 text-sm">
                      <span className="text-muted-foreground">{t('settings.cronManagement.nextRunAt')}: </span>
                      <span className="text-primary">{formatDateTime(task.nextRunAt)}</span>
                    </div>
                  )}
                </div>

                {/* Actions */}
                <div className="flex items-center gap-1 self-end sm:self-auto shrink-0">
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => handleTrigger(task.id)}
                    title={t('settings.cronManagement.trigger')}
                  >
                    <Play className="w-4 h-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => handleToggleEnabled(task)}
                    title={task.enabled ? t('settings.cronManagement.disable') : t('settings.cronManagement.enable')}
                  >
                    {task.enabled ? (
                      <ToggleRight className="w-4 h-4 text-green-500" />
                    ) : (
                      <ToggleLeft className="w-4 h-4 text-muted-foreground" />
                    )}
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => onEdit(task.id)}
                    title={t('common.edit')}
                  >
                    <Pencil className="w-4 h-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => setDeleteTaskId(task.id)}
                    title={t('common.delete')}
                  >
                    <Trash2 className="w-4 h-4 text-destructive" />
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteTaskId !== null} onOpenChange={() => setDeleteTaskId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('settings.cronManagement.deleteTask')}</AlertDialogTitle>
            <AlertDialogDescription>
              {t('settings.cronManagement.deleteTaskConfirm')}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('common.cancel')}</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete}>{t('common.delete')}</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
