#!/usr/bin/env deno run --allow-net --allow-read

import { BasePlugin, PluginInfo, PluginInput, PluginResult } from '../base_plugin.ts';

/**
 * Pixiv 登录插件
 *
 * Pixiv 的 web ajax 接口在部分内容（R18/仅登录可见等）场景下会返回 urls.original=null，
 * 因此需要提供已登录浏览器的 Cookie（通常只需要 PHPSESSID）。
 */
class PixivLoginPlugin extends BasePlugin {
  private static readonly USER_AGENT =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  getPluginInfo(): PluginInfo {
    return {
      name: 'Pixiv',
      type: 'login',
      namespace: 'pixivlogin',
      author: 'lrr4cj',
      version: '1.0',
      description:
        'Stores Pixiv login cookies (PHPSESSID) for other Pixiv plugins (download/metadata). Grab cookies from your browser after logging in.',
      parameters: [
        { name: 'PHPSESSID', type: 'string', desc: 'Pixiv PHPSESSID cookie value (required for logged-in access)' },
        { name: 'device_token', type: 'string', desc: 'Optional device_token cookie value' },
      ],
      permissions: ['net=www.pixiv.net'],
      update_url: 'https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Login/Pixiv.ts',
    };
  }

  protected async runPlugin(_: PluginInput): Promise<void> {
    try {
      this.reportProgress(10, '读取登录参数...');
      const params = this.getParams();
      const phpsessid = String(params.PHPSESSID || '').trim();
      const deviceToken = String(params.device_token || '').trim();

      const result = await this.doLogin(phpsessid, deviceToken);
      this.reportProgress(100, '登录完成');
      this.outputResult(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });
    }
  }

  private async doLogin(PHPSESSID: string, deviceToken: string): Promise<PluginResult> {
    if (!PHPSESSID) {
      // 与其它 login 插件保持一致：允许空配置（但后续可能无法获取 original url）
      return { success: true, data: { cookies: [], message: 'No cookies provided, returning blank configuration.' } };
    }

    const cookies: Array<{ name: string; value: string; domain: string; path: string }> = [
      { name: 'PHPSESSID', value: PHPSESSID, domain: 'www.pixiv.net', path: '/' },
    ];
    if (deviceToken) {
      cookies.push({ name: 'device_token', value: deviceToken, domain: 'www.pixiv.net', path: '/' });
    }

    const validation = await this.validateCookies(cookies);
    if (!validation.success) return validation;

    return {
      success: true,
      data: { cookies, message: 'Successfully configured Pixiv authentication cookies.' },
    };
  }

  private async validateCookies(
    cookies: Array<{ name: string; value: string; domain: string; path: string }>
  ): Promise<PluginResult> {
    try {
      const cookieHeader = cookies.map((c) => `${c.name}=${c.value}`).join('; ');
      const resp = await fetch('https://www.pixiv.net/ajax/user/self?lang=en', {
        headers: {
          'User-Agent': PixivLoginPlugin.USER_AGENT,
          'Accept': 'application/json, text/plain, */*',
          'Referer': 'https://www.pixiv.net/',
          'Cookie': cookieHeader,
        },
      });

      if (!resp.ok) {
        return { success: false, error: `HTTP ${resp.status}: Failed to access Pixiv ajax (check cookies).` };
      }

      const json = await resp.json().catch(() => null);
      // 典型返回结构：{error:false, body:{...}}；未登录通常 error=true。
      if (json && typeof json === 'object' && 'error' in json && json.error === true) {
        const msg = typeof json.message === 'string' ? json.message : 'Invalid Pixiv cookies.';
        return { success: false, error: msg };
      }

      return { success: true };
    } catch (error) {
      // 网络检查失败时不阻断保存，避免因临时网络问题导致无法配置。
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: true, data: { warning: `Could not validate cookies: ${errorMessage}. Assuming they are correct.` } };
    }
  }
}

if (import.meta.main) {
  const plugin = new PixivLoginPlugin();
  await plugin.handleCommand();
}

