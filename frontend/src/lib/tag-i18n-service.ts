'use client';

import { apiClient, uploadClient } from './api';

export type TagI18nEntry = {
  tag: string;
  lang: string;
  text: string;
  updated_at?: string;
};

export class TagI18nService {
  static async getMap(lang: string, arcid?: string): Promise<Record<string, string>> {
    const params: { lang: string; arcid?: string } = { lang };
    if (arcid) {
      params.arcid = arcid;
    }
    const resp = await apiClient.get('/api/tags/i18n', { params });
    // ResponseView.successJson: { code, message, data }
    const data = resp.data?.data;
    return (data?.map ?? {}) as Record<string, string>;
  }

  static async adminList(q?: string): Promise<TagI18nEntry[]> {
    const resp = await apiClient.get('/api/admin/tag_i18n', { params: { q: q ?? '' } });
    const data = resp.data?.data;
    return (data?.items ?? []) as TagI18nEntry[];
  }

  static async adminListTags(): Promise<string[]> {
    const resp = await apiClient.get('/api/admin/tag_i18n/tags');
    const data = resp.data?.data;
    return (data?.tags ?? []) as string[];
  }

  static async adminListMerged(params: {
    q?: string;
    limit?: number;
    offset?: number;
  }): Promise<{ items: { tag: string; zh: string; en: string; zh_intro: string; en_intro: string; zh_links: string; en_links: string }[]; total: number; limit: number; offset: number }> {
    // 显式拼接 querystring，便于在 Network 面板里直接看到 q/limit/offset
    const q = params.q ?? '';
    const limit = params.limit ?? 100;
    const offset = params.offset ?? 0;
    const url = `/api/admin/tag_i18n/merged?q=${encodeURIComponent(q)}&limit=${encodeURIComponent(String(limit))}&offset=${encodeURIComponent(String(offset))}`;
    const resp = await apiClient.get(url);
    const data = resp.data?.data;
    return {
      items: (data?.items ?? []) as { tag: string; zh: string; en: string; zh_intro: string; en_intro: string; zh_links: string; en_links: string }[],
      total: Number(data?.total ?? 0),
      limit: Number(data?.limit ?? limit),
      offset: Number(data?.offset ?? offset),
    };
  }

  static async adminUpsert(entry: TagI18nEntry): Promise<void> {
    await apiClient.put('/api/admin/tag_i18n', entry);
  }

  static async adminDelete(tag: string, lang: string): Promise<void> {
    await apiClient.delete('/api/admin/tag_i18n', { params: { tag, lang } });
  }

  static async adminExport(): Promise<{ generated_at: string; entries: TagI18nEntry[] }> {
    const resp = await apiClient.get('/api/admin/tag_i18n/export');
    return resp.data?.data as { generated_at: string; entries: TagI18nEntry[] };
  }

  static async adminImportInit(): Promise<{ job: number; chunk_size: number }> {
    const resp = await apiClient.post('/api/admin/tag_i18n/import/init');
    const data = resp.data?.data;
    return {
      job: Number(data?.job ?? 0),
      chunk_size: Number(data?.chunk_size ?? 1536 * 1024)
    };
  }

  static async adminImportUpload(job: number, file: File, chunkSize: number): Promise<{ job: number }> {
    const totalChunks = Math.ceil(file.size / chunkSize);

    if (totalChunks === 1) {
      // 小文件直接上传
      await uploadClient.put(
        `/api/admin/tag_i18n/import/chunk?job=${encodeURIComponent(String(job))}&chunkIndex=0&totalChunks=1`,
        file,
        { headers: { 'Content-Type': 'application/octet-stream' } }
      );
    } else {
      // 大文件分片上传
      for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
        const start = chunkIndex * chunkSize;
        const end = Math.min(start + chunkSize, file.size);
        const chunk = file.slice(start, end);

        await uploadClient.put(
          `/api/admin/tag_i18n/import/chunk?job=${encodeURIComponent(String(job))}&chunkIndex=${chunkIndex}&totalChunks=${totalChunks}`,
          chunk,
          { headers: { 'Content-Type': 'application/octet-stream' } }
        );
      }
    }

    // 通知服务器合并分片
    const resp = await apiClient.post(
      `/api/admin/tag_i18n/import/complete?job=${encodeURIComponent(String(job))}&totalChunks=${totalChunks}`
    );
    const data = resp.data?.data;
    return { job: Number(data?.job ?? 0) };
  }
}
