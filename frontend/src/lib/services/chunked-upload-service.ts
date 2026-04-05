import { apiClient } from '../api';
import { TaskPoolService } from './taskpool-service';
import type { ApiEnvelope } from '@/types/common';

// 上传元数据接口
export interface UploadMetadata {
  title?: string;
  tags?: string;
  summary?: string;
  categoryId?: string | number;
  fileChecksum?: string;
  overwrite?: boolean;  // 是否覆盖已存在的文件
  targetType?: 'archive' | 'tag_icon' | 'tag_background' | 'user_avatar' | 'metadata_asset' | 'plugin';
  targetId?: string | number;
  contentType?: string;
}

// 上传进度回调接口
export type UploadStage = 'queued' | 'uploading';

export interface UploadProgressCallback {
  onProgress: (progress: number) => void;
  onStatusChange?: (stage: UploadStage) => void;
  onChunkComplete?: (chunkIndex: number, totalChunks: number, uploadedChunks: number) => void;
  onError?: (error: Error, chunkIndex?: number) => void;
}

// 上传结果接口
export interface UploadResult {
  success: boolean;
  taskId?: string;
  error?: string;
  fileExists?: boolean;  // 文件是否已存在
  data?: Record<string, any>;
}

// 上传状态接口
export interface UploadStatus {
  taskId: string;
  fileName: string;
  fileSize: number;
  totalChunks: number;
  completedChunks: number[];
  status: 'pending' | 'uploading' | 'completed' | 'failed';
  createdAt: string;
  fileHash: string;
}

// 文件验证结果接口
export interface ValidationResult {
  valid: boolean;
  error?: string;
}

/**
 * 分片上传服务
 * 支持断点续传、进度显示、错误重试等功能
 */
export class ChunkedUploadService {
  // 配置常量
  private static readonly CHUNK_SIZE = 10 * 1024 * 1024; // 10MB
  private static readonly MAX_RETRIES = 3;
  private static readonly MAX_RETRIES_5XX = 5;  // 5xx 错误允许更多重试
  // 空闲超时：600秒（10分钟），与后端 UPLOAD_IDLE_TIMEOUT_SECONDS 对齐
  // 如果在此时间内没有数据传输活动，则认为连接已断开
  private static readonly UPLOAD_IDLE_TIMEOUT = 600000;
  private static readonly SUPPORTED_EXTENSIONS = ['zip', 'rar', '7z', 'tar', 'gz', 'pdf', 'epub', 'mobi', 'cbz', 'cbr', 'cb7', 'cbt'];
  private static readonly MAX_CONCURRENT_CHUNKS = 1; // 顺序上传（与后端顺序写入一致）

  /**
   * 主要的分片上传方法
   */
  static async uploadWithChunks(
    file: File,
    metadata: UploadMetadata,
    callbacks: UploadProgressCallback
  ): Promise<UploadResult> {
    let taskId: string | null = null; // 跟踪taskId以便在错误时清理localStorage

    try {
      // 1. 文件验证
      const validation = this.validateFile(file, metadata.targetType || 'archive');
      if (!validation.valid) {
        return { success: false, error: validation.error };
      }

      // 2. 使用外部传入的哈希（不再默认做全文件哈希计算，避免大文件额外读盘）
      const fileHash = metadata.fileChecksum || '';

      // 3. 计算分片信息
      const totalChunks = Math.ceil(file.size / this.CHUNK_SIZE);

      // 4. 初始化上传会话
      const initResult = await this.initUploadSession(file.name, file.size, fileHash, totalChunks, metadata);

      // 检查是否是文件已存在的情况
      if (initResult && typeof initResult === 'object' && 'fileExists' in initResult) {
        return { success: false, fileExists: true, error: initResult.error };
      }

      taskId = initResult as string | null;
      if (!taskId) {
        return { success: false, error: 'Failed to initialize upload session' };
      }

      // 5. 等待任务进入 running 状态（TaskPool 调度机制介入）
      const waitingResult = await this.waitForTaskReady(taskId, callbacks);
      if (!waitingResult.ready) {
        await this.cancelUploadTask(taskId);
        return { success: false, error: waitingResult.error || '任务等待超时或失败' };
      }

      // 6. 不再检查断点续传，直接上传所有分片
      const completedChunks: number[] = [];
      const remainingChunks = this.getRemainingChunks(totalChunks, completedChunks);

      // 7. 上传剩余分片（传入 taskId 用于进度同步）
      const firstUploadResult = await this.uploadChunksSequentially(
        file,
        taskId,
        remainingChunks,
        totalChunks,
        callbacks
      );

      // 7. 计算总的已上传分片数（包括之前已上传的）
      const totalCompletedChunks = completedChunks.length + firstUploadResult.successCount;
      
      // 如果有失败的分片（已包含 chunk 内部重试），直接返回错误
      if (firstUploadResult.failedChunks.length > 0) {
        await this.cancelUploadTask(taskId);
        return {
          success: false,
          error: `分片上传失败: ${firstUploadResult.failedChunks.length} 个分片失败`
        };
      }

      // 8. 验证所有分片都已上传完成
      if (totalCompletedChunks !== totalChunks) {
        console.error(`分片数量不匹配: 期望 ${totalChunks}, 实际 ${totalCompletedChunks}`);
        await this.cancelUploadTask(taskId);
        return {
          success: false,
          error: `分片数量不匹配: 期望 ${totalChunks}, 实际 ${totalCompletedChunks}`
        };
      }

      // 9. 等待任务处理完成（由后端自动落盘 + asset_upload_process）
      return await this.waitForTaskCompletion(taskId, callbacks);

    } catch (error) {
      console.error('Chunked upload failed:', error);

      // 如果有taskId，清理localStorage中的上传会话数据
      if (taskId) {
        await this.cancelUploadTask(taskId);
        try {
          localStorage.removeItem(`upload_${taskId}`);

        } catch (cleanupError) {
          console.warn('Failed to clean localStorage after upload failure:', cleanupError);
        }
      }

      return {
        success: false,
        error: error instanceof Error ? error.message : 'Upload failed'
      };
    }
  }

  /**
   * 文件验证
   */
  static validateFile(file: File, targetType: UploadMetadata['targetType'] = 'archive'): ValidationResult {
    // 分片上传已实现，这里不再限制总文件大小；仅确保文件非空。
    if (file.size <= 0) {
      return { valid: false, error: '文件不能为空' };
    }

    if (targetType && targetType !== 'archive') {
      return { valid: true };
    }

    // 检查文件扩展名
    const extension = file.name.split('.').pop()?.toLowerCase();
    if (!extension || !this.SUPPORTED_EXTENSIONS.includes(extension)) {
      return {
        valid: false,
        error: `不支持的文件格式: ${extension}。支持的格式: ${this.SUPPORTED_EXTENSIONS.join(', ')}`
      };
    }

    return { valid: true };
  }

  /**
   * 初始化上传会话
   * 返回 taskId 或 null，如果文件已存在则返回特殊对象
   */
  private static async initUploadSession(
    fileName: string,
    fileSize: number,
    fileHash: string,
    totalChunks: number,
    metadata: UploadMetadata
  ): Promise<string | { fileExists: true; error: string } | null> {
    // 调用服务器初始化上传会话 - 新接口返回 { code, message, data: { taskId } }
    try {
      const targetType = metadata.targetType || 'archive';
      const response = await apiClient.post<ApiEnvelope<{ taskId: string }>>('/api/assets/upload/init', {
        filename: fileName,
        file_checksum: fileHash,
        filesize: fileSize,
        chunk_size: this.CHUNK_SIZE,
        total_chunks: totalChunks,
        title: metadata.title || '',
        tags: metadata.tags || '',
        summary: metadata.summary || '',
        category_id: metadata.categoryId || '',
        overwrite: metadata.overwrite ? 'true' : 'false',
        target_type: targetType,
        target_id: metadata.targetId ?? '',
        content_type: metadata.contentType || ''
      });

      if (response.data?.code !== 200) {
        console.error('Server failed to initialize upload session:', response.data?.message);
        return null;
      }

      const taskId = String(response.data?.data?.taskId ?? '').trim();
      if (!taskId) {
        console.error('Server did not return taskId');
        return null;
      }

      // 保存上传会话信息到localStorage
      const session = {
        taskId,
        fileName,
        fileSize,
        fileHash,
        totalChunks,
        completedChunks: [],
        status: 'pending',
        createdAt: new Date().toISOString()
      };

      localStorage.setItem(`upload_${taskId}`, JSON.stringify(session));
      return taskId;
    } catch (error: any) {
      const status = Number(error?.response?.status ?? 0);
      const message = String(error?.response?.data?.message ?? error?.message ?? '');
      if (status === 409 && message.includes('文件已存在')) {
        return { fileExists: true, error: message || '文件已存在' };
      }
      console.error('Failed to init upload session:', error);
      return null;
    }
  }

  /**
   * 等待任务进入 running 状态（TaskPool 调度机制介入）
   * 每10秒查询一次任务状态，直到任务进入 running 状态或失败
   */
  private static async waitForTaskReady(
    taskId: string,
    callbacks: UploadProgressCallback,
    maxWaitMinutes: number = 30
  ): Promise<{ ready: boolean; error?: string }> {
    const POLL_INTERVAL = 1000; // 1秒
    const MAX_ATTEMPTS = Math.ceil((maxWaitMinutes * 60 * 1000) / POLL_INTERVAL);
    let attempts = 0;
    let lastStage: UploadStage | null = null;

    console.log(`[ChunkedUpload] 开始等待任务 ${taskId} 进入 running 状态...`);

    while (attempts < MAX_ATTEMPTS) {
      try {
        const task = await TaskPoolService.getTaskById(parseInt(taskId, 10));

        if (!task) {
          console.error(`[ChunkedUpload] 任务 ${taskId} 不存在`);
          return { ready: false, error: '任务不存在' };
        }

        console.log(`[ChunkedUpload] 任务 ${taskId} 状态: ${task.status}, 进度: ${task.progress}%`);

        switch (task.status) {
          case 'running':
            console.log(`[ChunkedUpload] 任务 ${taskId} 已进入 running 状态，开始上传`);
            callbacks.onStatusChange?.('uploading');
            return { ready: true };

          case 'pending':
            // 任务还在排队中，继续等待
            if (lastStage !== 'queued') {
              callbacks.onStatusChange?.('queued');
              lastStage = 'queued';
            }
            callbacks.onProgress(0);
            break;

          case 'failed':
          case 'stopped':
            return { ready: false, error: task.message || `任务状态为 ${task.status}` };

          case 'completed':
            return { ready: false, error: '任务已完成，但未进入上传状态' };

          default:
            console.warn(`[ChunkedUpload] 任务 ${taskId} 处于未知状态: ${task.status}`);
            break;
        }

        attempts++;
        if (attempts < MAX_ATTEMPTS) {
          console.log(`[ChunkedUpload] 等待 ${attempts}/${MAX_ATTEMPTS}，下次查询在 ${POLL_INTERVAL / 1000} 秒后...`);
          await this.delay(POLL_INTERVAL);
        }
      } catch (error) {
        console.error(`[ChunkedUpload] 查询任务状态失败:`, error);
        attempts++;
        if (attempts < MAX_ATTEMPTS) {
          await this.delay(POLL_INTERVAL);
        }
      }
    }

    return { ready: false, error: `等待任务超时（${maxWaitMinutes}分钟）` };
  }


  /**
   * 获取剩余需要上传的分片
   */
  private static getRemainingChunks(totalChunks: number, completedChunks: number[]): number[] {
    const remaining: number[] = [];
    for (let i = 0; i < totalChunks; i++) {
      if (!completedChunks.includes(i)) {
        remaining.push(i);
      }
    }
    return remaining;
  }

  /**
   * 更新localStorage中的completedChunks
   */
  private static updateLocalStorageCompletedChunks(taskId: string, chunkIndex: number, totalChunks: number): void {
    try {
      const sessionData = localStorage.getItem(`upload_${taskId}`);
      if (sessionData) {
        const session = JSON.parse(sessionData);

        // 确保completedChunks数组存在
        if (!session.completedChunks) {
          session.completedChunks = [];
        }

        // 添加新的分片索引（避免重复）
        if (!session.completedChunks.includes(chunkIndex)) {
          session.completedChunks.push(chunkIndex);
          // 排序
          session.completedChunks.sort((a: number, b: number) => a - b);
        }

        // 更新状态
        if (session.completedChunks.length === totalChunks) {
          session.status = 'completed';
        } else {
          session.status = 'uploading';
        }

        // 保存回localStorage
        localStorage.setItem(`upload_${taskId}`, JSON.stringify(session));
      }
    } catch (error) {
      console.warn('Failed to update localStorage completedChunks:', error);
    }
  }

  /**
   * 顺序上传分片
   */
  private static async uploadChunksSequentially(
    file: File,
    taskId: string,
    chunkIndices: number[],
    totalChunks: number,
    callbacks: UploadProgressCallback,
    previouslyCompletedChunks: number[] = []
  ): Promise<{ successCount: number; failedChunks: number[] }> {
    const totalBytes = file.size;
    const completedChunkIndices: number[] = [];
    const failedChunks: number[] = [];

    // 顺序上传：确保 chunkIndex 单调递增，避免服务端顺序写入时乱序
    const orderedChunks = [...chunkIndices].sort((a, b) => a - b);
    for (let i = 0; i < orderedChunks.length; i++) {
      const chunkIndex = orderedChunks[i];

      try {
        // 计算当前分片之前已上传的字节数
        const previousUploadedBytes = [...previouslyCompletedChunks, ...completedChunkIndices]
          .reduce((total, idx) => {
            const start = idx * this.CHUNK_SIZE;
            const end = Math.min(start + this.CHUNK_SIZE, totalBytes);
            return total + (end - start);
          }, 0);

        // 上传分片，并实时报告进度
        await this.uploadChunkWithRetry(
          file,
          taskId,
          chunkIndex,
          totalChunks,
          (chunkLoaded, chunkTotal) => {
            // 计算总体进度：之前已完成的分片 + 当前分片内的进度
            const currentProgress = previousUploadedBytes + chunkLoaded;
            const progress = Math.round((currentProgress / totalBytes) * 100);
            callbacks.onProgress(progress);
          }
        );

        // 更新localStorage中的completedChunks
        this.updateLocalStorageCompletedChunks(taskId, chunkIndex, totalChunks);
        completedChunkIndices.push(chunkIndex);
      } catch (error) {
        console.error(`分片 ${chunkIndex} 上传最终失败:`, error);
        const errorObj = error instanceof Error ? error : new Error(String(error));
        callbacks.onError?.(errorObj, chunkIndex);

        // 顺序上传失败后，剩余分片无法继续，标记为失败后退出
        failedChunks.push(...orderedChunks.slice(i));
        break;
      }

      // 计算进度：包括之前已完成的分片和本次新完成的分片
      const allCompletedChunks = [...previouslyCompletedChunks, ...completedChunkIndices];
      // 去重并排序，确保分片索引不重复
      const uniqueCompletedChunks = Array.from(new Set(allCompletedChunks)).sort((a, b) => a - b);
      const uploadedBytes = uniqueCompletedChunks.reduce((total, idx) => {
        const start = idx * this.CHUNK_SIZE;
        const end = Math.min(start + this.CHUNK_SIZE, totalBytes);
        return total + (end - start);
      }, 0);

      const progress = Math.round((uploadedBytes / totalBytes) * 100);
      callbacks.onProgress(progress);
      callbacks.onChunkComplete?.(chunkIndex, totalChunks, uniqueCompletedChunks.length);
    }

    return { successCount: completedChunkIndices.length, failedChunks };
  }

  /**
   * 检查Promise是否已解决
   */
  private static async isPromiseResolved(promise: Promise<any>): Promise<boolean> {
    // 创建一个新的Promise来检查原始Promise的状态
    return new Promise((resolve) => {
      // 设置一个很短的超时来检查Promise状态
      const timeout = setTimeout(() => {
        resolve(false); // 如果超时，说明Promise还未完成
      }, 0);

      promise
        .then(() => {
          clearTimeout(timeout);
          resolve(true); // Promise成功完成
        })
        .catch(() => {
          clearTimeout(timeout);
          resolve(true); // Promise失败但已完成
        });
    });
  }

  /**
   * 判断错误是否可重试
   */
  private static isRetryableError(error: any): { retryable: boolean; isPending409: boolean; is5xx: boolean } {
    const status = Number(error?.response?.status ?? 0);
    const message = String(error?.response?.data?.message ?? error?.message ?? '');

    // 不可重试: 400 Bad Request, 404 Not Found, 文件已存在 (409 + 文件已存在)
    if (status === 400 || status === 404) {
      return { retryable: false, isPending409: false, is5xx: false };
    }
    if (status === 409 && message.includes('文件已存在')) {
      return { retryable: false, isPending409: false, is5xx: false };
    }

    // 可重试: 409 pending（任务排队中）
    if (status === 409) {
      return { retryable: true, isPending409: true, is5xx: false };
    }

    // 可重试: 5xx 服务器错误（允许更多重试次数）
    if (status >= 500) {
      return { retryable: true, isPending409: false, is5xx: true };
    }

    // 网络超时、连接失败等视为可重试
    return { retryable: true, isPending409: false, is5xx: false };
  }

  /**
   * 带重试机制的分片上传
   * - 区分可重试/不可重试错误
   * - 409 pending 使用更长的重试间隔（5s）
   * - 5xx 错误允许最多 5 次重试，指数退避上限 16s
   */
  private static async uploadChunkWithRetry(
    file: File,
    taskId: string,
    chunkIndex: number,
    totalChunks: number,
    onChunkProgress?: (loaded: number, total: number) => void,
    retryCount = 0
  ): Promise<void> {
    try {
      const chunk = await this.getFileChunk(file, chunkIndex);
      await this.uploadChunk(taskId, chunkIndex, totalChunks, chunk, onChunkProgress);
    } catch (error) {
      const { retryable, isPending409, is5xx } = this.isRetryableError(error);

      if (!retryable) {
        // 不可重试错误，直接抛出
        throw new Error(`分片 ${chunkIndex} 上传失败 (不可重试): ${error instanceof Error ? error.message : 'Unknown error'}`);
      }

      const maxRetries = is5xx ? this.MAX_RETRIES_5XX : this.MAX_RETRIES;

      if (retryCount < maxRetries) {
        let delayMs: number;
        if (isPending409) {
          // 任务排队中：使用固定 5s 间隔
          delayMs = 5000;
        } else {
          // 指数退避：1s, 2s, 4s, 8s, 16s（上限 16s）
          delayMs = Math.min(1000 * Math.pow(2, retryCount), 16000);
        }

        await this.delay(delayMs);
        return this.uploadChunkWithRetry(file, taskId, chunkIndex, totalChunks, onChunkProgress, retryCount + 1);
      } else {
        console.error(`分片 ${chunkIndex} 重试 ${maxRetries} 次后仍然失败`);
        throw new Error(`分片 ${chunkIndex} 上传失败: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
    }
  }

  /**
   * 获取文件分片
   */
  private static async getFileChunk(file: File, chunkIndex: number): Promise<Blob> {
    const start = chunkIndex * this.CHUNK_SIZE;
    const end = Math.min(start + this.CHUNK_SIZE, file.size);
    return file.slice(start, end);
  }

  /**
   * 上传单个分片
   * 使用空闲超时机制：监控数据传输活动，如果长时间无数据传输则取消请求
   */
  private static async uploadChunk(
    taskId: string,
    chunkIndex: number,
    totalChunks: number,
    chunkData: Blob,
    onChunkProgress?: (loaded: number, total: number) => void
  ): Promise<void> {
    // 使用查询参数而不是FormData，因为后端使用getQuery获取参数
    const params = new URLSearchParams();
    params.append('taskId', taskId);
    params.append('chunkIndex', chunkIndex.toString());
    params.append('totalChunks', totalChunks.toString());
    params.append('filename', 'chunk.bin');

    // 创建 AbortController 用于空闲超时取消
    const abortController = new AbortController();
    let lastActivityTime = Date.now();
    let idleCheckInterval: NodeJS.Timeout | null = null;

    // 启动空闲超时检测
    const startIdleCheck = () => {
      idleCheckInterval = setInterval(() => {
        const idleTime = Date.now() - lastActivityTime;
        if (idleTime > this.UPLOAD_IDLE_TIMEOUT) {
          console.warn(`分片 ${chunkIndex} 上传空闲超时（${idleTime}ms），取消请求`);
          abortController.abort();
          if (idleCheckInterval) {
            clearInterval(idleCheckInterval);
            idleCheckInterval = null;
          }
        }
      }, 5000); // 每5秒检查一次
    };

    // 停止空闲超时检测
    const stopIdleCheck = () => {
      if (idleCheckInterval) {
        clearInterval(idleCheckInterval);
        idleCheckInterval = null;
      }
    };

    try {
      startIdleCheck();

      const response = await apiClient.put<ApiEnvelope<Record<string, any>>>(
        `/api/assets/upload/chunk?${params.toString()}`,
        chunkData,
        {
          headers: {
            'Content-Type': 'application/octet-stream',
          },
          signal: abortController.signal,
          // 不设置固定 timeout，依赖空闲超时检测
          onUploadProgress: (progressEvent) => {
            // 更新最后活动时间
            lastActivityTime = Date.now();

            if (progressEvent.total && onChunkProgress) {
              onChunkProgress(progressEvent.loaded, progressEvent.total);
            }
          },
        }
      );

      stopIdleCheck();

      if (response.data?.code !== 200) {
        throw new Error(response.data?.message || `Chunk ${chunkIndex} upload failed`);
      }
    } catch (error: any) {
      stopIdleCheck();

      // 如果是空闲超时导致的取消，抛出特定错误
      if (error.name === 'AbortError' || error.code === 'ERR_CANCELED') {
        throw new Error(`分片 ${chunkIndex} 上传空闲超时（${this.UPLOAD_IDLE_TIMEOUT / 1000}秒内无数据传输）`);
      }

      throw error;
    }
  }

  /**
   * 等待后端任务完成（asset_upload_process + consume task）
   */
  private static async waitForTaskCompletion(
    taskId: string,
    callbacks: UploadProgressCallback,
    maxWaitMinutes: number = 60
  ): Promise<UploadResult> {
    const timeoutMs = maxWaitMinutes * 60 * 1000;
    let lastProgress = 0;
    callbacks.onStatusChange?.('uploading');

    try {
      const task = await TaskPoolService.waitForTaskTerminal(parseInt(taskId, 10), {
        timeoutMs,
        onUpdate: (nextTask) => {
          if (typeof nextTask.progress === 'number') {
            lastProgress = Math.max(lastProgress, Math.min(100, Math.max(0, nextTask.progress)));
            callbacks.onProgress(lastProgress);
          }
        },
      });

      this.cleanupUploadSession(taskId);
      if (task.status === 'completed') {
        let resultPayload = this.parseTaskResult(task.result);
        const consumeTaskId = Number(resultPayload?.consume_task_id || 0);
        if (consumeTaskId > 0) {
          const consumeTask = await TaskPoolService.waitForTaskTerminal(consumeTaskId, {
            timeoutMs,
            onUpdate: (nextTask) => {
              if (typeof nextTask.progress === 'number') {
                lastProgress = Math.max(lastProgress, Math.min(100, Math.max(0, nextTask.progress)));
                callbacks.onProgress(lastProgress);
              }
            },
          });

          if (consumeTask.status !== 'completed') {
            return { success: false, error: consumeTask.message || `任务状态为 ${consumeTask.status}` };
          }
          const consumePayload = this.parseTaskResult(consumeTask.result);
          resultPayload = { ...(resultPayload || {}), ...(consumePayload || {}) };
        }
        return { success: true, taskId, data: resultPayload || undefined };
      }
      return { success: false, error: task.message || `任务状态为 ${task.status}` };
    } catch (error) {
      console.error(`[ChunkedUpload] 查询任务完成状态失败:`, error);
      this.cleanupUploadSession(taskId);
      return { success: false, error: `等待任务完成超时（${maxWaitMinutes}分钟）` };
    }
  }

  
  /**
   * 恢复上传
   */
  static async resumeUpload(taskId: string, file: File, metadata: UploadMetadata, callbacks: UploadProgressCallback): Promise<UploadResult> {
    try {
      // 不再检查上传状态，直接从localStorage获取基本信息
      const sessionData = localStorage.getItem(`upload_${taskId}`);
      if (!sessionData) {
        return { success: false, error: 'Upload session not found' };
      }

      const session = JSON.parse(sessionData);
      const completedChunks = session.completedChunks || [];
      const totalChunks = session.totalChunks || 0;
      // const fileHash = session.fileHash || '';
      // const fileName = session.fileName || '';

      if (session.status === 'completed') {
        return { success: false, error: 'Upload already completed' };
      }

      // 仅排队中的任务需要检查调度状态，已进入上传状态的任务不再打断
      if (session.status === 'pending') {
        const waitingResult = await this.waitForTaskReady(taskId, callbacks);
        if (!waitingResult.ready) {
          await this.cancelUploadTask(taskId);
          return { success: false, error: waitingResult.error || '任务等待超时或失败' };
        }
      }

      // 继续上传剩余分片
      const remainingChunks = this.getRemainingChunks(totalChunks, completedChunks);

      // 创建包装的回调，以正确计算总的已上传分片数
      const wrappedCallbacks: UploadProgressCallback = {
        onProgress: callbacks.onProgress,
        onChunkComplete: (chunkIndex, totalChunks, newlyUploadedChunks) => {
          // 计算总的已上传分片数（包括之前已上传的）
          // 注意：newlyUploadedChunks 是本次上传中成功完成的分片数量
          // 我们需要加上之前已经完成的分片数量
          const totalUploadedChunks = completedChunks.length + newlyUploadedChunks;
          callbacks.onChunkComplete?.(chunkIndex, totalChunks, totalUploadedChunks);
        },
        onError: callbacks.onError
      };

      const uploadResult = await this.uploadChunksSequentially(
        file,
        taskId,
        remainingChunks,
        totalChunks,
        wrappedCallbacks
      );

      // 计算总的已上传分片数（包括之前已上传的）
      const totalCompletedChunks = completedChunks.length + uploadResult.successCount;

      // 如果有失败的分片（已包含 chunk 内部重试），直接返回错误
      if (uploadResult.failedChunks.length > 0) {
        // 清理localStorage中的失败会话数据
        await this.cancelUploadTask(taskId);
        try {
          localStorage.removeItem(`upload_${taskId}`);

        } catch (cleanupError) {
          console.warn('Failed to clean localStorage after failed resume upload:', cleanupError);
        }

        return {
          success: false,
          error: `恢复上传时分片上传失败: ${uploadResult.failedChunks.length} 个分片失败`
        };
      }

      // 验证所有分片都已上传完成
      if (totalCompletedChunks !== totalChunks) {
        console.error(`恢复上传分片数量不匹配: 期望 ${totalChunks}, 实际 ${totalCompletedChunks}`);

        // 清理localStorage中的失败会话数据
        await this.cancelUploadTask(taskId);
        try {
          localStorage.removeItem(`upload_${taskId}`);

        } catch (cleanupError) {
          console.warn('Failed to clean localStorage after resume upload chunk count mismatch:', cleanupError);
        }

        return {
          success: false,
          error: `恢复上传分片数量不匹配: 期望 ${totalChunks}, 实际 ${totalCompletedChunks}`
        };
      }

      // 等待任务处理完成
      return await this.waitForTaskCompletion(taskId, callbacks);

    } catch (error) {
      // 恢复上传失败时清理localStorage
      await this.cancelUploadTask(taskId);
      try {
        localStorage.removeItem(`upload_${taskId}`);

      } catch (cleanupError) {
        console.warn('Failed to clean localStorage after resume upload failure:', cleanupError);
      }

      return {
        success: false,
        error: error instanceof Error ? error.message : 'Failed to resume upload'
      };
    }
  }

  /**
   * 延迟函数
   */
  private static delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 将服务端上传任务标记为失败，释放 TaskPool worker 槽位
   */
  private static async cancelUploadTask(taskId: string): Promise<void> {
    try {
      await apiClient.delete(`/api/assets/upload/${taskId}`);
    } catch (error) {
      console.warn(`Failed to cancel upload task ${taskId}:`, error);
    }
  }

  private static parseTaskResult(raw: unknown): Record<string, any> | null {
    if (typeof raw !== 'string' || raw.trim() === '') return null;
    try {
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object') return null;
      return parsed as Record<string, any>;
    } catch {
      return null;
    }
  }

  /**
   * 清理过期的上传会话数据
   * @param maxAge 最大保留时间（毫秒），默认24小时
   */
  static cleanupExpiredUploadSessions(maxAge: number = 24 * 60 * 60 * 1000): void {
    try {
      const keysToRemove: string[] = [];
      const now = Date.now();

      // 遍历localStorage中所有键
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key && key.startsWith('upload_')) {
          try {
            const sessionData = localStorage.getItem(key);
            if (sessionData) {
              const session = JSON.parse(sessionData);
              const createdAt = new Date(session.createdAt).getTime();

              // 如果会话过期或已经完成，添加到待清理列表
              const isExpired = now - createdAt > maxAge;
              const isCompleted = session.status === 'completed';

              if (isCompleted || isExpired) {
                keysToRemove.push(key);
              }
            }
          } catch {
            // 如果数据损坏，也清理掉
            keysToRemove.push(key);
            console.warn(`Corrupted upload session data detected: ${key}`);
          }
        }
      }

      // 清理过期的会话数据
      keysToRemove.forEach(key => {
        localStorage.removeItem(key);
      });

      // Upload session cleanup completed
    } catch (error) {
      console.warn('Failed to cleanup expired upload sessions:', error);
    }
  }

  /**
   * 清理指定的上传会话数据
   * @param taskId 要清理的任务ID
   */
  static cleanupUploadSession(taskId: string): void {
    try {
      localStorage.removeItem(`upload_${taskId}`);

    } catch (error) {
      console.warn(`Failed to cleanup upload session ${taskId}:`, error);
    }
  }

  /**
   * 获取错误消息
   */
  static getErrorMessage(error: any): string {
    if (error.response?.status === 413) {
      return "文件太大，请选择较小的文件";
    } else if (error.response?.status === 415) {
      return "不支持的文件格式";
    } else if (error.code === 'NETWORK_ERROR') {
      return "网络连接失败，请检查网络后重试";
    } else if (error.response?.status === 408) {
      return "上传超时，请检查网络连接或尝试较小的文件";
    } else {
      return error.message || "上传失败，请稍后重试";
    }
  }
}
