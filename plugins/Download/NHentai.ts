#!/usr/bin/env deno run --allow-net --allow-read --allow-write

import { BasePlugin, PluginInfo, PluginInput, PluginResult } from '../base_plugin.ts';

/**
 * nhentai 下载插件
 * 下载指定画廊的所有图片到文件夹
 */

interface NHentaiDoujinshi {
  id: number;
  name: string;
  pretty_name: string;
  img_id: string;
  pages: number;
  ext: string[];
}

// URL 常量
const BASE_URL = 'https://nhentai.net';
const DETAIL_URL = `${BASE_URL}/g`;
const IMAGE_URL = 'https://i1.nhentai.net/galleries';
const IMAGE_MIRRORS = ['i2', 'i3', 'i4', 'i5', 'i6', 'i7'];

class NHentaiDownloadPlugin extends BasePlugin {
  private userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  private defaultHeaders: Record<string, string> = {
    'User-Agent': this.userAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Connection': 'keep-alive',
    'Referer': 'https://nhentai.net/'
  };
  private loginCookies: string = '';

  getPluginInfo(): PluginInfo {
    return {
      name: "nhentai Downloader",
      type: "download",
      namespace: "nhentai",
      login_from: "nhlogin",
      author: "Minimax M2.1",
      version: "1.0",
      description: "Downloads all images from an nhentai gallery to a folder",
      parameters: [],
      url_regex: "https?://nhentai\\.net/g/\\d+/?",
      permissions: ["net=nhentai.net", "net=i1.nhentai.net", "net=i2.nhentai.net", "net=i3.nhentai.net", "net=i4.nhentai.net", "net=i5.nhentai.net", "net=i6.nhentai.net", "net=i7.nhentai.net"],
      update_url: "https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Download/NHentai.ts"
    };
  }

  protected async runPlugin(input: PluginInput): Promise<void> {
    try {
      const url = (input.url || '').trim();
      const loginCookies = input.loginCookies || null;

      if (!url) {
        this.outputResult({ success: false, error: 'No URL provided.' });
        return;
      }

      // 初始化 login cookies
      if (loginCookies) {
        this.loginCookies = this.buildCookieString(loginCookies);
      }

      const result = await this.downloadGallery(url);

      this.outputResult(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });
    }
  }

  /**
   * 构建 cookie 字符串
   */
  private buildCookieString(cookies: Array<{ name: string; value: string; domain: string; path: string }>): string {
    return cookies
      .filter(c => c.domain === 'nhentai.net' || c.domain.endsWith('.nhentai.net'))
      .map(c => `${c.name}=${c.value}`)
      .join('; ');
  }

  /**
   * 从 URL 提取画廊 ID
   */
  private extractGalleryId(url: string): number | null {
    const match = url.match(/nhentai\.net\/g\/(\d+)/);
    if (match) {
      return parseInt(match[1], 10);
    }
    return null;
  }

  /**
   * 下载画廊
   */
  private async downloadGallery(url: string): Promise<PluginResult> {
    const galleryId = this.extractGalleryId(url);
    if (!galleryId) {
      return { success: false, error: 'Invalid nhentai URL. Use https://nhentai.net/g/123456/' };
    }

    await this.logInfo('Starting download for gallery', { id: galleryId });

    // 获取画廊页面
    const galleryUrl = `${DETAIL_URL}/${galleryId}/`;
    const response = await this.smartFetch(galleryUrl);

    if (response.status === 404) {
      return { success: false, error: `Gallery not found: ${galleryId}` };
    }

    if (response.status === 403) {
      return { success: false, error: 'Blocked by Cloudflare. Please configure login cookies or use CloudflareBypass.' };
    }

    if (!response.ok) {
      return { success: false, error: `Failed to fetch gallery: status ${response.status}` };
    }

    // 解析画廊信息
    const doujinshi = this.parseGalleryPage(response.text, galleryId);
    if (!doujinshi) {
      return { success: false, error: 'Failed to parse gallery information' };
    }

    await this.logInfo('Parsed gallery', { name: doujinshi.name, pages: doujinshi.pages });

    // 创建下载目录
    const sanitizedName = this.sanitizeFilename(doujinshi.pretty_name || doujinshi.name);
    const folderName = `${doujinshi.id} ${sanitizedName}`;
    const pluginDir = `${this.input?.pluginDir || './data/cache/plugins/nhentai'}/${folderName}`;
    await Deno.mkdir(pluginDir, { recursive: true });

    // 下载所有图片
    let downloadedCount = 0;
    let failedCount = 0;

    for (let i = 1; i <= doujinshi.pages; i++) {
      const ext = doujinshi.ext[i - 1] || 'jpg';
      const fileName = `${i}.${ext}`;
      const filePath = `${pluginDir}/${fileName}`;

      // 输出当前下载进度
      const progress = Math.round(((i - 1) / doujinshi.pages) * 100);
      this.reportProgress(progress, `Downloading page ${i}/${doujinshi.pages}...`);

      // 检查文件是否已存在（断点续传）
      try {
        await Deno.lstat(filePath);
        await this.logDebug('File already exists, skipping', { filePath });
        downloadedCount++;
        continue;
      } catch {
        // 文件不存在，继续下载
      }

      const success = await this.downloadImageWithMirrors(doujinshi.img_id, i, ext, filePath);
      if (success) {
        downloadedCount++;
      } else {
        failedCount++;
        await this.logWarn('Failed to download image', { page: i });
      }
    }

    // 输出完成进度
    this.reportProgress(100, `Download complete: ${downloadedCount} succeeded, ${failedCount} failed`);

    if (downloadedCount === 0) {
      return { success: false, error: `No images were downloaded for gallery: ${galleryId}` };
    }

    return {
      success: true,
      data: [{
        relative_path: `plugins/nhentai/${folderName}`,
        filename: folderName,
        source: `https://nhentai.net/g/${galleryId}/`,
        downloaded_count: downloadedCount,
        failed_count: failedCount
      }]
    };
  }

  /**
   * 扩展名映射表
   */
  private static readonly EXT_MAP: Record<string, string> = {
    'j': 'jpg',
    'p': 'png',
    'g': 'gif',
    'w': 'webp'
  };

  /**
   * 解析画廊页面 HTML - 使用内嵌的 JSON 数据
   */
  private parseGalleryPage(html: string, galleryId: number): NHentaiDoujinshi | null {
    try {
      // 从页面中提取 window._gallery = JSON.parse("...") 的 JSON 数据
      const jsonMatch = html.match(/window\._gallery\s*=\s*JSON\.parse\s*\(\s*"(.+?)"\s*\)\s*;/);

      if (jsonMatch) {
        // 解析嵌套的 JSON 字符串（需要先解码转义字符）
        const jsonString = jsonMatch[1]
          .replace(/\\u0022/g, '"')
          .replace(/\\u002F/g, '/')
          .replace(/\\\\/g, '\\');

        const gallery = JSON.parse(jsonString);

        // 从 JSON 提取信息
        const mediaId = gallery.media_id as string;
        const title = gallery.title as { english?: string; japanese?: string; pretty?: string };
        const images = gallery.images as { pages: Array<{ t: string; w: number; h: number }> };
        const numPages = gallery.num_pages as number;

        // 转换扩展名
        const ext = images.pages.map(page => NHentaiDownloadPlugin.EXT_MAP[page.t] || 'jpg');

        return {
          id: galleryId,
          name: title.english || title.japanese || `Gallery ${galleryId}`,
          pretty_name: title.pretty || title.english || `Gallery ${galleryId}`,
          img_id: mediaId,
          pages: numPages,
          ext
        };
      }

      // 备用方案：从 HTML 解析
      return this.parseGalleryPageFromHtml(html, galleryId);
    } catch (error) {
      // 如果 JSON 解析失败，尝试 HTML 解析
      return this.parseGalleryPageFromHtml(html, galleryId);
    }
  }

  /**
   * 备用解析方法：从 HTML 提取信息
   */
  private parseGalleryPageFromHtml(html: string, galleryId: number): NHentaiDoujinshi | null {
    try {
      // 提取标题
      const titleMatch = html.match(/<h1[^>]*class="title"[^>]*>.*?<span class="pretty">([^<]+)<\/span>/s);
      const prettyName = titleMatch ? this.decodeHtmlEntities(titleMatch[1].trim()) : '';

      const fullTitleMatch = html.match(/<h1[^>]*class="title"[^>]*>(.*?)<\/h1>/s);
      let name = prettyName;
      if (fullTitleMatch) {
        const fullTitle = fullTitleMatch[1].replace(/<[^>]+>/g, '').trim();
        name = fullTitle || prettyName;
      }

      // 提取 img_id（从封面图片 URL）
      let imgId: string | null = null;
      const coverMatch = html.match(/\/galleries\/(\d+)\/cover\./);
      if (coverMatch) {
        imgId = coverMatch[1];
      }

      if (!imgId) {
        return null;
      }

      // 提取页数
      const pagesMatch = html.match(/Pages:\s*<\/span>\s*<span[^>]*>(\d+)<\/span>/s);
      const pages = pagesMatch ? parseInt(pagesMatch[1], 10) : 0;

      if (pages === 0) {
        return null;
      }

      // 提取每页扩展名（从缩略图 URL）
      const ext: string[] = [];
      const thumbRegex = /\/galleries\/\d+\/(\d+)t\.(\w+)/g;
      let thumbMatch;
      while ((thumbMatch = thumbRegex.exec(html)) !== null) {
        ext.push(thumbMatch[2]);
      }

      // 如果没有找到缩略图扩展名，默认使用 jpg
      if (ext.length === 0) {
        for (let i = 0; i < pages; i++) {
          ext.push('jpg');
        }
      }

      // 补齐缺少的扩展名
      while (ext.length < pages) {
        ext.push(ext[ext.length - 1] || 'jpg');
      }

      return {
        id: galleryId,
        name: name || `Gallery ${galleryId}`,
        pretty_name: prettyName || name || `Gallery ${galleryId}`,
        img_id: imgId,
        pages,
        ext
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * 解码 HTML 实体（支持十进制和十六进制）
   */
  private decodeHtmlEntities(text: string): string {
    return text
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      // 十进制 HTML 实体（如 &#1234;）
      .replace(/&#(\d+);/g, (_, num) => String.fromCharCode(parseInt(num, 10)))
      // 十六进制 HTML 实体（如 &#x4F60; 或 &#X4F60;）
      .replace(/&#x([0-9A-Fa-f]+);/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
  }

  /**
   * 安全化文件名（保留中文字符，只替换不安全字符）
   */
  private sanitizeFilename(name: string): string {
    return name
      // 解码URL编码序列（u前缀格式，如 u97e9）
      .split(/([uU][0-9a-fA-F]{4}|[0-9a-fA-F]{4})/)
      .map(part => {
        // 处理 u 前缀的格式（如 u97e9）
        if (part.match(/^[uU][0-9a-fA-F]{4}$/)) {
          const hex = part.substring(1);
          return String.fromCharCode(parseInt(hex, 16));
        }
        // 处理纯4位十六进制数字（如 4e61）
        else if (part.match(/^[0-9a-fA-F]{4}$/)) {
          return String.fromCharCode(parseInt(part, 16));
        }
        return part;
      })
      .join('')
      // 替换不安全字符（包括Windows保留字符、控制字符和全角括号）
      .replace(/[<>:"/\\|?*\[\]「」]/g, '')
      // 去除首尾空格
      .trim()
      // 截断到合理长度（留出ID和分隔符的空间）
      .substring(0, 80);
  }

  /**
   * 下载图片（带镜像切换）
   */
  private async downloadImageWithMirrors(imgId: string, page: number, ext: string, filePath: string): Promise<boolean> {
    // 先尝试主服务器
    const primaryUrl = `${IMAGE_URL}/${imgId}/${page}.${ext}`;
    if (await this.downloadImage(primaryUrl, filePath)) {
      return true;
    }

    // 尝试镜像服务器
    for (const mirror of IMAGE_MIRRORS) {
      const mirrorUrl = `https://${mirror}.nhentai.net/galleries/${imgId}/${page}.${ext}`;
      if (await this.downloadImage(mirrorUrl, filePath)) {
        return true;
      }
    }

    return false;
  }

  /**
   * 下载单个图片
   */
  private async downloadImage(url: string, filePath: string): Promise<boolean> {
    try {
      const headers: Record<string, string> = {
        ...this.defaultHeaders,
        'Accept': 'image/*,*/*'
      };

      if (this.loginCookies) {
        headers['Cookie'] = this.loginCookies;
      }

      const response = await fetch(url, { headers });

      if (!response.ok) {
        return false;
      }

      const arrayBuffer = await response.arrayBuffer();
      await Deno.writeFile(filePath, new Uint8Array(arrayBuffer));

      await this.logDebug('Downloaded image', { filePath });
      return true;
    } catch (error) {
      await this.logError('Error downloading image', { url, error: String(error) });
      return false;
    }
  }

  /**
   * 发送 HTTP 请求
   */
  private async smartFetch(url: string): Promise<{ ok: boolean; status: number; text: string }> {
    try {
      const headers: Record<string, string> = { ...this.defaultHeaders };
      if (this.loginCookies) {
        headers['Cookie'] = this.loginCookies;
      }

      const response = await fetch(url, { headers });
      const text = await response.text();
      return { ok: response.ok, status: response.status, text };
    } catch (error) {
      return { ok: false, status: 0, text: String(error) };
    }
  }
}

// 运行插件
if (import.meta.main) {
  const plugin = new NHentaiDownloadPlugin();
  await plugin.handleCommand();
}
