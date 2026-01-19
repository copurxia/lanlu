#!/usr/bin/env deno run --allow-net --allow-read

import { BasePlugin, PluginInfo, PluginInput, PluginParameter, PluginResult } from '../base_plugin.ts';
import { download } from "jsr:@doctor/download";

/**
 * E-Hentai下载插件
 * 处理E-Hentai画廊下载URL生成
 */

interface LoginCookie {
  name: string;
  value: string;
  domain: string;
  path: string;
}

class EHentaiDownloadPlugin extends BasePlugin {
  getPluginInfo(): PluginInfo {
    return {
      name: "E*Hentai Downloader",
      type: "download",
      namespace: "ehdl",
      login_from: "ehlogin",
      author: "Difegue",
      version: "1.2",
      description: "Downloads the given e*hentai URL and adds it to LANraragi. This uses GP to call the archiver, so make sure you have enough!",
      parameters: [
        { name: "forceresampled", type: "bool", desc: "Force resampled archive download", default_value: "0" }
      ],
      url_regex: "https?://e(-|x)hentai.org/g/.*/.*",
      permissions: ["net=e-hentai.org", "net=exhentai.org", "net=ehgt.org", "net=*.hath.network", "net=jsr.io"],
      update_url: "https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Download/EHentai.ts"
    };
  }

  protected async runPlugin(input: PluginInput): Promise<void> {
    try {
      const params = this.getParams();
      const loginCookies = (input.loginCookies || []) as LoginCookie[];
      const url = (input.url || '').trim();

      if (!url) {
        this.outputResult({ success: false, error: 'No URL provided.' });
        return;
      }

      this.reportProgress(1, 'Starting E-Hentai download...');
      await this.logInfo('EHentai download plugin started', { url });

      const result = await this.provideUrl(url, {
        forceresampled: params.forceresampled || false
      }, loginCookies);

      this.outputResult(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });
    }
  }

  /**
   * 处理下载URL生成
   */
  private async provideUrl(url: string, params: { forceresampled: boolean }, loginCookies: LoginCookie[]): Promise<PluginResult> {
    try {
      this.reportProgress(5, 'Validating gallery URL...');
      // 验证URL格式
      const urlMatch = url.match(/https?:\/\/e(-|x)hentai\.org\/g\/([0-9]*)\/([0-z]*)\/*.*/);
      if (!urlMatch) {
        return { success: false, error: "Not a valid E-H URL!" };
      }

      const [, domainPrefix, gID, gToken] = urlMatch;
      const domain = domainPrefix === 'ex' ? 'https://exhentai.org' : 'https://e-hentai.org';

      // 生成archiver URL
      const archiverUrl = `${domain}/archiver.php?gid=${gID}&token=${gToken}`;
      await this.logInfo('Resolved gallery', { gid: gID, token: gToken, archiverUrl, forceresampled: params.forceresampled });

      // 检查archiver URL是否有效
      const targetHost = this.getHostname(archiverUrl);
      this.reportProgress(15, 'Checking archiver page...');
      const checkResult = await this.checkArchiverUrl(archiverUrl, targetHost, loginCookies);
      if (!checkResult.success) {
        return checkResult;
      }

      // 获取下载URL
      this.reportProgress(25, 'Requesting archive download link...');
      const downloadResult = await this.getDownloadUrl(archiverUrl, params.forceresampled, targetHost, loginCookies);
      if (!downloadResult.success) {
        return downloadResult;
      }

      this.reportProgress(30, 'Downloading archive...');
      const downloaded = await this.downloadArchive(downloadResult.data.finalUrl, targetHost, loginCookies, gID, gToken, params.forceresampled);
      if (!downloaded.success) {
        return downloaded;
      }

      return {
        success: true,
        data: [{
          relative_path: downloaded.data.relativePath,
          filename: downloaded.data.filename,
          source: 'https://e-hentai.org/g/' + gID + '/' + gToken,
          archive_size: params.forceresampled ? 'resampled' : 'original'
        }]
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `URL processing failed: ${errorMessage}` };
    }
  }

  private async downloadArchive(
    finalUrl: string,
    domain: string,
    loginCookies: LoginCookie[],
    gID: string,
    gToken: string,
    forceresampled: boolean
  ): Promise<PluginResult> {
    try {
      const pluginDir = this.input?.pluginDir || './data/cache/plugins/ehdl';
      await Deno.mkdir(pluginDir, { recursive: true });

      const cookieHeader = this.buildCookieHeader(domain, loginCookies);

      const userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

      const headers = new Headers();
      headers.set('User-Agent', userAgent);
      headers.set('Referer', `https://${domain}/`);
      if (cookieHeader) {
        headers.set('Cookie', cookieHeader);
      }

      await this.logInfo('Fetching archive stream', { finalUrl, domain, forceresampled });
      const { readable, headers: respHeaders } = await download(finalUrl, { headers });

      const contentDisposition =
        respHeaders.get('content-disposition') || respHeaders.get('Content-Disposition') || '';
      const contentLengthHeader =
        respHeaders.get('content-length') || respHeaders.get('Content-Length') || '';
      const contentLength = Number.parseInt(contentLengthHeader || '0', 10);

      const derived = this.deriveFilenameFromContentDisposition(contentDisposition);
      const fixed = this.maybeFixMojibakeUtf8(derived);

      const fallback = `ehdl_${gID}_${gToken}_${forceresampled ? 'res' : 'org'}_${Date.now()}.zip`;
      const chosen = fixed && !this.looksGarbledFilename(fixed) ? fixed : fallback;
      const safeName = chosen.replace(/[\\/]/g, '_');
      const finalPath = await this.allocateUniquePath(`${pluginDir}/${safeName}`);

      await this.logInfo('Archive download started', {
        contentDisposition,
        contentLength,
        derivedFilename: derived,
        fixedFilename: fixed,
        finalPath
      });

      const file = await Deno.open(finalPath, { create: true, write: true, truncate: true });
      try {
        await this.pipeWithProgress(readable, file, contentLength);
      } finally {
        try {
          file.close();
        } catch {
          // ignore
        }
      }

      this.reportProgress(100, 'Download complete');
      await this.logInfo('Archive download completed', { finalPath });

      const filename = finalPath.split('/').pop() ?? safeName;
      const relativePath = `plugins/ehdl/${filename}`;
      return { success: true, data: { relativePath, filename } };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Archive download failed: ${errorMessage}` };
    }
  }

  private async pipeWithProgress(
    readable: ReadableStream<Uint8Array>,
    file: Deno.FsFile,
    contentLength: number
  ): Promise<void> {
    const reader = readable.getReader();
    let received = 0;
    let lastReportedPercent = -1;
    let lastReportAt = 0;
    const start = Date.now();

    // Keep the pre-download phases (validate/link generation) within 0-30.
    const base = 30;
    const span = 70;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value || value.length === 0) continue;

      // Write chunk to disk.
      let offset = 0;
      while (offset < value.length) {
        const n = await file.write(value.subarray(offset));
        if (n <= 0) break;
        offset += n;
      }
      received += offset;

      // Throttle progress updates to avoid spamming logs.
      const now = Date.now();
      if (now - lastReportAt < 400) continue;
      lastReportAt = now;

      if (contentLength > 0) {
        const ratio = Math.min(1, received / contentLength);
        const percent = Math.min(99, base + Math.floor(ratio * span));
        if (percent !== lastReportedPercent) {
          lastReportedPercent = percent;
          const mb = (received / 1024 / 1024).toFixed(1);
          const totalMb = (contentLength / 1024 / 1024).toFixed(1);
          this.reportProgress(percent, `Downloading... ${mb}MiB / ${totalMb}MiB`);
        }
      } else {
        // Unknown length; emit periodic byte-based updates.
        const elapsed = Math.max(1, (now - start) / 1000);
        const mib = received / 1024 / 1024;
        const speed = (mib / elapsed).toFixed(2);
        const percent = Math.min(99, base + Math.min(span - 1, Math.floor(mib)));
        if (percent !== lastReportedPercent) {
          lastReportedPercent = percent;
          this.reportProgress(percent, `Downloading... ${mib.toFixed(1)}MiB (${speed} MiB/s)`);
        }
      }
    }
  }

  private async allocateUniquePath(path: string): Promise<string> {
    try {
      await Deno.lstat(path);
    } catch {
      return path;
    }

    const dot = path.lastIndexOf('.');
    const base = dot > -1 ? path.slice(0, dot) : path;
    const ext = dot > -1 ? path.slice(dot) : '';
    for (let i = 1; i < 10000; i++) {
      const candidate = `${base}.${i}${ext}`;
      try {
        await Deno.lstat(candidate);
      } catch {
        return candidate;
      }
    }
    return `${base}.${Date.now()}${ext}`;
  }

  private deriveFilenameFromContentDisposition(headerValue: string): string {
    if (!headerValue) return '';
    const star = this.parseFilenameStar(headerValue);
    if (star) return star;
    return this.parseFilename(headerValue);
  }

  private looksGarbledFilename(name: string): boolean {
    if (!name) return true;
    if (name.includes('\uFFFD')) return true; // replacement character
    // C0/C1 control chars
    if (/[\x00-\x1F\x7F\u0080-\u009F]/.test(name)) return true;

    // Common mojibake sequences when UTF-8 bytes are mis-decoded as Latin-1
    if (name.includes('Ã') || name.includes('â') || name.includes('æ') || name.includes('¤')) return true;
    return false;
  }

  private maybeFixMojibakeUtf8(name: string): string {
    // If a server sends raw UTF-8 in filename= but it's interpreted as Latin-1,
    // converting bytes back to UTF-8 usually restores CJK filenames.
    if (!name) return name;
    if (!this.looksGarbledFilename(name)) return name;

    try {
      const bytes = new Uint8Array(name.length);
      for (let i = 0; i < name.length; i++) {
        bytes[i] = name.charCodeAt(i) & 0xff;
      }
      const fixed = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
      if (fixed && !this.looksGarbledFilename(fixed)) {
        return fixed;
      }
      return name;
    } catch {
      return name;
    }
  }

  private parseFilenameStar(contentDisposition: string): string {
    // RFC 5987: filename*=charset''percent-encoded
    const match = contentDisposition.match(/filename\*\s*=\s*([^;]+)/i);
    if (!match?.[1]) return '';

    const value = match[1].trim();
    const unquoted = value.replace(/^\"|\"$/g, '');
    // format: charset'lang'%xx%yy
    const partsMatch = unquoted.match(/^([^']*)'[^']*'(.*)$/);
    if (!partsMatch) {
      // Some servers send filename*=percent without charset/lang; try best-effort
      return this.decodeUriComponentSafe(unquoted);
    }

    const charset = (partsMatch[1] || 'utf-8').trim().toLowerCase();
    const encoded = partsMatch[2] || '';
    try {
      const bytes = this.percentDecodeToBytes(encoded);
      const decoder = new TextDecoder(charset as any, { fatal: false });
      return decoder.decode(bytes);
    } catch {
      return this.decodeUriComponentSafe(encoded);
    }
  }

  private parseFilename(contentDisposition: string): string {
    const match = contentDisposition.match(/filename\s*=\s*([^;]+)/i);
    if (!match?.[1]) return '';
    const value = match[1].trim().replace(/^\"|\"$/g, '');
    const decoded = this.decodeMimeEncodedWord(value);
    // Some servers percent-encode even in filename=
    if (decoded.includes('%')) {
      return this.decodeUriComponentSafe(decoded);
    }
    return decoded;
  }

  private decodeMimeEncodedWord(value: string): string {
    // RFC 2047: =?charset?B?base64?= or =?charset?Q?quoted-printable?=
    const m = value.match(/^=\\?([^?]+)\\?([bBqQ])\\?([^?]+)\\?=$/);
    if (!m) return value;
    const charset = m[1].trim().toLowerCase();
    const encoding = m[2].toUpperCase();
    const payload = m[3];
    try {
      let bytes: Uint8Array;
      if (encoding === 'B') {
        bytes = this.base64ToBytes(payload);
      } else {
        bytes = this.qpToBytes(payload);
      }
      const decoder = new TextDecoder(charset as any, { fatal: false });
      return decoder.decode(bytes);
    } catch {
      return value;
    }
  }

  private decodeUriComponentSafe(value: string): string {
    try {
      return decodeURIComponent(value);
    } catch {
      return value;
    }
  }

  private percentDecodeToBytes(value: string): Uint8Array {
    const bytes: number[] = [];
    for (let i = 0; i < value.length; i++) {
      const ch = value[i];
      if (ch === '%' && i + 2 < value.length) {
        const hex = value.slice(i + 1, i + 3);
        const byte = Number.parseInt(hex, 16);
        if (!Number.isNaN(byte)) {
          bytes.push(byte);
          i += 2;
          continue;
        }
      }
      bytes.push(ch.charCodeAt(0) & 0xff);
    }
    return new Uint8Array(bytes);
  }

  private base64ToBytes(value: string): Uint8Array {
    const bin = atob(value.replace(/\\s+/g, ''));
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) & 0xff;
    return out;
  }

  private qpToBytes(value: string): Uint8Array {
    // RFC 2047 Q-encoding: '_' means space, =HH hex
    const normalized = value.replace(/_/g, ' ');
    const bytes: number[] = [];
    for (let i = 0; i < normalized.length; i++) {
      const ch = normalized[i];
      if (ch === '=' && i + 2 < normalized.length) {
        const hex = normalized.slice(i + 1, i + 3);
        const byte = Number.parseInt(hex, 16);
        if (!Number.isNaN(byte)) {
          bytes.push(byte);
          i += 2;
          continue;
        }
      }
      bytes.push(ch.charCodeAt(0) & 0xff);
    }
    return new Uint8Array(bytes);
  }

  /**
   * 检查archiver URL是否有效
   */
  private async checkArchiverUrl(archiverUrl: string, domain: string, loginCookies: LoginCookie[]): Promise<PluginResult> {
    try {
      await this.logDebug('Checking archiver URL', { archiverUrl, domain });
      const headers = this.buildRequestHeaders(domain, loginCookies);
      const response = await fetch(archiverUrl, {
        headers
      });

      if (!response.ok) {
        return { success: false, error: `Failed to access archiver: ${response.statusText}` };
      }

      const html = await response.text();

      if (html.includes('Invalid archiver key')) {
        return { success: false, error: `Invalid archiver key. (${archiverUrl})` };
      }

      if (html.includes('This page requires you to log on.')) {
        return { success: false, error: 'Invalid E*Hentai login credentials. Please make sure the login plugin has proper settings set.' };
      }

      return { success: true };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Archiver check failed: ${errorMessage}` };
    }
  }

  /**
   * 获取最终下载URL
   */
  private async getDownloadUrl(archiverUrl: string, forceresampled: boolean, domain: string, loginCookies: LoginCookie[]): Promise<PluginResult> {
    try {
      await this.logDebug('Generating download URL', { archiverUrl, domain, forceresampled });
      const dltype = forceresampled ? 'res' : 'org';
      const dlcheck = forceresampled ? 'Download+Resample+Archive' : 'Download+Original+Archive';

      const formData = new FormData();
      formData.append('dltype', dltype);
      formData.append('dlcheck', dlcheck);

      const headers = this.buildRequestHeaders(domain, loginCookies);
      const response = await fetch(archiverUrl, {
        method: 'POST',
        body: formData,
        headers
      });

      if (!response.ok) {
        return { success: false, error: `POST request failed: ${response.statusText}` };
      }

      const content = await response.text();

      // 检查GP不足
      if (content.includes('Insufficient funds')) {
        return { success: false, error: 'You do not have enough GP to download this URL.' };
      }

      // 解析最终URL
      const finalUrlMatch = content.match(/document\.location = "([^"]+)"/);
      if (!finalUrlMatch) {
        const archiveType = forceresampled ? 'resampled' : 'original size';
        return {
          success: false,
          error: `Couldn't proceed with ${archiveType} download: <pre>${content}</pre>`
        };
      }

      let finalUrl = finalUrlMatch[1];

      // 添加start=1参数自动触发下载
      const url = new URL(finalUrl);
      url.searchParams.set('start', '1');
      finalUrl = url.toString();

      return { success: true, data: { finalUrl } };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Download URL generation failed: ${errorMessage}` };
    }
  }

  private parseLoginCookies(args: string[]): LoginCookie[] {
    const cookieArg = args.find(arg => arg.startsWith('--login_cookies='));
    if (!cookieArg) {
      return [];
    }
    const payload = cookieArg.substring('--login_cookies='.length);
    try {
      const parsed = JSON.parse(payload);
      if (!Array.isArray(parsed)) {
        return [];
      }

      return parsed
        .map(cookie => ({
          name: cookie?.name || '',
          value: cookie?.value || '',
          domain: cookie?.domain || '',
          path: cookie?.path || '/'
        }))
        .filter((cookie): cookie is LoginCookie => Boolean(cookie.name && cookie.value && cookie.domain));
    } catch (error) {
      console.warn('Failed to parse login cookies', error);
      return [];
    }
  }

  private buildRequestHeaders(domain: string, cookies: LoginCookie[]): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    };
    const cookieHeader = this.buildCookieHeader(domain, cookies);
    if (cookieHeader) {
      headers['Cookie'] = cookieHeader;
    }
    return headers;
  }

  private buildCookieHeader(domain: string, cookies: LoginCookie[]): string {
    const normalizedDomain = domain.toLowerCase();
    const matched = cookies.filter(cookie => this.domainMatches(cookie.domain, normalizedDomain));
    if (matched.length === 0) {
      return '';
    }
    return matched.map(cookie => `${cookie.name}=${cookie.value}`).join('; ');
  }

  private domainMatches(cookieDomain: string, targetDomain: string): boolean {
    if (!cookieDomain || !targetDomain) {
      return false;
    }
    const normalizedCookie = cookieDomain.replace(/^\./, '').toLowerCase();
    const normalizedTarget = targetDomain.replace(/^www\./, '').toLowerCase();
    return (
      normalizedTarget === normalizedCookie ||
      normalizedTarget.endsWith(`.${normalizedCookie}`) ||
      normalizedCookie.endsWith(`.${normalizedTarget}`)
    );
  }

  private getHostname(targetUrl: string): string {
    try {
      return new URL(targetUrl).hostname;
    } catch (_error) {
      return '';
    }
  }
}

// 运行插件
if (import.meta.main) {
  const plugin = new EHentaiDownloadPlugin();
  await plugin.handleCommand();
}
