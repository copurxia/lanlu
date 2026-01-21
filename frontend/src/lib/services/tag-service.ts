'use client';

import { apiClient, uploadClient } from '../api';

export type TagTranslation = {
  text: string;
  intro: string;
};

export type Tag = {
  id: number;
  namespace: string;
  name: string;
  translations: Record<string, TagTranslation>;
  links: string;
  iconAssetId?: number;
  backgroundAssetId?: number;
  created_at?: string;
  updated_at?: string;
};

export class TagService {
  /**
   * 获取标签翻译映射（用于前端展示）
   * @param lang 语言代码 (zh, en)
   * @param arcid 可选：档案ID，只返回该档案相关的翻译
   * @param tankoubon_id 可选：合集ID，只返回该合集相关的翻译（合集自身标签 + 所有归档标签）
   */
  static async getTranslations(lang: string, arcid?: string, tankoubon_id?: string): Promise<Record<string, string>> {
    const params: { lang: string; arcid?: string; tankoubon_id?: string } = { lang };
    if (arcid) {
      params.arcid = arcid;
    }
    if (tankoubon_id) {
      params.tankoubon_id = tankoubon_id;
    }
    const resp = await apiClient.get('/api/tags/translations', { params });
    const data = resp.data?.data;
    return (data?.map ?? {}) as Record<string, string>;
  }

  /**
   * 获取标签列表（支持分页和搜索）
   */
  static async list(params: {
    namespace?: string;
    q?: string;
    limit?: number;
    offset?: number;
  }): Promise<{ items: Tag[]; total: number; limit: number; offset: number }> {
    const q = params.q ?? '';
    const limit = params.limit ?? 100;
    const offset = params.offset ?? 0;
    const namespace = params.namespace ?? '';

    const queryParams = new URLSearchParams();
    if (q) queryParams.set('q', q);
    queryParams.set('limit', String(limit));
    queryParams.set('offset', String(offset));
    if (namespace) queryParams.set('namespace', namespace);

    const url = `/api/tags?${queryParams.toString()}`;
    const resp = await apiClient.get(url);
    const data = resp.data?.data;
    return {
      items: (data?.items ?? []) as Tag[],
      total: Number(data?.total ?? 0),
      limit: Number(data?.limit ?? limit),
      offset: Number(data?.offset ?? offset),
    };
  }

  /**
   * 获取单个标签详情
   */
  static async getById(id: number): Promise<Tag | null> {
    const resp = await apiClient.get(`/api/tags/${id}`);
    const data = resp.data?.data;
    return data as Tag | null;
  }

  static async getByName(tag: string): Promise<Tag | null> {
    const resp = await apiClient.get('/api/tags/by-name', { params: { tag } });
    const data = resp.data?.data;
    return data as Tag | null;
  }

  /**
   * 获取所有命名空间
   */
  static async listNamespaces(): Promise<string[]> {
    const resp = await apiClient.get('/api/tags/namespaces');
    const data = resp.data?.data;
    return (data?.namespaces ?? []) as string[];
  }

  /**
   * 自动补全搜索标签
   * @param q 搜索词
   * @param lang 语言代码
   * @param limit 返回数量限制
   */
  static async autocomplete(q: string, lang: string, limit: number = 10): Promise<{ value: string; label: string; display: string }[]> {
    if (!q) return [];
    const resp = await apiClient.get('/api/tags/autocomplete', {
      params: { q, lang, limit }
    });
    const data = resp.data?.data;
    return (data?.suggestions ?? []) as { value: string; label: string; display: string }[];
  }

  /**
   * 标签词云（按使用次数）
   */
  static async getCloud(params: { lang: string; limit?: number }): Promise<{ items: { tag: string; display: string; count: number }[]; total: number }> {
    const resp = await apiClient.get('/api/tags/cloud', {
      params: {
        lang: params.lang,
        limit: params.limit ?? 200,
      },
    });
    const data = resp.data?.data;
    return {
      items: (data?.items ?? []) as { tag: string; display: string; count: number }[],
      total: Number(data?.total ?? 0),
    };
  }

  /**
   * 获取所有标签名（用于自动补全）
   */
  static async adminListTagNames(): Promise<string[]> {
    const resp = await apiClient.get('/api/admin/tags/names');
    const data = resp.data?.data;
    return (data?.tags ?? []) as string[];
  }

  /**
   * 创建标签
   */
  static async adminCreate(tag: Partial<Tag>): Promise<{ id: number }> {
    const resp = await apiClient.post('/api/admin/tags', tag);
    const data = resp.data?.data;
    return { id: Number(data?.id ?? 0) };
  }

  /**
   * 更新标签
   */
  static async adminUpdate(id: number, updates: { translations?: Record<string, TagTranslation>; links?: string }): Promise<void> {
    await apiClient.put(`/api/admin/tags/${id}`, updates);
  }

  static async adminUploadIcon(id: number, file: File): Promise<{ iconAssetId: number }> {
    const body = await file.arrayBuffer();
    const resp = await apiClient.put(`/api/admin/tags/${id}/icon`, body, {
      headers: {
        'Content-Type': file.type || 'application/octet-stream',
        'X-Filename': file.name || 'tag_icon',
      },
    });
    const data = resp.data?.data;
    return { iconAssetId: Number(data?.iconAssetId ?? 0) };
  }

  static async adminUploadBackground(id: number, file: File): Promise<{ backgroundAssetId: number }> {
    const body = await file.arrayBuffer();
    const resp = await apiClient.put(`/api/admin/tags/${id}/background`, body, {
      headers: {
        'Content-Type': file.type || 'application/octet-stream',
        'X-Filename': file.name || 'tag_background',
      },
    });
    const data = resp.data?.data;
    return { backgroundAssetId: Number(data?.backgroundAssetId ?? 0) };
  }

  /**
   * 删除标签
   */
  static async adminDelete(id: number): Promise<void> {
    await apiClient.delete(`/api/admin/tags/${id}`);
  }

  /**
   * 导出标签
   */
  static async adminExport(): Promise<{ generated_at: string; tags: Tag[] }> {
    const resp = await apiClient.get('/api/admin/tags/export');
    return resp.data?.data as { generated_at: string; tags: Tag[] };
  }

  /**
   * 初始化导入任务
   */
  static async adminImportInit(): Promise<{ job: number; chunk_size: number }> {
    const resp = await apiClient.post('/api/admin/tags/import/init');
    const data = resp.data?.data;
    return {
      job: Number(data?.job ?? 0),
      chunk_size: Number(data?.chunk_size ?? 1536 * 1024)
    };
  }

  /**
   * 上传导入文件（支持分片）
   */
  static async adminImportUpload(job: number, file: File, chunkSize: number): Promise<{ job: number }> {
    const totalChunks = Math.ceil(file.size / chunkSize);

    if (totalChunks === 1) {
      await uploadClient.put(
        `/api/admin/tags/import/chunk?job=${encodeURIComponent(String(job))}&chunkIndex=0&totalChunks=1`,
        file,
        { headers: { 'Content-Type': 'application/octet-stream' } }
      );
    } else {
      for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
        const start = chunkIndex * chunkSize;
        const end = Math.min(start + chunkSize, file.size);
        const chunk = file.slice(start, end);

        await uploadClient.put(
          `/api/admin/tags/import/chunk?job=${encodeURIComponent(String(job))}&chunkIndex=${chunkIndex}&totalChunks=${totalChunks}`,
          chunk,
          { headers: { 'Content-Type': 'application/octet-stream' } }
        );
      }
    }

    const resp = await apiClient.post(
      `/api/admin/tags/import/complete?job=${encodeURIComponent(String(job))}&totalChunks=${totalChunks}`
    );
    const data = resp.data?.data;
    return { job: Number(data?.job ?? 0) };
  }
}

// 为了向后兼容，保留旧的类名
export const TagI18nService = TagService;
