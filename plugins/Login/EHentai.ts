#!/usr/bin/env deno run --allow-net --allow-read

import { BasePlugin, PluginInfo, PluginInput, PluginResult } from '../base_plugin.ts';

/**
 * E-Hentai登录插件
 * 处理E-H/ExH认证Cookie管理
 */
class EHentaiLoginPlugin extends BasePlugin {
  getPluginInfo(): PluginInfo {
    return {
      name: "E-Hentai",
      type: "login",
      namespace: "ehlogin",
      author: "Difegue",
      version: "2.3",
      icon: "https://e-hentai.org/favicon.ico",
      description: "Handles login to E-H. If you have an account that can access fjorded content or exhentai, adding the credentials here will make more archives available for parsing.",
      parameters: [
        { name: "ipb_member_id", type: "string", desc: "ipb_member_id cookie" },
        { name: "ipb_pass_hash", type: "string", desc: "ipb_pass_hash cookie" },
        { name: "star", type: "string", desc: "star cookie (optional, if present you can view fjorded content without exhentai)" },
        { name: "igneous", type: "string", desc: "igneous cookie(optional, if present you can view exhentai without Europe and America IP)" }
      ],
      permissions: ["net=exhentai.org", "net=e-hentai.org", "net=forums.e-hentai.org"],
      update_url: "https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Login/EHentai.ts"
    };
  }

  protected async runPlugin(input: PluginInput): Promise<void> {
    try {
      this.reportProgress(10, '读取登录参数...');
      const params = this.getParams();

      this.reportProgress(30, '验证登录凭据...');
      const result = await this.doLogin(
        params.ipb_member_id || '',
        params.ipb_pass_hash || '',
        params.star || '',
        params.igneous || ''
      );

      this.reportProgress(100, '登录完成');
      this.outputResult(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });
    }
  }

  /**
   * 执行登录逻辑，返回用户代理配置
   */
  private async doLogin(
    ipb_member_id: string,
    ipb_pass_hash: string,
    star: string,
    igneous: string
  ): Promise<PluginResult> {
    try {
      if (!ipb_member_id || !ipb_pass_hash) {
        return {
          success: true,
          data: {
            cookies: [],
            message: "No cookies provided, returning blank UserAgent."
          }
        };
      }

      const cookies = this.buildCookies(ipb_member_id, ipb_pass_hash, star, igneous);

      // 验证cookies是否有效
      const validationResult = await this.validateCookies(cookies);

      if (!validationResult.success) {
        return validationResult;
      }

      return {
        success: true,
        data: {
          cookies,
          message: "Successfully configured E-Hentai authentication cookies."
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Login failed: ${errorMessage}` };
    }
  }

  /**
   * 构建Cookie列表
   */
  private buildCookies(
    ipb_member_id: string,
    ipb_pass_hash: string,
    star: string,
    igneous: string
  ): Array<{name: string, value: string, domain: string, path: string}> {
    const cookies = [];

    // E-Hentai和ExHentai的基础cookies
    const domains = ['e-hentai.org', 'exhentai.org'];

    for (const domain of domains) {
      // 认证cookies
      cookies.push({
        name: 'ipb_member_id',
        value: ipb_member_id,
        domain,
        path: '/'
      });

      cookies.push({
        name: 'ipb_pass_hash',
        value: ipb_pass_hash,
        domain,
        path: '/'
      });

      // 可选cookies
      if (star) {
        cookies.push({
          name: 'star',
          value: star,
          domain,
          path: '/'
        });
      }

      if (igneous) {
        cookies.push({
          name: 'igneous',
          value: igneous,
          domain,
          path: '/'
        });
      }
    }

    // Forums cookie
    cookies.push({
      name: 'ipb_coppa',
      value: '0',
      domain: 'forums.e-hentai.org',
      path: '/'
    });

    // 跳过警告页面的cookies
    cookies.push({
      name: 'nw',
      value: '1',
      domain: 'exhentai.org',
      path: '/'
    });

    cookies.push({
      name: 'nw',
      value: '1',
      domain: 'e-hentai.org',
      path: '/'
    });

    return cookies;
  }

  /**
   * 验证cookies是否有效
   */
  private async validateCookies(cookies: Array<{name: string, value: string, domain: string, path: string}>): Promise<PluginResult> {
    try {
      // 构建Cookie header
      const cookieString = cookies
        .filter(cookie => cookie.domain === 'exhentai.org')
        .map(cookie => `${cookie.name}=${cookie.value}`)
        .join('; ');

      // 测试ExHentai访问
      const response = await fetch('https://exhentai.org', {
        headers: {
          'Cookie': cookieString,
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
      });

      if (!response.ok) {
        return { success: false, error: `HTTP ${response.status}: Failed to access ExHentai` };
      }

      const html = await response.text();

      // 检查是否需要登录
      if (html.includes('You need to be logged in to view this page.')) {
        return { success: false, error: 'Invalid E*Hentai login credentials.' };
      }

      return { success: true };
    } catch (error) {
      // 如果网络检查失败，仍然返回成功，因为cookies可能是正确的
      const errorMessage = error instanceof Error ? error.message : String(error);
      return {
        success: true,
        data: {
          warning: `Could not validate cookies: ${errorMessage}. Assuming they are correct.`
        }
      };
    }
  }
}

// 运行插件
if (import.meta.main) {
  const plugin = new EHentaiLoginPlugin();
  await plugin.handleCommand();
}
