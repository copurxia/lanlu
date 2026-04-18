'use client';

import { memo, useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Task } from '@/types/task';
import { TaskPoolService } from '@/lib/services/taskpool-service';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Spinner } from '@/components/ui/spinner';
import { Pagination } from '@/components/ui/pagination';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import {
  Play,
  Square,
  Clock,
  CheckCircle,
  XCircle,
  PauseCircle,
  RefreshCw,
  ListTodo,
} from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { useToast } from '@/hooks/use-toast';

const ALLOWED_FILTERS = ['all', 'pending', 'running', 'waiting', 'completed', 'failed'] as const;
type AllowedFilter = (typeof ALLOWED_FILTERS)[number];

const LOG_PREVIEW_RECENT_LINES = 80;
const LOG_PREVIEW_LAST_LINE_MAX = 160;

type TranslateFn = (key: string, options?: Record<string, any>) => string;

function normalizeFilter(value: string | null): AllowedFilter {
  if (!value) return 'all';
  return (ALLOWED_FILTERS as readonly string[]).includes(value) ? (value as AllowedFilter) : 'all';
}

function normalizePageIndex(value: string | null): number {
  if (!value) return 0;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 1) return 0;
  return parsed - 1;
}

function formatTimestamp(value?: string): string {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return date.toLocaleString();
}

function getStatusIcon(status: string) {
  switch (status.toLowerCase()) {
    case 'pending':
      return <Clock className="w-4 h-4" />;
    case 'running':
      return <RefreshCw className="w-4 h-4 animate-spin" />;
    case 'waiting':
      return <PauseCircle className="w-4 h-4" />;
    case 'completed':
      return <CheckCircle className="w-4 h-4" />;
    case 'failed':
      return <XCircle className="w-4 h-4" />;
    case 'stopped':
      return <PauseCircle className="w-4 h-4" />;
    default:
      return <Clock className="w-4 h-4" />;
  }
}

function deriveLogModel(message: string): {
  full: string;
  preview: string;
  lastLine: string;
  hiddenLineCount: number;
  isTruncated: boolean;
} {
  const full = message || '';
  if (!full) {
    return {
      full: '',
      preview: '',
      lastLine: '',
      hiddenLineCount: 0,
      isTruncated: false,
    };
  }

  const lines = full.split('\n');
  const recentLines = lines.slice(-LOG_PREVIEW_RECENT_LINES);
  const hiddenLineCount = Math.max(0, lines.length - recentLines.length);
  const preview = recentLines.join('\n').trim();
  const lastLineRaw = [...lines].reverse().find((line) => line.trim().length > 0) ?? lines[lines.length - 1] ?? '';
  const lastLine =
    lastLineRaw.length > LOG_PREVIEW_LAST_LINE_MAX
      ? `${lastLineRaw.slice(0, LOG_PREVIEW_LAST_LINE_MAX)}…`
      : lastLineRaw;

  return {
    full,
    preview,
    lastLine,
    hiddenLineCount,
    isTruncated: hiddenLineCount > 0,
  };
}

function prettyPrintResult(result: string): string {
  if (!result) return '';
  try {
    return JSON.stringify(JSON.parse(result), null, 2);
  } catch {
    return result;
  }
}

interface TaskCardProps {
  task: Task;
  t: TranslateFn;
  onCancelTask: (taskId: number) => void;
  onRetryTask: (taskId: number) => void;
}

const TaskCard = memo(function TaskCard({ task, t, onCancelTask, onRetryTask }: TaskCardProps) {
  const [logExpanded, setLogExpanded] = useState(false);

  useEffect(() => {
    setLogExpanded(false);
  }, [task.id]);

  const logModel = useMemo(() => deriveLogModel(task.message || ''), [task.message]);
  const formattedCreatedAt = useMemo(() => formatTimestamp(task.createdAt), [task.createdAt]);
  const formattedStartedAt = useMemo(() => formatTimestamp(task.startedAt), [task.startedAt]);
  const formattedCompletedAt = useMemo(() => formatTimestamp(task.completedAt), [task.completedAt]);
  const formattedTimeoutAt = useMemo(() => formatTimestamp(task.timeoutAt), [task.timeoutAt]);
  const formattedResult = useMemo(() => prettyPrintResult(task.result), [task.result]);

  const taskParams = useMemo(() => {
    if (!['upload', 'asset_upload', 'upload_process', 'asset_upload_process', 'download_url'].includes(task.taskType)) {
      return null;
    }
    return TaskPoolService.parseTaskParameters(task.parameters);
  }, [task.parameters, task.taskType]);

  const statusAction = useMemo(() => {
    switch (task.status.toLowerCase()) {
      case 'pending':
      case 'running':
      case 'waiting':
        return (
          <Button
            size="sm"
            variant="outline"
            onClick={() => onCancelTask(task.id)}
            className="flex items-center space-x-1 text-red-600 hover:text-red-700"
          >
            <Square className="w-3 h-3" />
            <span>{t('settings.taskManagement.cancel')}</span>
          </Button>
        );
      case 'failed':
      case 'stopped':
        return (
          <Button
            size="sm"
            variant="outline"
            onClick={() => onRetryTask(task.id)}
            className="flex items-center space-x-1 text-blue-600 hover:text-blue-700"
          >
            <Play className="w-3 h-3" />
            <span>{t('settings.taskManagement.retry')}</span>
          </Button>
        );
      default:
        return null;
    }
  }, [onCancelTask, onRetryTask, t, task.id, task.status]);

  return (
    <Card className="w-full">
      <CardHeader className="pb-3">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-2 min-w-0">
            <CardTitle className="text-base truncate min-w-0">{task.name}</CardTitle>
            <Badge className={TaskPoolService.getStatusColor(task.status)} variant="secondary">
              <div className="flex items-center gap-1 whitespace-nowrap">
                {getStatusIcon(task.status)}
                <span>{TaskPoolService.getStatusLabel(task.status, t)}</span>
              </div>
            </Badge>
            {task.phase && (
              <Badge variant="outline" className="whitespace-nowrap">
                {task.phase}
              </Badge>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-2 sm:justify-end">
            <Badge variant="outline" className="font-mono text-xs whitespace-nowrap">
              Job #{task.id}
            </Badge>
            <Badge className={TaskPoolService.getPriorityColor(task.priority)} title={`P${task.priority}`}>
              P{task.priority}
            </Badge>
            <Badge className={TaskPoolService.getTaskTypeColor(task.taskType)} variant="secondary">
              {TaskPoolService.getTaskTypeLabel(task.taskType)}
            </Badge>
            {task.triggerSource && (
              <Badge variant="outline" className="whitespace-nowrap">
                {TaskPoolService.getTriggerSourceLabel(task.triggerSource)}
              </Badge>
            )}
            {statusAction}
          </div>
        </div>
        {task.groupId && (
          <div className="mt-2">
            <Badge variant="secondary" className="text-xs">
              Group: {task.groupId}
            </Badge>
          </div>
        )}
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span>{t('settings.taskManagement.progress')}</span>
            <span>{task.progress}%</span>
          </div>
          <Progress value={task.progress} className="w-full" />
        </div>

        {!!task.message && (
          <div className="text-sm text-muted-foreground">
            <strong>{t('settings.taskManagement.latestLog')}:</strong> {logModel.lastLine}
            {task.waitingReason && (
              <div className="mt-1 text-xs">
                Waiting: {task.waitingReason}
              </div>
            )}
            <div className="mt-1 p-2 bg-gray-50 dark:bg-gray-800 rounded text-xs max-h-28 overflow-y-auto whitespace-pre-wrap">
              {logExpanded ? logModel.full : logModel.preview}
            </div>
            {logModel.isTruncated && (
              <div className="mt-2">
                <Button
                  size="sm"
                  variant="ghost"
                  className="h-6 px-2 text-xs"
                  onClick={() => setLogExpanded((prev) => !prev)}
                >
                  {logExpanded
                    ? t('common.collapse')
                    : `${t('common.expand')} (${logModel.hiddenLineCount} lines hidden)`}
                </Button>
              </div>
            )}
          </div>
        )}

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm text-muted-foreground">
          <div>
            <strong>{t('settings.taskManagement.createdAt')}:</strong>
            <br />
            {formattedCreatedAt}
          </div>
          {task.startedAt && (
            <div>
              <strong>{t('settings.taskManagement.startedAt')}:</strong>
              <br />
              {formattedStartedAt}
            </div>
          )}
          {task.completedAt && (
            <div>
              <strong>{t('settings.taskManagement.completedAt')}:</strong>
              <br />
              {formattedCompletedAt}
            </div>
          )}
          {task.timeoutAt && (
            <div className="md:col-span-3">
              <strong>{t('settings.taskManagement.timeoutAt')}:</strong>
              <br />
              {formattedTimeoutAt}
            </div>
          )}
        </div>

        {task.pluginNamespace && (
          <div className="text-sm">
            <strong>{t('settings.taskManagement.plugin')}:</strong> {task.pluginNamespace}
          </div>
        )}

        {(task.status === 'completed' || task.status === 'failed') && task.result && (
          <div className="text-sm">
            <strong>{t('settings.taskManagement.result')}:</strong>
            <div className="mt-1 p-2 bg-gray-50 dark:bg-gray-800 rounded text-xs max-h-20 overflow-y-auto overflow-x-auto whitespace-pre-wrap font-mono">
              {formattedResult}
            </div>
          </div>
        )}

        {taskParams && (
          <div className="text-sm border-t pt-3">
            <strong>{t('settings.taskManagement.taskDetails')}:</strong>
            <div className="mt-2 grid grid-cols-1 md:grid-cols-2 gap-2 text-xs">
              {taskParams.url && (
                <div className="md:col-span-2 break-all">
                  <strong>{t('settings.taskManagement.url')}:</strong> {taskParams.url}
                </div>
              )}
              {taskParams.filename && (
                <div className="md:col-span-2">
                  <strong>{t('settings.taskManagement.filename')}:</strong> {taskParams.filename}
                </div>
              )}
              {taskParams.filesize && (
                <div>
                  <strong>{t('settings.taskManagement.fileSize')}:</strong> {TaskPoolService.formatFileSize(taskParams.filesize)}
                </div>
              )}
              {taskParams.total_chunks && (
                <div>
                  <strong>{t('settings.taskManagement.chunkCount')}:</strong> {taskParams.total_chunks}
                </div>
              )}
              {taskParams.chunk_size && (
                <div>
                  <strong>{t('settings.taskManagement.chunkSize')}:</strong> {TaskPoolService.formatFileSize(taskParams.chunk_size)}
                </div>
              )}
              {taskParams.title && taskParams.title !== taskParams.filename && (
                <div className="md:col-span-2">
                  <strong>{t('settings.taskManagement.title')}:</strong> {taskParams.title}
                </div>
              )}
              {taskParams.tags && (
                <div className="md:col-span-2">
                  <strong>{t('settings.taskManagement.tags')}:</strong> {taskParams.tags}
                </div>
              )}
              {taskParams.summary && (
                <div className="md:col-span-2">
                  <strong>{t('settings.taskManagement.summary')}:</strong> {taskParams.summary}
                </div>
              )}
              {(taskParams.category_id || taskParams.categoryId) && (
                <div className="md:col-span-2">
                  <strong>{t('settings.taskManagement.category')}:</strong> {taskParams.category_id || taskParams.categoryId}
                </div>
              )}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}, (prev, next) => {
  return (
    prev.task === next.task &&
    prev.t === next.t &&
    prev.onCancelTask === next.onCancelTask &&
    prev.onRetryTask === next.onRetryTask
  );
});

interface TaskListProps {
  className?: string;
  refreshToken?: number;
}

export function TaskList({ className, refreshToken }: TaskListProps) {
  const { t } = useLanguage();
  const { confirm } = useConfirmContext();
  const { success: showSuccess } = useToast();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [updating, setUpdating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const hasLoadedOnceRef = useRef(false);
  const previousStreamStateRef = useRef<{ filter: AllowedFilter; page: number; refreshKey: string } | null>(null);
  const [localRefreshKey, setLocalRefreshKey] = useState(0);

  const [pageSize] = useState(10);
  const [totalPages, setTotalPages] = useState(0);
  const [total, setTotal] = useState(0);
  const [totalAll, setTotalAll] = useState<number | null>(null);
  const currentPage = useMemo(() => normalizePageIndex(searchParams.get('page')), [searchParams]);
  const activeFilter = useMemo(() => normalizeFilter(searchParams.get('tab')), [searchParams]);
  const refreshKey = useMemo(
    () => `${refreshToken ?? 0}:${localRefreshKey}`,
    [localRefreshKey, refreshToken]
  );

  const updateUrl = useCallback(
    (nextFilter: AllowedFilter, nextPageIndex: number) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set('tab', nextFilter);
      params.set('page', String(nextPageIndex + 1));

      const nextQuery = params.toString();
      const currentQuery = searchParams.toString();
      if (nextQuery === currentQuery) return;

      router.replace(`${pathname}?${nextQuery}`, { scroll: false });
    },
    [pathname, router, searchParams]
  );

  useEffect(() => {
    const previousStreamState = previousStreamStateRef.current;
    const isInitialLoad = !hasLoadedOnceRef.current;
    const isQueryChange =
      previousStreamState !== null &&
      (previousStreamState.filter !== activeFilter || previousStreamState.page !== currentPage);
    const isManualRefresh =
      previousStreamState !== null && !isQueryChange && previousStreamState.refreshKey !== refreshKey;
    previousStreamStateRef.current = { filter: activeFilter, page: currentPage, refreshKey };

    setError(null);
    if (isInitialLoad) {
      setLoading(true);
    } else if (isManualRefresh) {
      setRefreshing(true);
    } else if (isQueryChange) {
      setUpdating(true);
    }

    let closed = false;
    const unsubscribe = TaskPoolService.subscribeTaskList(
      {
        page: currentPage + 1,
        pageSize,
        status: activeFilter !== 'all' ? activeFilter : undefined,
      },
      {
        onTasks: (result) => {
          if (closed) return;

          hasLoadedOnceRef.current = true;
          setError(null);
          setTasks(Array.isArray(result.tasks) ? result.tasks : []);
          setTotal(typeof result.total === 'number' ? result.total : 0);
          setTotalAll(typeof result.totalAll === 'number' ? result.totalAll : null);
          setTotalPages(typeof result.totalPages === 'number' ? result.totalPages : 0);
          setLoading(false);
          setRefreshing(false);
          setUpdating(false);

          if (result.totalPages > 0 && currentPage > result.totalPages - 1) {
            updateUrl(activeFilter, result.totalPages - 1);
            return;
          }

          if (result.totalPages === 0 && currentPage !== 0) {
            updateUrl(activeFilter, 0);
          }
        },
        onError: (streamError) => {
          if (closed) return;
          console.warn('Task list stream error:', streamError);

          if (!hasLoadedOnceRef.current) {
            setError(streamError.message || 'Failed to connect task stream');
            setLoading(false);
            setRefreshing(false);
            setUpdating(false);
          }
        },
      }
    );

    return () => {
      closed = true;
      unsubscribe();
    };
  }, [activeFilter, currentPage, pageSize, refreshKey, updateUrl]);

  const handleRefresh = useCallback(() => {
    setLocalRefreshKey((prev) => prev + 1);
  }, []);

  const handleCancelTask = useCallback(
    async (taskId: number) => {
      const confirmed = await confirm({
        title: t('settings.taskManagement.confirmCancel'),
        description: '',
        confirmText: t('common.yes'),
        cancelText: t('common.no'),
        variant: 'destructive',
      });

      if (!confirmed) return;

      try {
        const ok = await TaskPoolService.cancelTask(taskId);
        if (ok) {
          handleRefresh();
          showSuccess(t('settings.taskManagement.canceled'));
        } else {
          setError(t('settings.taskManagement.failedToCancel'));
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : t('settings.taskManagement.failedToCancel'));
      }
    },
    [confirm, handleRefresh, showSuccess, t]
  );

  const handleRetryTask = useCallback(
    async (taskId: number) => {
      try {
        const result = await TaskPoolService.retryTask(taskId);
        if (result.success) {
          handleRefresh();
        } else {
          setError(t('settings.taskManagement.failedToRetry'));
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : t('settings.taskManagement.failedToRetry'));
      }
    },
    [handleRefresh, t]
  );

  const handleFilterChange = (value: string) => {
    const nextFilter = normalizeFilter(value);
    if (nextFilter === activeFilter && currentPage === 0) return;
    setUpdating(true);
    updateUrl(nextFilter, 0);
  };

  const handlePageChange = (page: number) => {
    if (page === currentPage) return;
    setUpdating(true);
    updateUrl(activeFilter, page);
  };

  if (loading && tasks.length === 0) {
    return (
      <div className="flex items-center justify-center py-8">
        <Spinner size="lg" />
        <span className="ml-2">{t('common.loading')}</span>
      </div>
    );
  }

  return (
    <div className={`space-y-6 ${className || ''}`}>
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-md">
          <p className="text-sm">{error}</p>
        </div>
      )}

      <div className="flex items-center justify-between gap-3">
        <Tabs value={activeFilter} onValueChange={handleFilterChange} className="flex-1 min-w-0">
          <TabsList className="flex w-full justify-start overflow-x-auto">
            <TabsTrigger value="all" className="flex items-center gap-2 flex-none px-2 sm:px-3">
              <span className="whitespace-nowrap">{t('settings.taskManagement.all')}</span>
              <Badge variant="secondary" className="text-xs px-1.5 py-0.5 min-w-5 h-5 flex items-center justify-center">
                {totalAll ?? total}
              </Badge>
            </TabsTrigger>
            <TabsTrigger value="pending" className="flex items-center gap-2 flex-none px-2 sm:px-3">
              <Clock className="w-4 h-4 shrink-0" />
              <span className="whitespace-nowrap">{t('settings.taskManagement.pending')}</span>
            </TabsTrigger>
            <TabsTrigger value="running" className="flex items-center gap-2 flex-none px-2 sm:px-3">
              <RefreshCw className="w-4 h-4 shrink-0" />
              <span className="whitespace-nowrap">{t('settings.taskManagement.running')}</span>
            </TabsTrigger>
            <TabsTrigger value="waiting" className="flex items-center gap-2 flex-none px-2 sm:px-3">
              <PauseCircle className="w-4 h-4 shrink-0" />
              <span className="whitespace-nowrap">等待中</span>
            </TabsTrigger>
            <TabsTrigger value="completed" className="flex items-center gap-2 flex-none px-2 sm:px-3">
              <CheckCircle className="w-4 h-4 shrink-0" />
              <span className="whitespace-nowrap">{t('settings.taskManagement.completed')}</span>
            </TabsTrigger>
            <TabsTrigger value="failed" className="flex items-center gap-2 flex-none px-2 sm:px-3">
              <XCircle className="w-4 h-4 shrink-0" />
              <span className="whitespace-nowrap">{t('settings.taskManagement.failed')}</span>
            </TabsTrigger>
          </TabsList>
        </Tabs>

        {(updating || refreshing) && (
          <div className="shrink-0 flex items-center text-muted-foreground">
            <Spinner size="sm" />
          </div>
        )}
      </div>

      {tasks.length > 0 ? (
        <div className="space-y-4">
          {tasks.map((task) => (
            <TaskCard
              key={task.id}
              task={task}
              t={t as TranslateFn}
              onCancelTask={handleCancelTask}
              onRetryTask={handleRetryTask}
            />
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

      {totalPages > 0 && (
        <div className="flex items-center justify-between">
          <p className="text-sm text-muted-foreground">{t('settings.taskManagement.totalTasks', { count: total })}</p>
          <Pagination currentPage={currentPage} totalPages={totalPages} onPageChange={handlePageChange} />
        </div>
      )}
    </div>
  );
}
