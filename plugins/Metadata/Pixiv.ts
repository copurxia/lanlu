#!/usr/bin/env deno run --allow-net --allow-read

import { BasePlugin, PluginInfo, PluginInput, PluginResult } from '../base_plugin.ts';

/**
 * Pixiv 元数据插件
 *
 * 通过 Pixiv Web Ajax 获取作品信息并输出 LANraragi 风格的 tags/title/summary。
 * - oneshotParam 支持 Pixiv artworks URL 或 illustId
 * - 若未提供 oneshotParam，则尝试从 existingTags 中的 source:pixiv URL 提取 illustId
 */

type LoginCookie = { name: string; value: string; domain?: string; path?: string };
type PixivAjaxEnvelope<T> = { error: boolean; message: string; body: T };

type PixivIllustBody = {
  illustId: string;
  illustTitle: string;
  illustComment: string;
  xRestrict?: number;
  aiType?: number;
  pageCount: number;
  userId: string;
  userName: string;
  userAccount?: string;
  tags?: { tags: Array<{ tag: string; translation?: Record<string, string> }> };
  urls: { original: string | null };
};

class PixivMetadataPlugin extends BasePlugin {
  private static readonly USER_AGENT =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  getPluginInfo(): PluginInfo {
    return {
      name: 'Pixiv',
      type: 'metadata',
      namespace: 'pixivmeta',
      login_from: 'pixivlogin',
      author: 'lrr4cj',
      version: '1.0',
      description: 'Fetches metadata (title/tags/summary) from Pixiv artwork via web ajax.',
      parameters: [
        { name: 'lang', type: 'string', desc: 'Pixiv ajax lang parameter (e.g. en, ja, zh)', default_value: 'en' },
        { name: 'merge_existing', type: 'bool', desc: 'Merge new tags with existing archive tags', default_value: '1' },
        { name: 'prefix_id', type: 'bool', desc: 'Prefix title with illustId', default_value: '0' },
        { name: 'strip_html', type: 'bool', desc: 'Strip HTML tags from Pixiv caption', default_value: '1' },
        { name: 'include_translations', type: 'bool', desc: 'Also add translated tag names when available', default_value: '0' },
      ],
      oneshot_arg: 'Pixiv artwork URL or illustId (e.g. https://www.pixiv.net/artworks/12345678)',
      cooldown: 1,
      permissions: ['net=www.pixiv.net'],
      update_url: 'https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Metadata/Pixiv.ts',
    };
  }

  protected async runPlugin(input: PluginInput): Promise<void> {
    try {
      this.reportProgress(5, '初始化 Pixiv 元数据抓取...');
      const params = this.getParams();

      const lang = String(params.lang || 'en').trim() || 'en';
      const mergeExisting = !!params.merge_existing;
      const prefixId = !!params.prefix_id;
      const stripHtml = !!params.strip_html;
      const includeTranslations = !!params.include_translations;

      const illustId =
        this.extractIllustId(String(input.oneshotParam || '').trim()) ||
        this.extractIllustIdFromSourceTag(String(input.existingTags || '')) ||
        this.extractIllustIdFromTitle(String(input.archiveTitle || ''));

      if (!illustId) {
        this.outputResult({
          success: false,
          error: 'No Pixiv illustId found. Provide oneshotParam as Pixiv URL/ID, or add a source:https://www.pixiv.net/artworks/<id> tag.',
        });
        return;
      }

      const cookieHeader = this.buildCookieHeaderForPixiv((input.loginCookies || []) as LoginCookie[]);
      const illust = await this.fetchIllust(illustId, lang, cookieHeader);
      if (!illust.success) {
        this.outputResult(illust);
        return;
      }

      const body = illust.data as PixivIllustBody;
      const rawTitle = (body.illustTitle || '').trim();
      const title = prefixId ? `${illustId} ${rawTitle}`.trim() : (rawTitle || illustId);
      const summary = stripHtml ? this.stripHtml(body.illustComment || '') : (body.illustComment || '');

      const tags = this.buildTags(body, { lang, includeTranslations });
      const merged = mergeExisting ? this.mergeTags(String(input.existingTags || ''), tags) : tags;

      this.reportProgress(100, '元数据获取完成');
      this.outputResult({
        success: true,
        data: {
          title,
          summary,
          tags: merged,
        },
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });
    }
  }

  private extractIllustId(input: string): string | null {
    const clean = input.replace(/^["'\s]+|["'\s]+$/g, '').trim();
    if (!clean) return null;
    if (/^\d+$/.test(clean)) return clean;
    const m1 = clean.match(/pixiv\.net\/(?:[a-z]{2}\/)?artworks\/(\d+)/);
    if (m1) return m1[1];
    const m2 = clean.match(/pixiv\.net\/member_illust\.php\?[^#]*illust_id=(\d+)/);
    if (m2) return m2[1];
    return null;
  }

  private extractIllustIdFromSourceTag(existingTags: string): string | null {
    // source:https://www.pixiv.net/artworks/123
    const m = existingTags.match(/source:\s*(https?:\/\/(?:www\.)?pixiv\.net\/(?:[a-z]{2}\/)?artworks\/(\d+))/i);
    if (m) return m[2];
    const m2 = existingTags.match(/source:\s*pixiv:(\d+)/i);
    if (m2) return m2[1];
    return null;
  }

  private extractIllustIdFromTitle(title: string): string | null {
    // 轻量兜底：标题里包含 pixiv + 数字（避免把随机数字当成 pixiv id）
    const m = title.match(/pixiv[^0-9]{0,10}(\d{6,})/i);
    return m ? m[1] : null;
  }

  private buildCookieHeaderForPixiv(cookies: LoginCookie[]): string {
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
          'User-Agent': PixivMetadataPlugin.USER_AGENT,
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
        return { success: true, data: JSON.parse(text) as T };
      } catch (error) {
        lastErr = error instanceof Error ? error.message : String(error);
        await this.sleep(250 * (i + 1));
      }
    }
    return { success: false, error: `Request failed after retries: ${lastErr}` };
  }

  private buildTags(body: PixivIllustBody, opts: { lang: string; includeTranslations: boolean }): string {
    const out: string[] = [];

    out.push(`source:https://www.pixiv.net/artworks/${body.illustId}`);
    out.push(`pixiv:${body.illustId}`);
    out.push(`pixiv_user:${body.userId}`);
    if (body.userName) out.push(`artist:${body.userName}`);
    if (body.userAccount) out.push(`pixiv_user_account:${body.userAccount}`);

    const xr = body.xRestrict ?? 0;
    if (xr === 1) out.push('rating:R-18');
    else if (xr === 2) out.push('rating:R-18G');

    if (body.aiType === 2) out.push('ai:generated');

    const tags = body.tags?.tags || [];
    for (const t of tags) {
      const name = String(t.tag || '').trim();
      if (name) out.push(`pixiv_tag:${name}`);

      if (opts.includeTranslations && t.translation) {
        const trans = t.translation[opts.lang] || t.translation.en;
        if (trans && trans.trim() && trans.trim() !== name) {
          out.push(`pixiv_tag:${trans.trim()}`);
        }
      }
    }

    // 去重但保序
    const seen = new Set<string>();
    const deduped: string[] = [];
    for (const t of out) {
      const k = t.trim();
      if (!k) continue;
      if (seen.has(k)) continue;
      seen.add(k);
      deduped.push(k);
    }

    return deduped.join(', ');
  }

  private mergeTags(existing: string, additions: string): string {
    const list = (s: string) =>
      s
        .split(',')
        .map((t) => t.trim())
        .filter((t) => t.length > 0);

    const out: string[] = [];
    const seen = new Set<string>();

    for (const t of [...list(existing), ...list(additions)]) {
      if (seen.has(t)) continue;
      seen.add(t);
      out.push(t);
    }

    return out.join(', ');
  }

  private stripHtml(html: string): string {
    // Pixiv comment 通常为 HTML；简单移除标签并解码常见实体
    const noTags = html.replace(/<br\s*\/?\s*>/gi, '\n').replace(/<[^>]+>/g, '');
    return noTags
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .trim();
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise((r) => setTimeout(r, ms));
  }
}

if (import.meta.main) {
  const plugin = new PixivMetadataPlugin();
  await plugin.handleCommand();
}
