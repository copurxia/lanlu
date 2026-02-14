import { apiClient } from '../api';
import { Archive, SearchResponse, SearchParams, RandomParams, ArchiveMetadata } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';
import { ServerInfo } from '@/types/server';
import { ChunkedUploadService, UploadMetadata, UploadProgressCallback, UploadResult } from './chunked-upload-service';
import { TaskPoolService } from './taskpool-service';
import { isSuccessResponse } from '@/lib/utils/api-utils';
import type { Task } from '@/types/task';

// 下载相关接口定义
export interface DownloadMetadata {
  title?: string;
  tags?: string;
  summary?: string;
  categoryId?: string | number;
}

export interface DownloadProgressCallback {
  onProgress?: (progress: number) => void;
  onComplete?: (result: DownloadResult) => void;
  onError?: (error: string) => void;
}

export interface DownloadResult {
  success: boolean;
  archives: Array<{
    relativePath: string;
    pluginRelativePath: string;
    filename: string;
  }>;
  id?: string;
  error?: string;
}

export interface MetadataPluginRunCallbacks {
  onUpdate?: (task: Task) => void;
}

export interface MetadataPluginInputMetadata {
  title?: string;
  summary?: string;
  tags?: string;
}

export interface MetadataPluginRunOptions {
  writeBack?: boolean;
  metadata?: MetadataPluginInputMetadata;
}

// 页面信息接口（支持图片、视频和HTML）
export interface PageInfo {
  url: string;
  type: 'image' | 'video' | 'html';
  title?: string;  // 章节标题（EPUB类型会有值）
}

export class ArchiveService {
  static async search(params: SearchParams, options?: { signal?: AbortSignal }): Promise<SearchResponse> {
    const normalizedParams: Record<string, unknown> = { ...params };
    normalizedParams.page = Math.max(1, Math.trunc(params.page ?? 1));
    normalizedParams.pageSize = Math.max(1, Math.trunc(params.pageSize ?? 20));

    const response = await apiClient.get('/api/search', { params: normalizedParams, signal: options?.signal });
    return response.data;
  }

  static async getRandom(params: RandomParams = {}): Promise<Array<Archive | Tankoubon>> {
    const response = await apiClient.get('/api/search/random', {
      params: {
        count: params.count || 5,
        filter: params.filter,
        category: params.category,
        newonly: params.newonly,
        untaggedonly: params.untaggedonly,
        groupby_tanks: params.groupby_tanks ?? true,
        lang: params.lang
      }
    });
    return response.data.data || [];
  }

  static async getMetadata(id: string, lang?: string): Promise<ArchiveMetadata> {
    const params: Record<string, string> = {};
    if (lang) {
      params.lang = lang;
    }
    const response = await apiClient.get(`/api/archives/${id}/metadata`, { params });
    return response.data;
  }

  static async updateMetadata(id: string, metadata: Partial<ArchiveMetadata>, lang?: string): Promise<void> {
    const params = new URLSearchParams();

    // 添加语言参数
    if (lang) {
      params.append('lang', lang);
    }

    if (metadata.title !== undefined) {
      params.append('title', metadata.title);
    }
    if (metadata.summary !== undefined) {
      params.append('summary', metadata.summary);
    }
    if (metadata.tags !== undefined) {
      params.append('tags', metadata.tags);
    }
    if (metadata.cover !== undefined) {
      params.append('cover', metadata.cover);
    }

    await apiClient.put(`/api/archives/${id}/metadata?${params.toString()}`);
  }

  static async getFiles(id: string): Promise<{ pages: PageInfo[]; progress: number }> {
    const response = await apiClient.get(`/api/archives/${id}/files`);
    const pages = (response.data.pages || []).map((page: PageInfo) => ({
      ...page,
      url: this.addTokenToUrl(page.url)
    }));
    return {
      pages,
      progress: response.data.progress || 0
    };
  }

  /**
   * 设置归档为新状态（PUT /api/archives/:id/isnew）
   */
  static async setIsNew(id: string): Promise<void> {
    await apiClient.put(`/api/archives/${id}/isnew`);
  }

  /**
   * 清除归档的新标记（DELETE /api/archives/:id/isnew）
   */
  static async clearIsNew(id: string): Promise<void> {
    await apiClient.delete(`/api/archives/${id}/isnew`);
  }

  /**
   * 更新阅读进度并自动标记为已读（PUT /api/archives/:id/progress/:page）
   */
  static async updateProgress(id: string, page: number): Promise<void> {
    await apiClient.put(`/api/archives/${id}/progress/${page}`);
  }

  /**
   * 删除档案（仅管理员可用）
   */
  static async deleteArchive(id: string): Promise<void> {
    await apiClient.delete(`/api/archives/${id}`);
  }

  static getAssetUrl(assetId?: number): string {
    if (!assetId || assetId <= 0) {
      return '';
    }
    return `/api/assets/${assetId}`;
  }

  static getPageUrl(id: string, path: string): string {
    // 使用相对路径，因为前端和后端部署在一起
    // 如果path被编码了，需要先解码再重新编码
    try {
      // 尝试解码path，如果已经是编码状态
      return decodeURIComponent(path);
    } catch {
      // 如果解码失败，说明path已经是正确格式
      return `/api/archives/${id}/page?path=${path}`;
    }
  }

  static getDownloadUrl(id: string): string {
    return `/api/archives/${id}/download`;
  }

  /**
   * Cookie 鉴权下无需再拼接 token query。
   */
  static addTokenToUrl(url: string): string {
    return url;
  }

  static async getServerInfo(): Promise<ServerInfo> {
    const response = await apiClient.get('/api/info');
    return response.data;
  }

  /**
   * 新的分片上传方法（推荐使用）
   * 支持断点续传、进度显示、错误重试等功能
   */
  static async uploadArchiveWithChunks(
    file: File,
    metadata?: UploadMetadata,
    callbacks?: UploadProgressCallback
  ): Promise<UploadResult> {
    // 默认回调函数
    const defaultCallbacks: UploadProgressCallback = {
      onProgress: () => {},
      onChunkComplete: () => {},
      onError: () => {}
    };

    return await ChunkedUploadService.uploadWithChunks(
      file,
      metadata || {},
      callbacks || defaultCallbacks
    );
  }

  
  /**
   * 恢复上传
   */
  static async resumeUpload(
    taskId: string,
    file: File,
    metadata?: UploadMetadata,
    callbacks?: UploadProgressCallback
  ): Promise<UploadResult> {
    const defaultCallbacks: UploadProgressCallback = {
      onProgress: () => {},
      onChunkComplete: () => {},
      onError: () => {}
    };

    return await ChunkedUploadService.resumeUpload(
      taskId,
      file,
      metadata || {},
      callbacks || defaultCallbacks
    );
  }

  /**
   * 验证文件
   */
  static validateFile(file: File) {
    return ChunkedUploadService.validateFile(file);
  }

  /**
   * 获取错误消息
   */
  static getUploadErrorMessage(error: any): string {
    return ChunkedUploadService.getErrorMessage(error);
  }

  // ==================== 下载相关方法 ====================

  /**
   * 从单个URL下载档案
   * @param url 下载链接
   * @param metadata 下载元数据
   * @param callbacks 进度回调
   */
  static async downloadFromUrl(
    url: string,
    metadata?: DownloadMetadata,
    callbacks?: DownloadProgressCallback
  ): Promise<DownloadResult> {
    try {
      callbacks?.onProgress?.(0);

      const response = await apiClient.post('/api/download_url', {
        url,
        title: metadata?.title,
        tags: metadata?.tags,
        summary: metadata?.summary,
        category_id: metadata?.categoryId
      });

      const rawSuccess = response.data?.success;
      const enqueueSuccess = isSuccessResponse(rawSuccess);

      if (!enqueueSuccess) {
        const errorMessage = response.data?.error || 'Download failed';
        callbacks?.onError?.(errorMessage);
        return { success: false, error: errorMessage, archives: [] };
      }

      const jobId = response.data?.job;
      if (!jobId) {
        // 兼容旧返回（若后端仍直接返回id等信息）
        const result: DownloadResult = {
          success: true,
          id: response.data.id,
          error: response.data.error,
          archives: response.data.relative_path ? [{
            relativePath: response.data.relative_path,
            pluginRelativePath: response.data.plugin_relative_path,
            filename: response.data.filename
          }] : []
        };
        callbacks?.onProgress?.(100);
        callbacks?.onComplete?.(result);
        return result;
      }

      const finalTask = await this.waitForTaskCompletion(Number(jobId), (task) => {
        const p = typeof task.progress === 'number' ? task.progress : 0;
        callbacks?.onProgress?.(Math.max(0, Math.min(100, p)));
      });

      const parsed = this.parseTaskOutput(finalTask);
      if (finalTask.status === 'failed' || parsed.success === false) {
        const err = parsed.error || finalTask.result || finalTask.message || 'Download failed';
        const failResult: DownloadResult = { success: false, error: err, archives: [] };
        callbacks?.onComplete?.(failResult);
        return failResult;
      }

      const okResult: DownloadResult = {
        success: true,
        id: parsed.id,
        archives: parsed.archives || []
      };
      callbacks?.onProgress?.(100);
      callbacks?.onComplete?.(okResult);
      return okResult;
    } catch (error: any) {
      const errorMessage = error.response?.data?.error || error.message || 'Download failed';
      callbacks?.onError?.(errorMessage);

      return {
        success: false,
        error: errorMessage,
        archives: []
      };
    }
  }

  /**
   * 执行元数据插件（进入TaskPool，返回的job由前端轮询）
   */
  static async runMetadataPlugin(
    archiveId: string,
    namespace: string,
    param?: string,
    callbacks?: MetadataPluginRunCallbacks,
    options?: MetadataPluginRunOptions
  ): Promise<Task> {
    return await this.runMetadataPluginForTarget(
      'archive',
      archiveId,
      namespace,
      param,
      callbacks,
      options
    );
  }

  /**
   * 执行元数据插件（支持 archive / tankoubon 目标）
   * - Preview (writeBack=false): 返回 deno_task，前端读取输出并填充编辑表单
   * - Write-back (writeBack=true): 返回 metadata_plugin，再跟踪 callback 任务完成持久化
   */
  static async runMetadataPluginForTarget(
    targetType: 'archive' | 'tankoubon',
    targetId: string,
    namespace: string,
    param?: string,
    callbacks?: MetadataPluginRunCallbacks,
    options?: MetadataPluginRunOptions
  ): Promise<Task> {
    const payload: Record<string, unknown> = {
      target_type: targetType,
      target_id: targetId,
      // Backward-compatible field; backend ignores it when target_* is present.
      archive_id: targetId,
      namespace,
      param: param || '',
      // Default is preview/query (no persistence). Explicitly pass the flag so behavior is stable.
      write_back: options?.writeBack ? 1 : 0,
    };
    if (options?.metadata) {
      payload.metadata = options.metadata;
    }

    const response = await apiClient.post('/api/metadata_plugin', payload);

    const rawSuccess = response.data?.success;
    const enqueueSuccess = isSuccessResponse(rawSuccess);

    if (!enqueueSuccess) {
      const errorMessage = response.data?.error || 'Metadata plugin enqueue failed';
      throw new Error(errorMessage);
    }

    const jobId = response.data?.job;
    if (!jobId) {
      throw new Error('No job id returned');
    }

    // Two modes:
    // - Preview/query (default): API returns a `deno_task` job. Frontend reads plugin output from that task.
    // - Write-back: API returns a `metadata_plugin` job which spawns a callback that persists data.
    const taskType = String(response.data?.task_type || response.data?.taskType || '').trim();
    const writeBack = Boolean(response.data?.write_back ?? response.data?.writeBack ?? options?.writeBack);
    if (!writeBack || taskType === 'deno_task') {
      return await this.waitForTaskCompletion(Number(jobId), (task) => {
        callbacks?.onUpdate?.(task);
      });
    }

    const enqueueTask = await this.waitForTaskCompletion(Number(jobId), (task) => {
      callbacks?.onUpdate?.(task);
    });

    let callbackTaskId: number | undefined;
    try {
      const out = enqueueTask.result ? JSON.parse(enqueueTask.result) : null;
      const rawId = out?.callback_task_id ?? out?.callbackTaskId;
      if (typeof rawId === 'number') callbackTaskId = rawId;
      else if (typeof rawId === 'string' && rawId.trim() !== '') callbackTaskId = Number(rawId);
    } catch {
      // ignore parse errors; fall back to returning enqueueTask
    }

    if (!callbackTaskId || !Number.isFinite(callbackTaskId) || callbackTaskId <= 0) {
      return enqueueTask;
    }

    const finalTask = await this.waitForTaskCompletion(callbackTaskId, (task) => {
      callbacks?.onUpdate?.(task);
    });

    return finalTask;
  }

  private static async waitForTaskCompletion(
    jobId: number,
    onUpdate?: (task: Task) => void,
    options?: { intervalMs?: number; timeoutMs?: number }
  ): Promise<Task> {
    const intervalMs = options?.intervalMs ?? 800;
    const timeoutMs = options?.timeoutMs ?? 10 * 60 * 1000;
    const start = Date.now();

    while (true) {
      const task = await TaskPoolService.getTaskById(jobId);
      onUpdate?.(task);

      if (task.status === 'completed' || task.status === 'failed' || task.status === 'stopped') {
        return task;
      }
      if (Date.now() - start > timeoutMs) {
        throw new Error(`Task ${jobId} timeout`);
      }
      await new Promise((r) => setTimeout(r, intervalMs));
    }
  }

  private static parseTaskOutput(task: Task): {
    success: boolean;
    id?: string;
    error?: string;
    filename?: string;
    relativePath?: string;
    pluginRelativePath?: string;
    archives?: Array<{
      relativePath: string;
      pluginRelativePath: string;
      filename: string;
    }>;
  } {
    const raw = task.result;
    if (!raw) return { success: task.status === 'completed', archives: [] };
    try {
      const obj = JSON.parse(raw);
      const success = isSuccessResponse(obj?.success);

      // 解析 archives 数组
      if (obj?.archives && Array.isArray(obj.archives)) {
        return {
          success,
          archives: obj.archives.map((archive: any) => ({
            relativePath: archive.relative_path,
            pluginRelativePath: archive.plugin_relative_path,
            filename: archive.filename
          }))
        };
      }

      return {
        success,
        id: obj?.id,
        error: obj?.error,
        filename: obj?.filename,
        relativePath: obj?.relative_path,
        pluginRelativePath: obj?.plugin_relative_path,
        archives: []
      };
    } catch {
      return { success: task.status === 'completed', archives: [] };
    }
  }

  /**
   * 批量下载URL
   * @param urls 下载链接数组
   * @param metadata 下载元数据
   * @param callbacks 进度回调
   */
  static async downloadMultipleUrls(
    urls: string[],
    metadata?: DownloadMetadata,
    callbacks?: DownloadProgressCallback
  ): Promise<DownloadResult[]> {
    const results: DownloadResult[] = [];

    for (let i = 0; i < urls.length; i++) {
      const url = urls[i].trim();
      if (!url) continue;

      try {
        const result = await this.downloadFromUrl(url, metadata, {
          onProgress: (progress) => {
            const overallProgress = ((i * 100) + progress) / urls.length;
            callbacks?.onProgress?.(Math.round(overallProgress));
          },
          onComplete: callbacks?.onComplete,
          onError: callbacks?.onError
        });

        results.push(result);
      } catch (error: any) {
        results.push({
          success: false,
          error: error.message || 'Download failed',
          archives: []
        });
      }
    }

    return results;
  }

  /**
   * 模拟下载进度（用于UI测试，实际会调用真实API）
   * @param url 下载链接
   * @param callbacks 进度回调
   */
  static async simulateDownload(
    url: string,
    callbacks?: DownloadProgressCallback
  ): Promise<DownloadResult> {
    try {
      // 模拟下载进度
      for (let i = 0; i <= 100; i += 10) {
        await new Promise(resolve => setTimeout(resolve, 200));
        callbacks?.onProgress?.(i);
      }

      const result: DownloadResult = {
        success: true,
        id: Math.random().toString(36).substr(2, 9),
        archives: [{
          relativePath: `archive/archive_${Date.now()}.zip`,
          pluginRelativePath: `plugins/simulate/archive_${Date.now()}.zip`,
          filename: `archive_${Date.now()}.zip`
        }]
      };

      callbacks?.onComplete?.(result);
      return result;
    } catch (error: any) {
      const errorMessage = error.message || 'Download failed';
      callbacks?.onError?.(errorMessage);

      return {
        success: false,
        error: errorMessage,
        archives: []
      };
    }
  }
}
