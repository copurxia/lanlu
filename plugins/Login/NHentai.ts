#!/usr/bin/env deno run --allow-net --allow-read

import { BasePlugin, PluginInfo, PluginInput, PluginResult } from '../base_plugin.ts';

/**
 * nhentai 登录插件
 * 处理 nhentai 认证 Cookie 管理（主要用于绕过 Cloudflare）
 */
class NHentaiLoginPlugin extends BasePlugin {
  getPluginInfo(): PluginInfo {
    return {
      name: "nhentai",
      type: "login",
      namespace: "nhlogin",
      author: "Minimax M2.1",
      version: "1.0",
      description: "Handles login cookies for nhentai. Required for bypassing Cloudflare protection.",
      parameters: [
        { name: "cf_clearance", type: "string", desc: "cf_clearance cookie from browser (required for Cloudflare bypass)" },
        { name: "csrftoken", type: "string", desc: "csrftoken cookie (optional)" }
      ],
      permissions: ["net=nhentai.net"],
      update_url: "https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Login/NHentai.ts"
    };
  }

  protected async runPlugin(_: PluginInput): Promise<void> {
    try {
      this.reportProgress(10, '读取登录参数...');
      const params = this.getParams();

      const result = await this.doLogin(
        (params.cf_clearance as string) || '',
        (params.csrftoken as string) || ''
      );

      this.reportProgress(100, '登录完成');
      this.outputResult(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });
    }
  }

  /**
   * 执行登录逻辑，返回 Cookie 配置
   */
  private async doLogin(
    cf_clearance: string,
    csrftoken: string
  ): Promise<PluginResult> {
    try {
      if (!cf_clearance) {
        return {
          success: true,
          data: {
            cookies: [],
            message: "No cookies provided, returning blank configuration. Note: nhentai may require Cloudflare cookies to access."
          }
        };
      }

      const cookies = this.buildCookies(cf_clearance, csrftoken);

      // 验证 cookies 是否有效
      const validationResult = await this.validateCookies(cookies);

      if (!validationResult.success) {
        return validationResult;
      }

      return {
        success: true,
        data: {
          cookies,
          message: "Successfully configured nhentai authentication cookies."
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Login failed: ${errorMessage}` };
    }
  }

  /**
   * 构建 Cookie 列表
   */
  private buildCookies(
    cf_clearance: string,
    csrftoken: string
  ): Array<{ name: string; value: string; domain: string; path: string }> {
    const cookies: Array<{ name: string; value: string; domain: string; path: string }> = [];
    const domain = 'nhentai.net';

    // Cloudflare 认证 cookie
    if (cf_clearance) {
      cookies.push({
        name: 'cf_clearance',
        value: cf_clearance,
        domain,
        path: '/'
      });
    }

    // CSRF token cookie
    if (csrftoken) {
      cookies.push({
        name: 'csrftoken',
        value: csrftoken,
        domain,
        path: '/'
      });
    }

    return cookies;
  }

  /**
   * 验证 cookies 是否有效
   */
  private async validateCookies(
    cookies: Array<{ name: string; value: string; domain: string; path: string }>
  ): Promise<PluginResult> {
    try {
      // 构建 Cookie header
      const cookieString = cookies
        .map(cookie => `${cookie.name}=${cookie.value}`)
        .join('; ');

      // 测试 nhentai 访问
      const response = await fetch('https://nhentai.net/', {
        headers: {
          'Cookie': cookieString,
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        }
      });

      if (!response.ok) {
        return { success: false, error: `HTTP ${response.status}: Failed to access nhentai` };
      }

      const html = await response.text();

      // 检查是否被 Cloudflare 拦截
      if (html.includes('Just a moment...') || html.includes('Checking your browser')) {
        return { success: false, error: 'Cloudflare protection detected. Please update your cf_clearance cookie.' };
      }

      return { success: true };
    } catch (error) {
      // 如果网络检查失败，仍然返回成功，因为 cookies 可能是正确的
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
  const plugin = new NHentaiLoginPlugin();
  await plugin.handleCommand();
}
