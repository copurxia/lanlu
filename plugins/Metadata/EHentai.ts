#!/usr/bin/env deno run --allow-net --allow-read

import { BasePlugin, PluginInfo, PluginInput, PluginResult } from '../base_plugin.ts';

/**
 * E-Hentai元数据插件
 * 从E-Hentai搜索并获取画廊标签和元数据
 */
class EHentaiMetadataPlugin extends BasePlugin {
  private static readonly USER_AGENT =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

  getPluginInfo(): PluginInfo {
    return {
      name: "E-Hentai",
      type: "metadata",
      namespace: "ehplugin",
      login_from: "ehlogin",
      author: "Difegue and others",
      version: "2.6",
      description: "Searches g.e-hentai for tags matching your archive. This plugin will use the source: tag of the archive if it exists.",
      parameters: [
        { name: "lang", type: "string", desc: "Forced language to use in searches (Japanese won't work due to EH limitations)" },
        { name: "usethumbs", type: "bool", desc: "Fetch using thumbnail first (falls back to title)" },
        { name: "search_gid", type: "bool", desc: "Search using gID from title (falls back to title)" },
        { name: "enablepanda", type: "bool", desc: "Use ExHentai (enable to search for fjorded content without star cookie)" },
        { name: "jpntitle", type: "bool", desc: "Save the original title when available instead of the English or romanised title" },
        { name: "additionaltags", type: "bool", desc: "Fetch additional timestamp (time posted) and uploader metadata" },
        { name: "expunged", type: "bool", desc: "Search only expunged galleries" },
        { name: "debug", type: "bool", desc: "Write verbose debug logs to data/logs/plugins.log" }
      ],
      oneshot_arg: "E-H Gallery URL (Will attach tags matching this exact gallery to your archive)",
      cooldown: 4,
      // 需要读缩略图目录以进行 file search；需要访问 upload.e-hentai.org 上传图片。
      permissions: ["net=e-hentai.org", "net=exhentai.org", "net=api.e-hentai.org", "net=upload.e-hentai.org", "read=./data/thumb"],
      icon: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAAEnQAABJ0Ad5mH3gAAAOASURBVDhPjVNbaFRXFF3n3puZyZ3EzJ1HkpIohthAP0InYMAKUUpfVFDylY9Bg1CJ+UllfLSEIoIEtBan7Y9t8KO0pSU0lH74oQZsMWImkSBalUADqR8mTVOTyXMymcfd7nPuNZpo2yzm3DmPfdZZZ+91MDyYJA0g+AMkStY3i8Brn392jjYKIclK7hP0rNzK7XkIIM8BdlRgkdYvvhya7bcUGT0ugKbXNZ4zcsCS+Qoycyl3y39DCL5qoJ+DpUKvM6mwzIcsFQCfjtmfL+LQX5cRa+9AOp12A57Btm1UV1ejoaHBIbTupDB/YB/yg5fcEKDo3VaUnPoWlLZBfg1zOwU6OjqQSr2o1DAMJJNJNDU1OYTBeynMNFbBPHoRwirnxOWgVW2DVhbh4wsQQR2p3VWgxXGX4uWQxJxyFyvLKHpzDzy7tsOz+w1olkMmQfKW+z/Gmc7javxvKC0t5SSywtCfRFplDYlNIRJlES65QYEbRNYQrf77bxFtKRauOYj6+vook8m4IweBAFtNXfl+CtP1FszD56VuLo6J/O/XYT98AL1+FwojQxChSuRuXsV3X55mywbR1taGlpYWlbfx8XHEYjFVFEfhQ2UyCriKAv2sapjIF/+agndZ3dmrZP1GpH/4Fb1eu0XF9vT0UHd3t+onEgkaGxuj8vJy+UieQfPzASxQNqxwyyyD2D5YmoU9PwfP3naETS+i0Siam5vBJOjq6kI8HkdNTQ2y2SzkVmZQXyydPMIEC+y/eRQfuQAU8mreznBVhIAvBFwb+YeLdA+6z0RFRQUmJiZUzFMohVKFr/UUq5jmAU/ofM5KGkWN74HY8MarnBtv8Wq1T350DLquw+PxyO1rIOC3KJicQbZ/SFpeKUGBvVfGchhaZDOEybnIs4U0HTYfOP+OABcVvb29qjCyL2FZlrysTqHJPBY+OMwbpGBJmIPx2g5FbuzYC30ze9KxJEQYmIlWclom1Xh0dBR1dXWKNBwOQxxtP0SJn/qBne+vGlmBXwtHATmujtfDP9nn3Hj9WBn4FefiB3Gi8xM32IFSKA05cvc2Jh894rysKbqCaZq48MWn+OaPrUBjTKUD37+Fqam/EYnwM30OklBK/V8spqYIRh3hB8evd4YH3ZW1YELaEKGE32sQKt6mK7/86M68CHnYhgkTifNqQ21trVKyvsm1gYEBegL+M2W04901FQAAAABJRU5ErkJggg==",
      update_url: "https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Metadata/EHentai.ts"
    };
  }

  protected async runPlugin(input: PluginInput): Promise<void> {
    try {
      this.reportProgress(5, '初始化元数据搜索...');
      const params = this.getParams();
      const debug = !!params.debug;

      await this.logInfo("run:start", {
        archive_id: input.archiveId || '',
        has_oneshot: !!input.oneshotParam,
        title_len: (input.archiveTitle || '').length,
        has_thumbhash: !!(input.thumbnailHash || ''),
        login_cookie_count: (input.loginCookies || []).length,
        usethumbs: !!params.usethumbs,
        search_gid: !!params.search_gid,
        enablepanda: !!params.enablepanda,
        expunged: !!params.expunged,
        debug
      });

      this.reportProgress(10, '准备搜索参数...');

      // 从 input 中获取必要信息
      const lrrInfo = {
        archive_title: input.archiveTitle || '',
        existing_tags: input.existingTags || '',
        thumbnail_hash: input.thumbnailHash || '',
        login_cookies: input.loginCookies || [],
        oneshot_param: input.oneshotParam || '',
        archive_id: input.archiveId || '',
        debug
      };

      this.reportProgress(20, '开始搜索 E-Hentai...');

      const result = await this.getTags(
        lrrInfo,
        params.lang || '',
        params.usethumbs || false,
        params.search_gid || false,
        params.enablepanda || false,
        params.jpntitle || false,
        params.additionaltags || false,
        params.expunged || false
      );

      this.reportProgress(100, '元数据获取完成');
      this.outputResult(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });
    }
  }

  private async getTags(
    lrrInfo: any,
    lang: string,
    usethumbs: boolean,
    search_gid: boolean,
    enablepanda: boolean,
    jpntitle: boolean,
    additionaltags: boolean,
    expunged: boolean
  ): Promise<PluginResult> {
    let gID = "";
    let gToken = "";
    const domain = enablepanda ? 'https://exhentai.org' : 'https://e-hentai.org';
    const cookies = Array.isArray(lrrInfo.login_cookies) ? lrrInfo.login_cookies : [];
    const debug = !!lrrInfo.debug;

    await this.dlog(debug, "getTags:context", {
      archive_id: lrrInfo.archive_id || '',
      domain,
      title: (lrrInfo.archive_title || '').slice(0, 200),
      thumbhash: lrrInfo.thumbnail_hash ? `${String(lrrInfo.thumbnail_hash).slice(0, 8)}…` : '',
      cookie_count: cookies.length
    });

    // 从oneshot参数或source标签提取gallery IDs
    if (lrrInfo.oneshot_param && lrrInfo.oneshot_param.match(/.*\/g\/([0-9]*)\/([0-z]*)\/*.*/)) {
      const match = lrrInfo.oneshot_param.match(/.*\/g\/([0-9]*)\/([0-z]*)\/*.*/);
      if (match) {
        gID = match[1];
        gToken = match[2];
        await this.dlog(debug, "getTags:use_oneshot", { gID, gToken: `${gToken.slice(0, 6)}…` });
      }
    } else if (lrrInfo.existing_tags && lrrInfo.existing_tags.match(/.*source:\s*(?:https?:\/\/)?e(?:x|-)hentai\.org\/g\/([0-9]*)\/([0-z]*)\/*.*/gi)) {
      const match = lrrInfo.existing_tags.match(/.*source:\s*(?:https?:\/\/)?e(?:x|-)hentai\.org\/g\/([0-9]*)\/([0-z]*)\/*.*/gi);
      if (match) {
        const srcMatch = match[0].match(/g\/([0-9]*)\/([0-z]*)/);
        if (srcMatch) {
          gID = srcMatch[1];
          gToken = srcMatch[2];
          await this.dlog(debug, "getTags:use_source_tag", { gID, gToken: `${gToken.slice(0, 6)}…` });
        }
      }
    }

    if (!gID) {
      // 搜索matching gallery
      const searchResult = await this.lookupGallery(
        lrrInfo.archive_title,
        lrrInfo.existing_tags,
        lrrInfo.thumbnail_hash,
        domain,
        cookies,
        lang,
        usethumbs,
        search_gid,
        expunged,
        debug
      );

      if (searchResult.success) {
        gID = searchResult.data.gID;
        gToken = searchResult.data.gToken;
        await this.dlog(debug, "getTags:lookup_success", { gID, gToken: `${gToken.slice(0, 6)}…` });
      } else {
        await this.logWarn("getTags:lookup_failed", { archive_id: lrrInfo.archive_id || '', error: searchResult.error });
        return searchResult;
      }
    }

    if (!gID) {
      return { success: false, error: "No matching EH Gallery Found!" };
    }

    // 获取tags
    const tagsResult = await this.getTagsFromEH(gID, gToken, jpntitle, additionaltags);
    if (!tagsResult.success) {
      await this.logWarn("getTags:gdata_failed", { archive_id: lrrInfo.archive_id || '', gID, error: tagsResult.error });
      return tagsResult;
    }

    const hashData: any = { tags: tagsResult.data.tags };

    // 添加source URL和title（同时添加两个域名）
    if (hashData.tags) {
      const sourceUrlEx = `https://exhentai.org/g/${gID}/${gToken}`;
      const sourceUrlE = `https://e-hentai.org/g/${gID}/${gToken}`;
      hashData.tags += `, source:${sourceUrlEx}, source:${sourceUrlE}`;
      hashData.title = tagsResult.data.title;
    }

    return { success: true, data: hashData };
  }

  private async lookupGallery(
    title: string,
    tags: string,
    thumbhash: string,
    domain: string,
    cookies: Array<{ name: string; value: string; domain?: string; path?: string }>,
    defaultlanguage: string,
    usethumbs: boolean,
    search_gid: boolean,
    expunged: boolean,
    debug: boolean
  ): Promise<PluginResult> {
    try {
      // 缩略图以图搜图（通过 upload.e-hentai.org 的 file search）
      if (thumbhash && usethumbs) {
        const thumbFile = await this.resolveThumbnailFilePath(thumbhash);
        if (thumbFile) {
          await this.dlog(debug, "lookup:file_search:start", { thumbhash: `${thumbhash.slice(0, 8)}…`, file: thumbFile });
          const result = await this.fileSearchByUpload(thumbFile, cookies);
          if (result.success) {
            return result;
          }
          await this.logWarn("lookup:file_search:miss", { error: result.error || "unknown" });
        } else {
          await this.logWarn("lookup:file_search:no_thumb_file", { thumbhash: `${thumbhash.slice(0, 8)}…` });
        }
      }

      // 使用标题中的gID搜索
      if (search_gid) {
        const titleGidMatch = title.match(/\[([0-9]+)\]/g);
        if (titleGidMatch) {
          const gid = titleGidMatch[0].replace(/\[|\]/g, '');
          const url = `${domain}?f_search=gid:${gid}`;
          await this.dlog(debug, "lookup:gid_search:start", { gid });
          const result = await this.ehentaiParse(url, cookies);
          if (result.success) {
            return result;
          }
          await this.dlog(debug, "lookup:gid_search:miss", { error: result.error || "unknown" });
        }
      }

      // 常规文本搜索
      let url = `${domain}?advsearch=1&f_sfu=on&f_sft=on&f_sfl=on&f_search=${encodeURIComponent(`"${title}"`)}`;
      await this.dlog(debug, "lookup:title_search:base", { title: title.slice(0, 200) });

      // 添加artist标签
      const artistMatch = tags.match(/.*artist:\s?([^,]*),*.*/gi);
      if (artistMatch && artistMatch[0]) {
        const artist = artistMatch[0].replace(/.*artist:\s?([^,]*),*.*/gi, '$1');
        if (/^[\x00-\x7F]*$/.test(artist)) {
          url += `+${encodeURIComponent(`artist:${artist}`)}`;
          await this.dlog(debug, "lookup:title_search:add_artist", { artist });
        }
      }

      // 添加语言覆盖
      if (defaultlanguage) {
        url += `+${encodeURIComponent(`language:${defaultlanguage}`)}`;
        await this.dlog(debug, "lookup:title_search:add_language", { language: defaultlanguage });
      }

      // 搜索已删除画廊
      if (expunged) {
        url += "&f_sh=on";
        await this.dlog(debug, "lookup:title_search:expunged", {});
      }

      return await this.ehentaiParse(url, cookies);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Gallery lookup failed: ${errorMessage}` };
    }
  }

  private async ehentaiParse(
    url: string,
    cookies: Array<{ name: string; value: string; domain?: string; path?: string }>
  ): Promise<PluginResult> {
    try {
      const response = await fetch(url, {
        headers: {
          ...this.buildHeaders(url, cookies)
        }
      });

      if (!response.ok) {
        return { success: false, error: `HTTP ${response.status}: ${response.statusText}` };
      }

      const html = await response.text();
      return this.parseGalleryFromHtml(html);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Search failed: ${errorMessage}` };
    }
  }

  private parseGalleryFromHtml(html: string): PluginResult {
    // 检查是否被临时禁止
    if (html.includes('Your IP address has been')) {
      return { success: false, error: 'Temporarily banned from EH for excessive pageloads.' };
    }

    // 解析搜索结果
    const glinkMatch = html.match(
      /<a[^>]*href="[^"]*\/g\/(\d+)\/([^"\/]*)[^"]*"[^>]*>\s*<div[^>]*class="glink"[^>]*>/i
    );
    if (glinkMatch) {
      const gID = glinkMatch[1];
      const gToken = glinkMatch[2];
      return { success: true, data: { gID, gToken } };
    }

    if (html.includes('No hits found')) {
      return { success: false, error: 'No gallery found in search results' };
    }

    return { success: false, error: 'No gallery found in search results' };
  }

  private async resolveThumbnailFilePath(thumbhash: string): Promise<string | null> {
    const base = `./data/thumb/${thumbhash}`;
    const candidates = [base, `${base}.jpg`, `${base}.jpeg`, `${base}.png`, `${base}.webp`];
    for (const path of candidates) {
      try {
        const st = await Deno.stat(path);
        if (st.isFile) {
          return path;
        }
      } catch {
        // ignore
      }
    }
    return null;
  }

  private detectMimeType(path: string): string {
    const lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpeg') || lower.endsWith('.jpg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  private async fileSearchByUpload(
    thumbnailPath: string,
    cookies: Array<{ name: string; value: string; domain?: string; path?: string }>
  ): Promise<PluginResult> {
    try {
      const uploadUrl = 'https://upload.e-hentai.org/image_lookup.php';
      const bytes = await Deno.readFile(thumbnailPath);
      const blob = new Blob([bytes], { type: this.detectMimeType(thumbnailPath) });
      await this.logInfo("file_search:upload", {
        file: thumbnailPath,
        size: bytes.byteLength,
        mime: this.detectMimeType(thumbnailPath)
      });

      const form = new FormData();
      form.append('sfile', blob, thumbnailPath.split('/').pop() || 'cover.jpg');
      form.append('fs_similar', 'on');
      form.append('fs_covers', 'on');

      const response = await fetch(uploadUrl, {
        method: 'POST',
        body: form,
        headers: {
          ...this.buildHeaders(uploadUrl, cookies)
        }
      });

      if (!response.ok) {
        return { success: false, error: `HTTP ${response.status}: ${response.statusText}` };
      }

      const html = await response.text();
      if (html.includes('Similarity Scan was disabled')) {
        await this.logWarn("file_search:similarity_disabled", {});
      }
      return this.parseGalleryFromHtml(html);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `File search failed: ${errorMessage}` };
    }
  }

  private async getTagsFromEH(
    gID: string,
    gToken: string,
    jpntitle: boolean,
    additionaltags: boolean
  ): Promise<PluginResult> {
    try {
      const response = await fetch('https://api.e-hentai.org/api.php', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': EHentaiMetadataPlugin.USER_AGENT
        },
        body: JSON.stringify({
          method: "gdata",
          gidlist: [[parseInt(gID), gToken]],
          namespace: 1
        })
      });

      if (!response.ok) {
        return { success: false, error: `API request failed: ${response.statusText}` };
      }

      const json = await response.json();

      if (json.error) {
        return { success: false, error: json.error };
      }

      const data = json.gmetadata[0];
      if (!data) {
        return { success: false, error: 'No metadata returned from API' };
      }

      const tags = [...data.tags, `category:${data.category.toLowerCase()}`];

      if (additionaltags) {
        if (data.uploader) {
          tags.push(`uploader:${data.uploader}`);
        }
        if (data.posted) {
          tags.push(`timestamp:${data.posted}`);
        }
      }

      const title = jpntitle && data.title_jpn ? data.title_jpn : data.title;

      return {
        success: true,
        data: {
          tags: tags.join(', '),
          title: this.htmlUnescape(title)
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `API call failed: ${errorMessage}` };
    }
  }

  private htmlUnescape(text: string): string {
    return text
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'");
  }

  private cookieHeaderForUrl(
    url: string,
    cookies: Array<{ name: string; value: string; domain?: string; path?: string }>
  ): string {
    if (!cookies || cookies.length === 0) {
      return '';
    }
    let hostname = '';
    try {
      hostname = new URL(url).hostname;
    } catch {
      return '';
    }

    const applicable = cookies.filter(cookie => {
      const domain = cookie.domain || '';
      if (!domain) return false;
      if (domain.startsWith('.')) {
        return hostname.endsWith(domain.substring(1));
      }
      return hostname === domain;
    });

    if (applicable.length === 0) {
      return '';
    }

    return applicable.map(c => `${c.name}=${c.value}`).join('; ');
  }

  private buildHeaders(
    url: string,
    cookies: Array<{ name: string; value: string; domain?: string; path?: string }>
  ): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': EHentaiMetadataPlugin.USER_AGENT
    };
    const cookie = this.cookieHeaderForUrl(url, cookies);
    if (cookie) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  private async dlog(debug: boolean, message: string, meta?: unknown): Promise<void> {
    if (!debug) {
      return;
    }
    await this.logDebug(message, meta);
  }
}

// 运行插件
if (import.meta.main) {
  const plugin = new EHentaiMetadataPlugin();
  await plugin.handleCommand();
}
