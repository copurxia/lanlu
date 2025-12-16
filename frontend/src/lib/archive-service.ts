import { apiClient } from './api';
import { Archive, SearchResponse, SearchParams, RandomParams, ArchiveMetadata } from '@/types/archive';
import { ServerInfo } from '@/types/server';
import { ChunkedUploadService, UploadMetadata, UploadProgressCallback, UploadResult } from './chunked-upload-service';
import { MinionService } from './minion-service';
import type { MinionTask } from '@/types/minion';

// 下载相关接口定义
export interface DownloadMetadata {
  title?: string;
  tags?: string;
  summary?: string;
  categoryId?: string;
}

export interface DownloadProgressCallback {
  onProgress?: (progress: number) => void;
  onComplete?: (result: DownloadResult) => void;
  onError?: (error: string) => void;
}

export interface DownloadResult {
  success: boolean;
  id?: string;
  error?: string;
  filename?: string;
  size?: number;
  relativePath?: string;
  pluginRelativePath?: string;
}

export interface MetadataPluginRunCallbacks {
  onUpdate?: (task: MinionTask) => void;
}

export class ArchiveService {
  static async search(params: SearchParams): Promise<SearchResponse> {
    const response = await apiClient.get('/api/search', { params });
    return response.data;
  }

  static async getRandom(params: RandomParams = {}): Promise<Archive[]> {
    const response = await apiClient.get('/api/search/random', { 
      params: {
        count: params.count || 5,
        filter: params.filter,
        category: params.category,
        newonly: params.newonly,
        untaggedonly: params.untaggedonly
      }
    });
    return response.data.data || [];
  }

  static async getMetadata(id: string): Promise<ArchiveMetadata> {
    const response = await apiClient.get(`/api/archives/${id}/metadata`);
    return response.data;
  }

  static async updateMetadata(id: string, metadata: Partial<ArchiveMetadata>): Promise<void> {
    const params = new URLSearchParams();
    
    if (metadata.title !== undefined) {
      params.append('title', metadata.title);
    }
    if (metadata.summary !== undefined) {
      params.append('summary', metadata.summary);
    }
    if (metadata.tags !== undefined) {
      params.append('tags', metadata.tags);
    }
    
    await apiClient.put(`/api/archives/${id}/metadata?${params.toString()}`);
  }

  static async getFiles(id: string): Promise<string[]> {
    const response = await apiClient.get(`/api/archives/${id}/files`);
    return response.data.pages || [];
  }

  static async getArchive(id: string): Promise<any> {
    const response = await apiClient.get(`/api/archives/${id}`);
    return response.data;
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
   * 删除档案（仅管理员可用）
   */
  static async deleteArchive(id: string): Promise<void> {
    await apiClient.delete(`/api/archives/${id}`);
  }

  static getThumbnailUrl(id: string, page: number = 1): string {
    // 使用相对路径，因为前端和后端部署在一起
    return `/api/archives/${id}/thumbnail?page=${page}`;
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

  static async getServerInfo(): Promise<ServerInfo> {
    const response = await apiClient.get('/api/info');
    return response.data;
  }

  /**
   * 传统上传方法（保持向后兼容）
   * @deprecated 建议使用 uploadArchiveWithChunks 方法
   */
  static async uploadArchive(
    file: File,
    metadata?: {
      title?: string;
      tags?: string;
      summary?: string;
      categoryId?: string;
      fileChecksum?: string;
    }
  ): Promise<{ success: boolean; id?: string; error?: string }> {
    // 添加元数据作为查询参数
    const params = new URLSearchParams();
    if (metadata?.title) params.append('title', metadata.title);
    if (metadata?.tags) params.append('tags', metadata.tags);
    if (metadata?.summary) params.append('summary', metadata.summary);
    if (metadata?.categoryId) params.append('category_id', metadata.categoryId);
    if (metadata?.fileChecksum) params.append('file_checksum', metadata.fileChecksum);
    params.append('filename', file.name);
    
    try {
      // 将文件转换为 ArrayBuffer
      const arrayBuffer = await file.arrayBuffer();
      
      const response = await apiClient.put(`/api/archives/upload?${params.toString()}`, arrayBuffer, {
        headers: {
          'Content-Type': 'application/octet-stream',
        },
      });
      
      return {
        success: response.data.success === 1,
        id: response.data.id,
        error: response.data.error,
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.error || 'Upload failed',
      };
    }
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
      const enqueueSuccess =
        rawSuccess === true ||
        rawSuccess === 1 ||
        rawSuccess === "1" ||
        rawSuccess === "true";

      if (!enqueueSuccess) {
        const errorMessage = response.data?.error || 'Download failed';
        callbacks?.onError?.(errorMessage);
        return { success: false, error: errorMessage };
      }

      const jobId = response.data?.job;
      if (!jobId) {
        // 兼容旧返回（若后端仍直接返回id等信息）
        const result: DownloadResult = {
          success: true,
          id: response.data.id,
          error: response.data.error,
          filename: response.data.filename,
          size: response.data.size,
          relativePath: response.data.relative_path,
          pluginRelativePath: response.data.plugin_relative_path
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
        const failResult: DownloadResult = { success: false, error: err };
        callbacks?.onComplete?.(failResult);
        return failResult;
      }

      const okResult: DownloadResult = {
        success: true,
        id: parsed.id,
        filename: parsed.filename,
        relativePath: parsed.relativePath,
        pluginRelativePath: parsed.pluginRelativePath
      };
      callbacks?.onProgress?.(100);
      callbacks?.onComplete?.(okResult);
      return okResult;
    } catch (error: any) {
      const errorMessage = error.response?.data?.error || error.message || 'Download failed';
      callbacks?.onError?.(errorMessage);

      return {
        success: false,
        error: errorMessage
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
    callbacks?: MetadataPluginRunCallbacks
  ): Promise<MinionTask> {
    const response = await apiClient.post('/api/metadata_plugin', {
      archive_id: archiveId,
      namespace,
      param: param || ''
    });

    const rawSuccess = response.data?.success;
    const enqueueSuccess =
      rawSuccess === true ||
      rawSuccess === 1 ||
      rawSuccess === "1" ||
      rawSuccess === "true";

    if (!enqueueSuccess) {
      const errorMessage = response.data?.error || 'Metadata plugin enqueue failed';
      throw new Error(errorMessage);
    }

    const jobId = response.data?.job;
    if (!jobId) {
      throw new Error('No job id returned');
    }

    const finalTask = await this.waitForTaskCompletion(Number(jobId), (task) => {
      callbacks?.onUpdate?.(task);
    });

    return finalTask;
  }

  private static async waitForTaskCompletion(
    jobId: number,
    onUpdate?: (task: MinionTask) => void,
    options?: { intervalMs?: number; timeoutMs?: number }
  ): Promise<MinionTask> {
    const intervalMs = options?.intervalMs ?? 800;
    const timeoutMs = options?.timeoutMs ?? 10 * 60 * 1000;
    const start = Date.now();

    while (true) {
      const task = await MinionService.getTaskById(jobId);
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

  private static parseTaskOutput(task: MinionTask): {
    success: boolean;
    id?: string;
    error?: string;
    filename?: string;
    relativePath?: string;
    pluginRelativePath?: string;
  } {
    const raw = task.result;
    if (!raw) return { success: task.status === 'completed' };
    try {
      const obj = JSON.parse(raw);
      const rawSuccess = obj?.success;
      const success =
        rawSuccess === true ||
        rawSuccess === 1 ||
        rawSuccess === "1" ||
        rawSuccess === "true";

      return {
        success,
        id: obj?.id,
        error: obj?.error,
        filename: obj?.filename,
        relativePath: obj?.relative_path,
        pluginRelativePath: obj?.plugin_relative_path
      };
    } catch {
      return { success: task.status === 'completed' };
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
          error: error.message || 'Download failed'
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
        filename: `archive_${Date.now()}.zip`,
        size: Math.floor(Math.random() * 10000000) + 1000000
      };

      callbacks?.onComplete?.(result);
      return result;
    } catch (error: any) {
      const errorMessage = error.message || 'Download failed';
      callbacks?.onError?.(errorMessage);

      return {
        success: false,
        error: errorMessage
      };
    }
  }
}
