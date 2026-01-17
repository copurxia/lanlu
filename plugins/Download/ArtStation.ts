#!/usr/bin/env deno run --allow-net --allow-read --allow-write

import { BasePlugin, PluginInfo, PluginInput, PluginResult } from '../base_plugin.ts';

/**
 * ArtStation下载插件
 * 下载指定用户的所有作品图片到文件夹
 */

interface ArtStationAsset {
  asset_type: string;
  has_image: boolean;
  image_url: string;
  has_embedded_player?: boolean;
  player_embedded?: string;
}

interface ArtStationProject {
  hash_id: string;
  slug: string;
  title: string;
  assets: ArtStationAsset[];
  user: {
    username: string;
  };
}

class ArtStationDownloadPlugin extends BasePlugin {
  private userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/113.0';
  private defaultHeaders: Record<string, string> = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/113.0',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Connection': 'keep-alive',
  };
  private bypassUrl: string = '';

  getPluginInfo(): PluginInfo {
    return {
      name: "ArtStation Downloader",
      type: "download",
      icon: "data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='35' height='32' fill='none' viewBox='0 0 35 32'%3E%3Cpath fill='%2313AFF0' fill-rule='evenodd' d='M35 24.354c0-.704-.208-1.36-.565-1.91L22.937 2.525A3.54 3.54 0 0 0 19.813.652h-6.077l17.76 30.666 2.8-4.833c.553-.925.704-1.334.704-2.131m-35-.037 2.956 5.093h.001a3.54 3.54 0 0 0 3.157 1.938h19.624l-4.072-7.03zM10.832 5.621l7.938 13.701H2.893z' clip-rule='evenodd'/%3E%3C/svg%3E",
      namespace: "artstation",
      author: "MiniMax M2.1",
      version: "1.0",
      description: "Downloads all artwork images from an ArtStation user profile to a folder",
      parameters: [
        { name: "quality", type: "string", desc: "Image quality: 4k or large", default_value: "4k" },
        { name: "bypass_url", type: "string", desc: "CloudflareBypass URL (e.g. http://localhost:8089)", default_value: "" }
      ],
      url_regex: "https?://(www\\.artstation\\.com/[^/]+|[^/]+\\.artstation\\.com)/?.*",
      permissions: ["net"],  // Allow all network for FlareSolverr support
      update_url: "https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Download/ArtStation.ts"
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

      const result = await this.downloadUserArtworks(url, {
        quality: (params.quality as string) || '4k',
        bypassUrl: (params.bypass_url as string) || ''
      });

      this.outputResult(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });
    }
  }

  /**
   * 从URL提取用户名
   */
  private extractUsername(url: string): string | null {
    // 清理 URL
    const cleanUrl = url.replace(/^["'\s]+|["'\s]+$/g, '').trim();

    // Format 1: https://www.artstation.com/username
    const match1 = cleanUrl.match(/https?:\/\/(?:www\.)?artstation\.com\/([^\/\?#"'\s]+)/);
    if (match1 && match1[1] !== 'artwork' && match1[1] !== 'projects') {
      return match1[1];
    }

    // Format 2: https://username.artstation.com
    const match2 = cleanUrl.match(/https?:\/\/([^\.]+)\.artstation\.com/);
    if (match2 && match2[1] !== 'www') {
      return match2[1];
    }

    return null;
  }

  /**
   * 下载用户的所有作品
   */
  private async downloadUserArtworks(url: string, params: { quality: string; bypassUrl: string }): Promise<PluginResult> {
    const username = this.extractUsername(url);
    if (!username) {
      return { success: false, error: 'Invalid ArtStation URL. Use https://www.artstation.com/username or https://username.artstation.com' };
    }

    // 初始化 CloudflareBypass
    if (params.bypassUrl) {
      this.bypassUrl = params.bypassUrl.replace(/\/$/, '');
      await this.logInfo('Using CloudflareBypass', { url: this.bypassUrl });
    }

    await this.logInfo('Starting download for user', { username });

    // 获取所有项目
    const projects = await this.getAllProjects(username);
    if (!projects.success) {
      return projects;
    }

    const projectHashIds = projects.data.hashIds as string[];
    if (projectHashIds.length === 0) {
      return { success: false, error: `No artworks found for user: ${username}` };
    }

    await this.logInfo('Found projects', { count: projectHashIds.length });

    // 创建下载目录
    const pluginDir = `${this.input?.pluginDir || './data/cache/plugins/artstation'}/${username}`;
    await Deno.mkdir(pluginDir, { recursive: true });

    // 下载所有项目的图片
    let downloadedCount = 0;
    let failedCount = 0;

    for (let i = 0; i < projectHashIds.length; i++) {
      const hashId = projectHashIds[i];

      // 输出当前下载进度
      const progress = Math.round((i / projectHashIds.length) * 100);
      this.reportProgress(progress, `Downloading project ${i + 1}/${projectHashIds.length}...`);

      try {
        const projectResult = await this.downloadProject(hashId, pluginDir, params.quality);
        if (projectResult.success) {
          downloadedCount += projectResult.data.count as number;
        } else {
          failedCount++;
          await this.logWarn('Failed to download project', { hashId, error: projectResult.error });
        }
      } catch (error) {
        failedCount++;
        await this.logError('Error downloading project', { hashId, error: String(error) });
      }
    }

    // 输出完成进度
    this.reportProgress(100, `Download complete: ${downloadedCount} succeeded, ${failedCount} failed`);

    if (downloadedCount === 0) {
      return { success: false, error: `No images were downloaded for user: ${username}` };
    }

    return {
      success: true,
      data: [{
        relative_path: `plugins/artstation/${username}`,
        filename: username,
        source: `https://www.artstation.com/${username}`,
        downloaded_count: downloadedCount,
        failed_count: failedCount
      }]
    };
  }

  /**
   * 从RSS获取用户的所有项目
   */
  private async getAllProjects(username: string): Promise<PluginResult> {
    const hashIds: string[] = [];
    let page = 0;

    while (true) {
      page++;
      const rssUrl = `https://${username}.artstation.com/rss?page=${page}`;

      try {
        const response = await this.smartFetch(rssUrl, { accept: 'application/rss+xml, application/xml, text/xml, */*' });

        if (response.status === 404) {
          if (page === 1) {
            return { success: false, error: `User not found: ${username}` };
          }
          break;
        }

        if (response.status === 403) {
          return { success: false, error: 'Blocked by ArtStation. Please try again later or use CloudflareBypass.' };
        }

        if (!response.ok) {
          if (page === 1) {
            const errorMsg = response.text || `status ${response.status}`;
            return { success: false, error: `Failed to fetch RSS: ${errorMsg}` };
          }
          break;
        }

        const rssText = response.text;
        const links = this.parseRssLinks(rssText);

        if (links.length === 0) {
          break;
        }

        // 提取artwork hash IDs
        for (const link of links) {
          const match = link.match(/artstation\.com\/artwork\/([a-zA-Z0-9]+)/);
          if (match) {
            hashIds.push(match[1]);
          }
        }

        await this.logInfo('Fetched RSS page', { page, linksFound: links.length });

      } catch (error) {
        if (page === 1) {
          return { success: false, error: `Network error fetching RSS: ${String(error)}` };
        }
        break;
      }
    }

    return { success: true, data: { hashIds } };
  }

  /**
   * 解析RSS XML获取链接
   */
  private parseRssLinks(rssText: string): string[] {
    const links: string[] = [];

    // 使用正则表达式提取item中的link
    const itemRegex = /<item[^>]*>[\s\S]*?<\/item>/g;
    const linkRegex = /<link[^>]*>([^<]+)<\/link>/;

    const items = rssText.match(itemRegex) || [];
    for (const item of items) {
      const linkMatch = item.match(linkRegex);
      if (linkMatch && linkMatch[1]) {
        links.push(linkMatch[1].trim());
      }
    }

    return links;
  }

  /**
   * 下载单个项目的所有图片
   */
  private async downloadProject(hashId: string, targetDir: string, quality: string): Promise<PluginResult> {
    const projectUrl = `https://www.artstation.com/projects/${hashId}.json`;

    try {
      const response = await this.smartFetch(projectUrl, { accept: 'application/json' });

      if (!response.ok) {
        return { success: false, error: `Failed to fetch project: status ${response.status}` };
      }

      let project: ArtStationProject;
      try {
        project = JSON.parse(response.text);
      } catch {
        return { success: false, error: `Failed to parse project JSON for ${hashId}` };
      }
      const assets = project.assets || [];

      let downloadedCount = 0;

      for (let i = 0; i < assets.length; i++) {
        const asset = assets[i];

        // 输出图片下载进度
        const progress = Math.round((i / assets.length) * 100);
        this.reportProgress(progress, `Downloading image ${i + 1}/${assets.length}...`);

        if (asset.has_image && asset.image_url) {
          let imageUrl = asset.image_url;

          // 根据质量设置调整URL
          if (quality === '4k') {
            imageUrl = imageUrl.replace('/large/', '/4k/');
          }

          const fileName = this.getFileNameFromUrl(imageUrl);
          const filePath = `${targetDir}/${fileName}`;

          // 检查文件是否已存在
          try {
            await Deno.lstat(filePath);
            await this.logDebug('File already exists, skipping', { filePath });
            downloadedCount++;
            continue;
          } catch {
            // 文件不存在，继续下载
          }

          const downloadResult = await this.downloadImage(imageUrl, filePath);
          if (downloadResult) {
            downloadedCount++;
          }
        }
      }

      return { success: true, data: { count: downloadedCount } };

    } catch (error) {
      return { success: false, error: `Error processing project ${hashId}: ${String(error)}` };
    }
  }

  /**
   * 从URL提取文件名
   */
  private getFileNameFromUrl(url: string): string {
    try {
      const urlObj = new URL(url);
      const pathParts = urlObj.pathname.split('/');
      return pathParts[pathParts.length - 1] || `image_${Date.now()}.jpg`;
    } catch {
      return `image_${Date.now()}.jpg`;
    }
  }

  /**
   * 下载单个图片
   */
  private async downloadImage(url: string, filePath: string): Promise<boolean> {
    try {
      const response = await fetch(url, {
        headers: {
          ...this.defaultHeaders,
          'Accept': 'image/*,*/*'
        }
      });

      if (!response.ok) {
        await this.logWarn('Failed to download image', { url, status: response.status });
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
   * 通过 CloudflareBypass 发送请求 (Request Mirroring 方式)
   * 使用 x-hostname 头指定目标主机
   */
  private async fetchWithBypass(url: string): Promise<{ ok: boolean; status: number; text: string }> {
    try {
      const parsedUrl = new URL(url);
      const targetHostname = parsedUrl.hostname;
      const pathWithQuery = parsedUrl.pathname + parsedUrl.search;
      const bypassEndpoint = `${this.bypassUrl}${pathWithQuery}`;

      await this.logDebug('CloudflareBypass request', {
        url,
        endpoint: bypassEndpoint,
        hostname: targetHostname
      });

      const response = await fetch(bypassEndpoint, {
        headers: {
          'User-Agent': this.userAgent,
          'x-hostname': targetHostname
        }
      });

      const text = await response.text();

      if (!response.ok) {
        await this.logError('CloudflareBypass HTTP error', { status: response.status, response: text.substring(0, 500) });
        return { ok: false, status: response.status, text };
      }

      await this.logDebug('CloudflareBypass response', { status: response.status, length: text.length });

      return { ok: true, status: 200, text };

    } catch (error) {
      await this.logError('CloudflareBypass request failed', { url, error: String(error) });
      return { ok: false, status: 0, text: `CloudflareBypass connection failed: ${String(error)}` };
    }
  }

  /**
   * 智能 fetch - 自动选择直接请求或 CloudflareBypass
   */
  private async smartFetch(url: string, options?: { accept?: string }): Promise<{ ok: boolean; status: number; text: string }> {
    // 如果配置了 CloudflareBypass，使用它
    if (this.bypassUrl) {
      return this.fetchWithBypass(url);
    }

    // 否则使用普通 fetch
    try {
      const response = await fetch(url, {
        headers: {
          ...this.defaultHeaders,
          ...(options?.accept ? { 'Accept': options.accept } : {})
        }
      });

      const text = await response.text();
      return { ok: response.ok, status: response.status, text };

    } catch (error) {
      return { ok: false, status: 0, text: String(error) };
    }
  }
}

// 运行插件
if (import.meta.main) {
  const plugin = new ArtStationDownloadPlugin();
  await plugin.handleCommand();
}
