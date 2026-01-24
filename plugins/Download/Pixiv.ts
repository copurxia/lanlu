#!/usr/bin/env deno run --allow-net --allow-read --allow-write

import { BasePlugin, PluginInfo, PluginInput, PluginResult } from '../base_plugin.ts';

/**
 * Pixiv 下载插件
 *
 * 支持 URL：
 * - https://www.pixiv.net/artworks/<illustId>
 * - https://www.pixiv.net/en/artworks/<illustId>
 * - https://www.pixiv.net/member_illust.php?illust_id=<illustId>
 *
 * 通过 Pixiv Web Ajax：
 * - /ajax/illust/{id}?lang=en
 * - /ajax/illust/{id}/pages?lang=en
 * - /ajax/illust/{id}/ugoira_meta (ugoira)
 *
 * 下载原图需带 Referer 头（Pixiv 防盗链）。
 */

type LoginCookie = { name: string; value: string; domain?: string; path?: string };

type PixivAjaxEnvelope<T> = { error: boolean; message: string; body: T };

type PixivIllustBody = {
  illustId: string;
  illustTitle: string;
  illustComment: string;
  illustType?: number;
  xRestrict?: number;
  pageCount: number;
  aiType?: number;
  userId: string;
  userName: string;
  userAccount?: string;
  tags?: { tags: Array<{ tag: string; romaji?: string; translation?: Record<string, string> }> };
  urls: { original: string | null; regular?: string | null; small?: string | null };
  createDate?: string;
  uploadDate?: string;
};

type PixivPagesBody = Array<{ urls: { original: string } }>;

type PixivUgoiraBody = {
  originalSrc: string;
  src?: string;
  frames: Array<{ file: string; delay: number }>;
};

class PixivDownloadPlugin extends BasePlugin {
  private static readonly USER_AGENT =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  getPluginInfo(): PluginInfo {
    return {
      name: 'Pixiv Downloader',
      type: 'download',
      namespace: 'pixivdl',
      login_from: 'pixivlogin',
      author: 'lrr4cj',
      version: '1.0',
      description: 'Downloads original images from a Pixiv artwork (illust/manga/ugoira).',
      parameters: [
        { name: 'lang', type: 'string', desc: 'Pixiv ajax lang parameter (e.g. en, ja, zh)', default_value: 'en' },
        { name: 'concurrency', type: 'int', desc: 'Max concurrent downloads for multi-page works', default_value: '4' },
        { name: 'save_meta_json', type: 'bool', desc: 'Write meta.json into the download folder', default_value: '1' },
        { name: 'prefix_id', type: 'bool', desc: 'Prefix folder name with illustId', default_value: '0' },
      ],
      url_regex:
        'https?://(www\\.)?pixiv\\.net/(?:[a-z]{2}/)?artworks/\\d+.*|https?://(www\\.)?pixiv\\.net/member_illust\\.php\\?illust_id=\\d+.*',
      permissions: ['net=www.pixiv.net', 'net=i.pximg.net', 'net=*.pximg.net'],
      update_url: 'https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Download/Pixiv.ts',
    };
  }

  protected async runPlugin(input: PluginInput): Promise<void> {
    try {
      const params = this.getParams();
      const url = (input.url || '').trim();
      if (!url) {
        this.outputResult({ success: false, error: 'No URL provided.' });
        return;
      }

      const illustId = this.extractIllustId(url);
      if (!illustId) {
        this.outputResult({ success: false, error: 'Invalid Pixiv URL. Use https://www.pixiv.net/artworks/<id>' });
        return;
      }

      const lang = String(params.lang || 'en').trim() || 'en';
      const concurrency = this.clampInt(Number(params.concurrency ?? 4), 1, 16);
      const saveMetaJson = !!params.save_meta_json;
      const prefixId = !!params.prefix_id;

      const loginCookies = (input.loginCookies || []) as LoginCookie[];

      const result = await this.downloadIllust(illustId, { lang, concurrency, saveMetaJson, prefixId }, loginCookies);
      this.outputResult(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });
    }
  }

  private async downloadIllust(
    illustId: string,
    opts: { lang: string; concurrency: number; saveMetaJson: boolean; prefixId: boolean },
    loginCookies: LoginCookie[]
  ): Promise<PluginResult> {
    this.reportProgress(5, 'Fetching Pixiv artwork info...');
    const cookieHeader = this.buildCookieHeaderForPixiv(loginCookies);

    const illust = await this.fetchIllust(illustId, opts.lang, cookieHeader);
    if (!illust.success) return illust;
    const body = illust.data as PixivIllustBody;

    const title = (body.illustTitle || '').trim();
    const safeTitle = this.sanitizeFilename(title) || illustId;
    const folderName = (opts.prefixId ? `${illustId} ${safeTitle}` : safeTitle).trim();

    const baseDir = this.input?.pluginDir || './data/cache/plugins/pixivdl';
    const outDir = `${baseDir}/${folderName}`;
    await Deno.mkdir(outDir, { recursive: true });

    // 保存 meta.json（仅用于调试/追溯，不影响系统导入）
    if (opts.saveMetaJson) {
      const meta = {
        source: `https://www.pixiv.net/artworks/${illustId}`,
        illustId,
        illustTitle: body.illustTitle,
        illustComment: body.illustComment,
        userId: body.userId,
        userName: body.userName,
        userAccount: body.userAccount,
        pageCount: body.pageCount,
        xRestrict: body.xRestrict,
        aiType: body.aiType,
        tags: body.tags?.tags || [],
        createDate: body.createDate,
        uploadDate: body.uploadDate,
      };
      await Deno.writeTextFile(`${outDir}/meta.json`, JSON.stringify(meta, null, 2));
    }

    const referer = `https://www.pixiv.net/artworks/${illustId}`;

    // ugoira
    if (body.urls?.original && body.urls.original.includes('ugoira')) {
      this.reportProgress(10, 'Detected ugoira, fetching ugoira meta...');
      const ugo = await this.fetchUgoiraMeta(illustId, cookieHeader);
      if (!ugo.success) return ugo;
      const ugoBody = ugo.data as PixivUgoiraBody;

      const zipUrl = ugoBody.originalSrc || ugoBody.src;
      if (!zipUrl) {
        return { success: false, error: 'Failed to resolve ugoira zip url.' };
      }

      const zipPath = `${outDir}/ugoira.zip`;
      const jsonPath = `${outDir}/ugoira_frames.json`;

      // 保存帧延迟信息
      await Deno.writeTextFile(jsonPath, JSON.stringify({ illustId, frames: ugoBody.frames }, null, 2));

      this.reportProgress(20, 'Downloading ugoira zip...');
      const ok = await this.downloadFile(zipUrl, zipPath, { referer });
      if (!ok) {
        return { success: false, error: 'Failed to download ugoira zip.' };
      }

      this.reportProgress(100, 'Download complete');
      return {
        success: true,
        data: [
          {
            relative_path: `plugins/pixivdl/${folderName}`,
            filename: folderName,
            source: referer,
            downloaded_count: 1,
            failed_count: 0,
          },
        ],
      };
    }

    // illust/manga pages
    const pages = await this.fetchPages(illustId, opts.lang, cookieHeader);
    if (!pages.success) return pages;
    const urls = pages.data as string[];

    const total = urls.length;
    if (total === 0) {
      return { success: false, error: 'No downloadable pages found.' };
    }

    const pad = String(total).length;
    const tasks = urls.map((u, idx) => {
      const ext = this.guessExtFromUrl(u) || 'jpg';
      const name = `${String(idx + 1).padStart(pad, '0')}.${ext}`;
      const path = `${outDir}/${name}`;
      return { url: u, path, idx: idx + 1, total };
    });

    let downloaded = 0;
    let failed = 0;

    this.reportProgress(15, `Downloading ${total} page(s)...`);
    await this.promisePool(tasks, opts.concurrency, async (t) => {
      const progress = 15 + Math.floor(((t.idx - 1) / total) * 80);
      this.reportProgress(progress, `Downloading page ${t.idx}/${total}...`);

      // 断点续传：存在即跳过
      try {
        await Deno.lstat(t.path);
        downloaded++;
        return;
      } catch {
        // continue
      }

      const ok = await this.downloadFile(t.url, t.path, { referer });
      if (ok) downloaded++;
      else failed++;
    });

    this.reportProgress(100, `Download complete: ${downloaded} succeeded, ${failed} failed`);

    if (downloaded === 0) {
      return { success: false, error: 'No files were downloaded.' };
    }

    return {
      success: true,
      data: [
        {
          relative_path: `plugins/pixivdl/${folderName}`,
          filename: folderName,
          source: referer,
          downloaded_count: downloaded,
          failed_count: failed,
        },
      ],
    };
  }

  private extractIllustId(url: string): string | null {
    const clean = url.replace(/^["'\s]+|["'\s]+$/g, '').trim();
    const m1 = clean.match(/pixiv\.net\/(?:[a-z]{2}\/)?artworks\/(\d+)/);
    if (m1) return m1[1];
    const m2 = clean.match(/pixiv\.net\/member_illust\.php\?[^#]*illust_id=(\d+)/);
    if (m2) return m2[1];
    return null;
  }

  private buildCookieHeaderForPixiv(cookies: LoginCookie[]): string {
    // 只透传 pixiv.net 域的 cookie；pximg 下载不需要 cookie（但需要 Referer）。
    return (cookies || [])
      .filter((c) => (c.domain || '').includes('pixiv.net'))
      .map((c) => `${c.name}=${c.value}`)
      .join('; ');
  }

  private async fetchIllust(illustId: string, lang: string, cookieHeader: string): Promise<PluginResult> {
    const url = `https://www.pixiv.net/ajax/illust/${illustId}?lang=${encodeURIComponent(lang)}`;
    const resp = await this.fetchJsonWithRetry<PixivAjaxEnvelope<PixivIllustBody>>(url, {
      cookieHeader,
      referer: `https://www.pixiv.net/artworks/${illustId}`,
    });
    if (!resp.success) return resp;

    const env = resp.data as PixivAjaxEnvelope<PixivIllustBody>;
    if (env.error) return { success: false, error: env.message || 'Pixiv ajax returned error.' };
    if (!env.body) return { success: false, error: 'Pixiv ajax returned empty body.' };

    // 未登录/权限不足时，urls.original 可能为 null（参考 PixivUtil2 逻辑）。
    if (!env.body.urls || env.body.urls.original == null) {
      return {
        success: false,
        error:
          'Pixiv did not provide original image URLs (urls.original is null). This usually means you need to configure Pixiv login cookies (PHPSESSID) or the work is not accessible.',
      };
    }

    return { success: true, data: env.body };
  }

  private async fetchPages(illustId: string, lang: string, cookieHeader: string): Promise<PluginResult> {
    const url = `https://www.pixiv.net/ajax/illust/${illustId}/pages?lang=${encodeURIComponent(lang)}`;
    const resp = await this.fetchJsonWithRetry<PixivAjaxEnvelope<PixivPagesBody>>(url, {
      cookieHeader,
      referer: `https://www.pixiv.net/artworks/${illustId}`,
    });
    if (!resp.success) return resp;

    const env = resp.data as PixivAjaxEnvelope<PixivPagesBody>;
    if (env.error) return { success: false, error: env.message || 'Pixiv pages ajax returned error.' };

    const list = Array.isArray(env.body) ? env.body : [];
    const urls = list.map((p) => p?.urls?.original).filter((u): u is string => typeof u === 'string' && u.length > 0);

    // 兜底：某些情况下 /pages 失败，但 /illust 里仍有 original（单页）。
    if (urls.length === 0) {
      const illust = await this.fetchIllust(illustId, lang, cookieHeader);
      if (illust.success) {
        const body = illust.data as PixivIllustBody;
        if (body?.urls?.original) return { success: true, data: [body.urls.original] };
      }
    }

    return { success: true, data: urls };
  }

  private async fetchUgoiraMeta(illustId: string, cookieHeader: string): Promise<PluginResult> {
    const url = `https://www.pixiv.net/ajax/illust/${illustId}/ugoira_meta`;
    const resp = await this.fetchJsonWithRetry<PixivAjaxEnvelope<PixivUgoiraBody>>(url, {
      cookieHeader,
      referer: `https://www.pixiv.net/artworks/${illustId}`,
    });
    if (!resp.success) return resp;

    const env = resp.data as PixivAjaxEnvelope<PixivUgoiraBody>;
    if (env.error) return { success: false, error: env.message || 'Pixiv ugoira ajax returned error.' };
    return { success: true, data: env.body };
  }

  private async fetchJsonWithRetry<T>(
    url: string,
    opts: { cookieHeader: string; referer: string }
  ): Promise<PluginResult> {
    const maxRetry = 4;
    let lastErr = '';
    for (let i = 0; i <= maxRetry; i++) {
      try {
        const headers: Record<string, string> = {
          'User-Agent': PixivDownloadPlugin.USER_AGENT,
          'Accept': 'application/json, text/plain, */*',
          'Referer': opts.referer,
        };
        if (opts.cookieHeader) headers['Cookie'] = opts.cookieHeader;

        const resp = await fetch(url, { headers });
        const text = await resp.text();

        if (resp.status === 429 || resp.status === 503) {
          lastErr = `HTTP ${resp.status}`;
          await this.sleep(400 * (i + 1));
          continue;
        }
        if (!resp.ok) {
          return { success: false, error: `HTTP ${resp.status}: ${text.slice(0, 200)}` };
        }

        const json = JSON.parse(text) as T;
        return { success: true, data: json };
      } catch (error) {
        lastErr = error instanceof Error ? error.message : String(error);
        await this.sleep(250 * (i + 1));
      }
    }
    return { success: false, error: `Request failed after retries: ${lastErr}` };
  }

  private async downloadFile(url: string, filePath: string, opts: { referer: string }): Promise<boolean> {
    try {
      const headers: Record<string, string> = {
        'User-Agent': PixivDownloadPlugin.USER_AGENT,
        'Accept': '*/*',
        'Referer': opts.referer,
      };

      const resp = await fetch(url, { headers });
      if (!resp.ok || !resp.body) {
        await this.logWarn('download:failed', { url, status: resp.status });
        return false;
      }

      const file = await Deno.open(filePath, { create: true, write: true, truncate: true });
      try {
        const reader = resp.body.getReader();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          if (!value || value.length === 0) continue;
          let offset = 0;
          while (offset < value.length) {
            const n = await file.write(value.subarray(offset));
            if (n <= 0) break;
            offset += n;
          }
        }
      } finally {
        try {
          file.close();
        } catch {
          // ignore
        }
      }

      return true;
    } catch (error) {
      await this.logError('download:error', { url, error: String(error) });
      return false;
    }
  }

  private guessExtFromUrl(url: string): string | null {
    try {
      const u = new URL(url);
      const base = u.pathname.split('/').pop() || '';
      const dot = base.lastIndexOf('.');
      if (dot < 0) return null;
      const ext = base.slice(dot + 1).toLowerCase();
      if (!ext) return null;
      // 只允许常见图片扩展名
      if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'zip'].includes(ext)) return ext === 'jpeg' ? 'jpg' : ext;
      return ext;
    } catch {
      return null;
    }
  }

  private sanitizeFilename(name: string): string {
    return String(name)
      .replace(/[<>:"/\\|?*\[\]「」]/g, '')
      .trim()
      .substring(0, 80);
  }

  private clampInt(n: number, min: number, max: number): number {
    if (!Number.isFinite(n)) return min;
    return Math.max(min, Math.min(max, Math.trunc(n)));
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise((r) => setTimeout(r, ms));
  }

  private async promisePool<T>(items: T[], concurrency: number, worker: (item: T) => Promise<void>): Promise<void> {
    const queue = items.slice();
    const runners: Promise<void>[] = [];

    const runOne = async () => {
      while (queue.length > 0) {
        const item = queue.shift();
        if (item === undefined) return;
        await worker(item);
      }
    };

    for (let i = 0; i < concurrency; i++) {
      runners.push(runOne());
    }

    await Promise.all(runners);
  }
}

if (import.meta.main) {
  const plugin = new PixivDownloadPlugin();
  await plugin.handleCommand();
}
