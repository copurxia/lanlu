/**
 * Lanlu HTTP API 客户端
 *
 * 使用 Node.js 内置 fetch (Node 18+)
 */

export class LanluApiClient {
  #host;
  #token;
  #noProxy;

  constructor({ host, token, noProxy = false }) {
    this.#host = host.replace(/\/+$/, '');
    this.#token = token;
    this.#noProxy = noProxy;
  }

  /**
   * 构建 fetch 选项
   */
  #fetchOpts(extra = {}) {
    const opts = {
      headers: {},
      ...extra,
    };

    // no-proxy 支持
    if (this.#noProxy) {
      opts.headers['X-No-Proxy'] = '1';
    }

    return opts;
  }

  /**
   * 执行 HTTP 请求
   */
  /**
   * 获取服务端地址
   */
  getHost() {
    return this.#host;
  }

  async #request(method, path, { query, body, headers, bodyType } = {}) {
    let url = this.#buildUrl(path, query);

    const opts = this.#fetchOpts({ method });
    opts.headers['Authorization'] = `Bearer ${this.#token}`;
    opts.headers['Accept'] = 'application/json';

    if (body !== undefined) {
      if (bodyType === 'bytes' || body instanceof Uint8Array) {
        opts.body = body;
        opts.headers['Content-Type'] = 'application/octet-stream';
      } else {
        opts.body = String(body);
        opts.headers['Content-Type'] = 'application/json';
      }
    }

    if (headers) {
      Object.assign(opts.headers, headers);
    }

    let resp;
    try {
      resp = await fetch(url, opts);
    } catch (e) {
      throw new Error(`HTTP request failed: ${e.message}`);
    }

    const respBody = await resp.text();

    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${respBody}`);
    }

    return respBody;
  }

  /**
   * GET 请求
   */
  async get(path, query = {}) {
    return await this.#request('GET', path, { query });
  }

  /**
   * POST 请求（JSON body）
   */
  async post(path, body = '') {
    return await this.#request('POST', path, { body });
  }

  /**
   * PUT 请求（二进制 body）
   */
  async putBytes(path, query, body) {
    return await this.#request('PUT', path, { query, body, bodyType: 'bytes' });
  }

  /**
   * PUT 请求（JSON body）
   */
  async put(path, body = '') {
    return await this.#request('PUT', path, { body });
  }

  #buildUrl(path, query = {}) {
    const url = `${this.#host}${path.startsWith('/') ? path : '/' + path}`;
    const qs = buildQuery(query);
    return qs ? `${url}?${qs}` : url;
  }
}

// 循环引用避免：json_utils 被其他模块引用，这里只 import 内部函数
import { buildQuery } from './json_utils.mjs';
