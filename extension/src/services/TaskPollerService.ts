/**
 * TaskPollerService - 独立的任务轮询服务
 * 运行在Chrome扩展的后台，与React组件解耦
 */

import { getTaskById } from '@/lib/lanlu-api';
import { TaskEvents } from '@/lib/events';
import type { DownloadEntry } from '@/store/download-queue';

type QueueStatus = 'queued' | 'running' | 'completed' | 'failed' | 'stopped';

function clampProgress(value: unknown): number {
  const n = typeof value === 'number' ? value : 0;
  return Math.max(0, Math.min(100, n));
}

function normalizeStatus(raw: string): QueueStatus {
  switch (raw) {
    case 'pending':
      return 'queued';
    case 'running':
      return 'running';
    case 'completed':
      return 'completed';
    case 'failed':
      return 'failed';
    case 'stopped':
      return 'stopped';
    default:
      return 'running';
  }
}

function parseArchiveIdFromScanResult(raw: string): string | null {
  if (!raw) return null;
  try {
    const obj = JSON.parse(raw) as { archive_id?: string };
    return typeof obj.archive_id === 'string' && obj.archive_id.trim() ? obj.archive_id : null;
  } catch {
    return null;
  }
}

function parseScanTaskIdFromDownloadResult(raw: string): number | null {
  if (!raw) return null;
  try {
    const obj = JSON.parse(raw) as { task_id?: string | number };
    if (typeof obj.task_id === 'number' && Number.isFinite(obj.task_id)) return obj.task_id;
    if (typeof obj.task_id === 'string') {
      const trimmed = obj.task_id.trim();
      if (!trimmed) return null;
      const parsed = Number.parseInt(trimmed, 10);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  } catch {
    return null;
  }
}

export interface TaskPollerConfig {
  pollInterval?: number; // 轮询间隔，默认5000ms
  maxConcurrentTasks?: number; // 最大并发任务数，默认5
}

export class TaskPollerService {
  private config: Required<TaskPollerConfig>;
  private running = false;
  private intervalId: number | null = null;
  private isPolling = false;
  private entries: DownloadEntry[] = [];
  private auth: { serverUrl: string; token: string } | null = null;

  constructor(config: TaskPollerConfig = {}) {
    this.config = {
      pollInterval: config.pollInterval ?? 5000,
      maxConcurrentTasks: config.maxConcurrentTasks ?? 5,
    };
  }

  /**
   * 启动轮询服务
   */
  start(
    auth: { serverUrl: string; token: string },
    entries: DownloadEntry[]
  ): void {
    this.auth = auth;
    this.entries = entries;
    this.running = true;

    console.log('[TaskPollerService] Starting service...', {
      interval: this.config.pollInterval,
      maxConcurrent: this.config.maxConcurrentTasks,
      totalEntries: entries.length,
    });

    // 立即执行一次轮询
    this.tick();

    // 设置定时轮询
    this.intervalId = window.setInterval(() => {
      this.tick();
    }, this.config.pollInterval);
  }

  /**
   * 停止轮询服务
   */
  stop(): void {
    this.running = false;
    if (this.intervalId) {
      window.clearInterval(this.intervalId);
      this.intervalId = null;
    }
    console.log('[TaskPollerService] Service stopped');
  }

  /**
   * 更新认证信息
   */
  updateAuth(auth: { serverUrl: string; token: string }): void {
    this.auth = auth;
  }

  /**
   * 更新任务列表
   */
  updateEntries(entries: DownloadEntry[]): void {
    this.entries = entries;
  }

  /**
   * 检查服务是否正在运行
   */
  isRunning(): boolean {
    return this.running;
  }

  /**
   * 手动触发一次轮询
   */
  async pollOnce(): Promise<void> {
    if (!this.running || this.isPolling) {
      console.log('[TaskPollerService] Poll skipped - not running or already polling');
      return;
    }
    await this.tick();
  }

  /**
   * 核心轮询逻辑
   */
  private async tick(): Promise<void> {
    if (!this.running || !this.auth || this.isPolling) {
      return;
    }

    this.isPolling = true;

    try {
      // 获取需要轮询的任务
      const activeTasks = this.entries.filter((entry) => {
        if (entry.status === 'queued' || entry.status === 'running') return true;
        // download_url 已完成，但 scan_archive 尚未发现时继续轮询 group
        if (
          entry.status === 'completed' &&
          entry.downloadTaskId &&
          !entry.scanTaskId &&
          !entry.archiveId
        )
          return true;
        return false;
      });

      if (activeTasks.length === 0) {
        console.log('[TaskPollerService] No active tasks to poll');
        return;
      }

      console.log(`[TaskPollerService] Polling ${activeTasks.length} active tasks...`);

      // 限制并发数
      const batches = this.chunkArray(activeTasks, this.config.maxConcurrentTasks);
      for (const batch of batches) {
        await Promise.allSettled(
          batch.map((entry) => this.pollEntry(entry))
        );
      }

      console.log('[TaskPollerService] Poll cycle completed');
    } catch (error) {
      console.error('[TaskPollerService] Poll cycle error:', error);
    } finally {
      this.isPolling = false;
    }
  }

  /**
   * 轮询单个任务
   */
  private async pollEntry(entry: DownloadEntry): Promise<void> {
    if (!this.auth) return;

    try {
      // 1) 轮询 download_url 任务
      if (
        entry.downloadTaskId &&
        (entry.status === 'queued' || entry.status === 'running')
      ) {
        await this.pollDownloadTask(entry);
      }

      // 2) 轮询 scan_archive 任务（如果存在）
      if (entry.scanTaskId && (entry.status === 'queued' || entry.status === 'running')) {
        await this.pollScanTask(entry);
      }

      // 3) 如果下载完成但尚未发现扫描任务，轮询组以查找扫描任务
      if (
        entry.downloadTaskId &&
        entry.status === 'completed' &&
        !entry.scanTaskId &&
        !entry.archiveId
      ) {
        await this.discoverScanTask(entry);
      }
    } catch (error) {
      console.error(`[TaskPollerService] Error polling entry ${entry.id}:`, error);
    }
  }

  /**
   * 轮询下载任务
   */
  private async pollDownloadTask(entry: DownloadEntry): Promise<void> {
    if (!this.auth || !entry.downloadTaskId) return;

    try {
      const task = await getTaskById(this.auth, entry.downloadTaskId);
      const status = normalizeStatus(task.status);

      // 发布进度更新事件
      TaskEvents.progress(entry.id, clampProgress(task.progress), task.message || '');

      if (status !== entry.status) {
        TaskEvents.update(entry.id, {
          status,
          downloadProgress: clampProgress(task.progress),
          downloadMessage: task.message || '',
          error: status === 'failed' ? task.message || '任务失败' : undefined,
        });
      }

      // 下载完成后发现扫描任务
      if (task.status === 'completed' && !entry.scanTaskId) {
        const scanTaskId = parseScanTaskIdFromDownloadResult(task.result);
        if (scanTaskId) {
          try {
            const scan = await getTaskById(this.auth, scanTaskId);
            const scanStatus = normalizeStatus(scan.status);
            TaskEvents.discovered(entry.id, undefined, scan.id);
            TaskEvents.update(entry.id, {
              scanTaskId: scan.id,
              scanProgress: clampProgress(scan.progress),
              scanMessage: scan.message || '',
              status: scanStatus === 'queued' ? 'queued' : scanStatus === 'running' ? 'running' : scanStatus,
            });
          } catch (error) {
            const message = error instanceof Error ? error.message : '扫描任务查询失败';
            TaskEvents.error(entry.id, message);
          }
        }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : '任务查询失败';
      TaskEvents.error(entry.id, message);
    }
  }

  /**
   * 轮询扫描任务
   */
  private async pollScanTask(entry: DownloadEntry): Promise<void> {
    if (!this.auth || !entry.scanTaskId) return;

    try {
      const scanTask = await getTaskById(this.auth, entry.scanTaskId);
      const scanStatus = normalizeStatus(scanTask.status);
      const archiveId =
        scanTask.status === 'completed'
          ? parseArchiveIdFromScanResult(scanTask.result)
          : null;

      // 发布进度更新事件
      TaskEvents.progress(entry.id, clampProgress(scanTask.progress), scanTask.message || '');

      if (scanStatus !== entry.status || archiveId !== entry.archiveId) {
        TaskEvents.update(entry.id, {
          scanProgress: clampProgress(scanTask.progress),
          scanMessage: scanTask.message || '',
          archiveId: archiveId ?? entry.archiveId,
          status:
            scanStatus === 'queued'
              ? 'queued'
              : scanStatus === 'running'
              ? 'running'
              : scanStatus,
          error:
            scanStatus === 'failed' ? scanTask.message || '扫描失败' : undefined,
        });
      }

      // 任务完成
      if (scanStatus === 'completed' && archiveId) {
        TaskEvents.complete(entry.id, archiveId);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : '扫描任务查询失败';
      TaskEvents.error(entry.id, message);
    }
  }

  /**
   * 发现扫描任务
   */
  private async discoverScanTask(entry: DownloadEntry): Promise<void> {
    if (!this.auth || !entry.downloadTaskId) return;

    try {
      const downloadTask = await getTaskById(this.auth, entry.downloadTaskId);
      const scanTaskId = parseScanTaskIdFromDownloadResult(downloadTask.result);
      if (!scanTaskId) return;
      const scan = await getTaskById(this.auth, scanTaskId);
      const scanStatus = normalizeStatus(scan.status);
      TaskEvents.discovered(entry.id, undefined, scan.id);
      TaskEvents.update(entry.id, {
        scanTaskId: scan.id,
        scanProgress: clampProgress(scan.progress),
        scanMessage: scan.message || '',
        status:
          scanStatus === 'queued'
            ? 'queued'
            : scanStatus === 'running'
            ? 'running'
            : scanStatus,
      });
    } catch (error) {
      // 忽略组查找错误，避免下载完成后状态翻转
      console.log('[TaskPollerService] Scan task discovery failed (ignored):', error);
    }
  }

  /**
   * 将数组分块
   */
  private chunkArray<T>(array: T[], chunkSize: number): T[][] {
    const chunks: T[][] = [];
    for (let i = 0; i < array.length; i += chunkSize) {
      chunks.push(array.slice(i, i + chunkSize));
    }
    return chunks;
  }
}

// 导出单例实例
export const taskPollerService = new TaskPollerService();
