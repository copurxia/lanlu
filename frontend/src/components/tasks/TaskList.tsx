'use client';

import { useState, useEffect, useCallback } from 'react';
import { Task, TaskPageResult } from '@/types/task';
import { TaskPoolService } from '@/lib/taskpool-service';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Spinner } from '@/components/ui/spinner';
import { Pagination } from '@/components/ui/pagination';
import {
  Play,
  Square,
  Clock,
  CheckCircle,
  XCircle,
  PauseCircle,
  RefreshCw,
  ListTodo
} from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { useToast } from '@/hooks/use-toast';

interface TaskListProps {
  className?: string;
}

export function TaskList({ className }: TaskListProps) {
  const { t } = useLanguage();
  const { confirm } = useConfirmContext();
  const { success: showSuccess } = useToast();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Pagination state
  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize] = useState(10);
  const [totalPages, setTotalPages] = useState(0);
  const [total, setTotal] = useState(0);

  // Filter state
  const [activeFilter, setActiveFilter] = useState('all');

  const fetchTasks = useCallback(async (page: number = currentPage) => {
    try {
      setError(null);
      const result: TaskPageResult = await TaskPoolService.getTasks(page, pageSize);

      // 确保 result.tasks 是数组
      const tasksArray = Array.isArray(result.tasks) ? result.tasks : [];

      // Apply client-side filtering if needed
      let filteredTasks = tasksArray;
      if (activeFilter !== 'all') {
        filteredTasks = tasksArray.filter(task => task && task.status === activeFilter);
      }

      setTasks(filteredTasks);
      setTotal(typeof result.total === 'number' ? result.total : 0);
      setTotalPages(typeof result.totalPages === 'number' ? result.totalPages : 0);
      setCurrentPage(page);
    } catch (err) {
      console.error('Failed to fetch tasks:', err);
      setError(err instanceof Error ? err.message : 'Failed to fetch tasks');
      setTasks([]);
      setTotal(0);
      setTotalPages(0);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [activeFilter, currentPage, pageSize]);

  useEffect(() => {
    setLoading(true);
    fetchTasks(1);
  }, [activeFilter, fetchTasks]);

  // 自动刷新：当存在运行中/待执行任务时，周期性刷新列表以展示进度与日志
  useEffect(() => {
    const hasActive = tasks.some(t => t?.status === 'running' || t?.status === 'pending');
    if (!hasActive) return;

    const timer = setInterval(() => {
      if (loading || refreshing) return;
      fetchTasks(currentPage);
    }, 1500);

    return () => clearInterval(timer);
  }, [tasks, activeFilter, currentPage, loading, refreshing, fetchTasks]);

  const handleRefresh = async () => {
    setRefreshing(true);
    await fetchTasks(currentPage);
  };

  const handleCancelTask = async (taskId: number) => {
    const confirmed = await confirm({
      title: t('settings.taskManagement.confirmCancel'),
      description: '',
      confirmText: t('common.yes'),
      cancelText: t('common.no'),
      variant: 'destructive',
    });

    if (!confirmed) return;

    try {
      const success = await TaskPoolService.cancelTask(taskId);
      if (success) {
        await handleRefresh();
        showSuccess(t('settings.taskManagement.canceled'));
      } else {
        setError(t('settings.taskManagement.failedToCancel'));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : t('settings.taskManagement.failedToCancel'));
    }
  };

  const handleRetryTask = async (taskId: number) => {
    try {
      const result = await TaskPoolService.retryTask(taskId);
      if (result.success) {
        await handleRefresh();
      } else {
        setError(t('settings.taskManagement.failedToRetry'));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : t('settings.taskManagement.failedToRetry'));
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status.toLowerCase()) {
      case 'pending':
        return <Clock className="w-4 h-4" />;
      case 'running':
        return <RefreshCw className="w-4 h-4 animate-spin" />;
      case 'completed':
        return <CheckCircle className="w-4 h-4" />;
      case 'failed':
        return <XCircle className="w-4 h-4" />;
      case 'stopped':
        return <PauseCircle className="w-4 h-4" />;
      default:
        return <Clock className="w-4 h-4" />;
    }
  };

  const getStatusActionButtons = (task: Task) => {
    switch (task.status.toLowerCase()) {
      case 'pending':
        return (
          <div className="flex space-x-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => handleCancelTask(task.id)}
              className="flex items-center space-x-1 text-red-600 hover:text-red-700"
            >
              <Square className="w-3 h-3" />
              <span>{t('settings.taskManagement.cancel')}</span>
            </Button>
          </div>
        );
      case 'running':
        return (
          <div className="flex space-x-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => handleCancelTask(task.id)}
              className="flex items-center space-x-1 text-red-600 hover:text-red-700"
            >
              <Square className="w-3 h-3" />
              <span>{t('settings.taskManagement.cancel')}</span>
            </Button>
          </div>
        );
      case 'failed':
      case 'stopped':
        return (
          <div className="flex space-x-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => handleRetryTask(task.id)}
              className="flex items-center space-x-1 text-blue-600 hover:text-blue-700"
            >
              <Play className="w-3 h-3" />
              <span>{t('settings.taskManagement.retry')}</span>
            </Button>
          </div>
        );
      case 'completed':
        return null;
      default:
        return null;
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <Spinner size="lg" />
        <span className="ml-2">{t('common.loading')}</span>
      </div>
    );
  }

  return (
    <div className={`space-y-6 ${className || ''}`}>
      {/* Error */}
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-md">
          <p className="text-sm">{error}</p>
        </div>
      )}

      {/* Filters */}
      <Tabs value={activeFilter} onValueChange={setActiveFilter}>
        <TabsList className="grid w-full grid-cols-5">
          <TabsTrigger value="all" className="flex items-center space-x-2">
            <span>{t('settings.taskManagement.all')}</span>
            <Badge variant="secondary" className="text-xs px-1.5 py-0.5 min-w-[1.25rem] h-5 flex items-center justify-center">{total}</Badge>
          </TabsTrigger>
          <TabsTrigger value="pending" className="flex items-center space-x-2">
            <Clock className="w-4 h-4" />
            <span>{t('settings.taskManagement.pending')}</span>
          </TabsTrigger>
          <TabsTrigger value="running" className="flex items-center space-x-2">
            <RefreshCw className="w-4 h-4" />
            <span>{t('settings.taskManagement.running')}</span>
          </TabsTrigger>
          <TabsTrigger value="completed" className="flex items-center space-x-2">
            <CheckCircle className="w-4 h-4" />
            <span>{t('settings.taskManagement.completed')}</span>
          </TabsTrigger>
          <TabsTrigger value="failed" className="flex items-center space-x-2">
            <XCircle className="w-4 h-4" />
            <span>{t('settings.taskManagement.failed')}</span>
          </TabsTrigger>
        </TabsList>
      </Tabs>

      {/* Task List */}
      {tasks.length > 0 ? (
        <div className="space-y-4">
          {tasks.map((task) => (
            <Card key={task.id} className="w-full">
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-3">
                    <CardTitle className="text-base">{task.name}</CardTitle>
                    <Badge
                      className={TaskPoolService.getStatusColor(task.status)}
                      variant="secondary"
                    >
                      <div className="flex items-center space-x-1">
                        {getStatusIcon(task.status)}
                        <span>{TaskPoolService.getStatusLabel(task.status, t)}</span>
                      </div>
                    </Badge>
                  </div>
                  <div className="flex items-center space-x-2">
                    <Badge variant="outline" className="font-mono text-xs">
                      Job #{task.id}
                    </Badge>
                    {/* 优先级徽章 - 新增 */}
                    <Badge className={TaskPoolService.getPriorityColor(task.priority)}>
                      P{task.priority}
                    </Badge>
                    <Badge
                      className={TaskPoolService.getTaskTypeColor(task.taskType)}
                      variant="secondary"
                    >
                      {TaskPoolService.getTaskTypeLabel(task.taskType)}
                    </Badge>
                    {/* 触发源徽章 - 新增 */}
                    {task.triggerSource && (
                      <Badge variant="outline">
                        {TaskPoolService.getTriggerSourceLabel(task.triggerSource)}
                      </Badge>
                    )}
                    {getStatusActionButtons(task)}
                  </div>
                </div>
                {/* 分组ID - 新增 */}
                {task.groupId && (
                  <div className="mt-2">
                    <Badge variant="secondary" className="text-xs">
                      Group: {task.groupId}
                    </Badge>
                  </div>
                )}
              </CardHeader>
              <CardContent className="space-y-3">
                {/* Progress */}
                <div className="space-y-2">
                  <div className="flex items-center justify-between text-sm">
                    <span>{t('settings.taskManagement.progress')}</span>
                    <span>{task.progress}%</span>
                  </div>
                  <Progress value={task.progress} className="w-full" />
                </div>

                {/* Message */}
                {task.message && (
                  <div className="text-sm text-muted-foreground">
                    <strong>{t('settings.taskManagement.latestLog')}:</strong>{' '}
                    {(() => {
                      const lines = task.message.split('\n').map(s => s.trim()).filter(Boolean);
                      const last = lines.length > 0 ? lines[lines.length - 1] : task.message;
                      return last.length > 160 ? `${last.slice(0, 160)}…` : last;
                    })()}
                    <div className="mt-1 p-2 bg-gray-50 dark:bg-gray-800 rounded text-xs max-h-24 overflow-y-auto whitespace-pre-wrap">
                      {task.message}
                    </div>
                  </div>
                )}

                {/* Time Information */}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm text-muted-foreground">
                  <div>
                    <strong>{t('settings.taskManagement.createdAt')}:</strong>
                    <br />
                    {new Date(task.createdAt).toLocaleString()}
                  </div>
                  {task.startedAt && (
                    <div>
                      <strong>{t('settings.taskManagement.startedAt')}:</strong>
                      <br />
                      {new Date(task.startedAt).toLocaleString()}
                    </div>
                  )}
                  {task.completedAt && (
                    <div>
                      <strong>{t('settings.taskManagement.completedAt')}:</strong>
                      <br />
                      {new Date(task.completedAt).toLocaleString()}
                    </div>
                  )}
                  {/* 超时时间 - 新增 */}
                  {task.timeoutAt && (
                    <div className="md:col-span-3">
                      <strong>{t('settings.taskManagement.timeoutAt')}:</strong>
                      <br />
                      {new Date(task.timeoutAt).toLocaleString()}
                    </div>
                  )}
                </div>

                {/* Plugin Info */}
                {task.pluginNamespace && (
                  <div className="text-sm">
                    <strong>{t('settings.taskManagement.plugin')}:</strong> {task.pluginNamespace}
                  </div>
                )}

                {/* Result (for completed/failed tasks) */}
                {(task.status === 'completed' || task.status === 'failed') && task.result && (
                  <div className="text-sm">
                    <strong>{t('settings.taskManagement.result')}:</strong>
                    <div className="mt-1 p-2 bg-gray-50 dark:bg-gray-800 rounded text-xs max-h-20 overflow-y-auto whitespace-pre-wrap">
                      {(() => {
                        try {
                          return JSON.stringify(JSON.parse(task.result), null, 2);
                        } catch {
                          return task.result;
                        }
                      })()}
                    </div>
                  </div>
                )}

                {/* Upload / URL Download Details */}
                {(['upload', 'upload_process', 'download_url'].includes(task.taskType) && task.parameters) && (
                  <div className="text-sm border-t pt-3">
                    <strong>{t('settings.taskManagement.taskDetails')}:</strong>
                    {(() => {
                      const params = TaskPoolService.parseTaskParameters(task.parameters);
                      return (
                        <div className="mt-2 grid grid-cols-1 md:grid-cols-2 gap-2 text-xs">
                          {params.url && (
                            <div className="md:col-span-2 break-all">
                              <strong>{t('settings.taskManagement.url')}:</strong> {params.url}
                            </div>
                          )}
                          {params.filename && (
                            <div className="md:col-span-2">
                              <strong>{t('settings.taskManagement.filename')}:</strong> {params.filename}
                            </div>
                          )}
                          {params.filesize && (
                            <div>
                              <strong>{t('settings.taskManagement.fileSize')}:</strong> {TaskPoolService.formatFileSize(params.filesize)}
                            </div>
                          )}
                          {params.total_chunks && (
                            <div>
                              <strong>{t('settings.taskManagement.chunkCount')}:</strong> {params.total_chunks}
                            </div>
                          )}
                          {params.chunk_size && (
                            <div>
                              <strong>{t('settings.taskManagement.chunkSize')}:</strong> {TaskPoolService.formatFileSize(params.chunk_size)}
                            </div>
                          )}
                          {params.title && params.title !== params.filename && (
                            <div className="md:col-span-2">
                              <strong>{t('settings.taskManagement.title')}:</strong> {params.title}
                            </div>
                          )}
                          {params.tags && (
                            <div className="md:col-span-2">
                              <strong>{t('settings.taskManagement.tags')}:</strong> {params.tags}
                            </div>
                          )}
                          {params.summary && (
                            <div className="md:col-span-2">
                              <strong>{t('settings.taskManagement.summary')}:</strong> {params.summary}
                            </div>
                          )}
                          {(params.category_id || params.categoryId) && (
                            <div className="md:col-span-2">
                              <strong>{t('settings.taskManagement.category')}:</strong> {params.category_id || params.categoryId}
                            </div>
                          )}
                        </div>
                      );
                    })()}
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      ) : (
        <Card>
          <CardContent className="py-12">
            <div className="text-center">
              <ListTodo className="w-12 h-12 text-muted-foreground mx-auto mb-4" />
              <h3 className="text-lg font-semibold text-muted-foreground mb-2">
                {t('settings.taskManagement.noTasks')}
              </h3>
              <p className="text-sm text-muted-foreground">
                {activeFilter === 'all' ? t('settings.taskManagement.noTasksAll') : t('settings.taskManagement.noTasksFiltered')}
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Pagination */}
      {totalPages > 0 && (
        <div className="flex items-center justify-between">
          <p className="text-sm text-muted-foreground">
            {t('settings.taskManagement.totalTasks', { count: total })}
          </p>
          <Pagination
            currentPage={currentPage}
            totalPages={totalPages}
            onPageChange={(page) => fetchTasks(page)}
          />
        </div>
      )}
    </div>
  );
}
