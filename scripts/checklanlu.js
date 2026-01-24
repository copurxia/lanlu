// ==UserScript==
// @name        ExHentai Lanlu Checker 1.6
// @namespace   https://github.com/Putarku
// @match       https://exhentai.org/*
// @match       https://e-hentai.org/*
// @grant       GM_xmlhttpRequest
// @grant       GM_addStyle
// @grant       GM_getValue
// @grant       GM_setValue
// @grant       GM_registerMenuCommand
// @connect     *
// @license MIT
// @version     1.6
// @author      Putarku
// @description Checks if galleries on ExHentai/E-Hentai are already in your Lanraragi library and marks them by inserting a span at the beginning of the title.
// ==/UserScript==

(async function() {
    'use strict';

    // --- 配置（油猴菜单）---
    const DEFAULT_SETTINGS = {
        serverUrl: 'http://localhost:3005',
        apiKey: 'lanlu',
        maxConcurrentRequests: 5,
        cacheDurationMs: 60 * 60 * 1000, // 1h
    };

    async function gmGetValue(key, defaultValue) {
        try {
            const v = GM_getValue(key, defaultValue);
            return (v && typeof v.then === 'function') ? await v : v;
        } catch {
            return defaultValue;
        }
    }

    async function gmSetValue(key, value) {
        try {
            const v = GM_setValue(key, value);
            if (v && typeof v.then === 'function') await v;
        } catch {
            // ignore
        }
    }

    function parsePositiveInt(v, fallback) {
        const n = typeof v === 'number' ? v : parseInt(String(v ?? ''), 10);
        return Number.isFinite(n) && n > 0 ? n : fallback;
    }

    async function loadSettings() {
        const serverUrl = String(await gmGetValue('lanlu.serverUrl', DEFAULT_SETTINGS.serverUrl) || '').trim();
        const apiKey = String(await gmGetValue('lanlu.apiKey', DEFAULT_SETTINGS.apiKey) || '').trim();
        const maxConcurrentRequests = parsePositiveInt(
            await gmGetValue('lanlu.maxConcurrentRequests', DEFAULT_SETTINGS.maxConcurrentRequests),
            DEFAULT_SETTINGS.maxConcurrentRequests
        );
        const cacheDurationMs = parsePositiveInt(
            await gmGetValue('lanlu.cacheDurationMs', DEFAULT_SETTINGS.cacheDurationMs),
            DEFAULT_SETTINGS.cacheDurationMs
        );
        return { serverUrl, apiKey, maxConcurrentRequests, cacheDurationMs };
    }

    async function configureSettings() {
        const current = await loadSettings();
        const serverUrl = prompt('Lanlu Checker - SERVER_URL（不要以 / 结尾）', current.serverUrl);
        if (serverUrl === null) return;
        const apiKey = prompt('Lanlu Checker - API_KEY（Bearer token，可留空）', current.apiKey);
        if (apiKey === null) return;
        const maxConcurrent = prompt('Lanlu Checker - 最大并发请求数', String(current.maxConcurrentRequests));
        if (maxConcurrent === null) return;
        const cacheMs = prompt('Lanlu Checker - 缓存时长（毫秒）', String(current.cacheDurationMs));
        if (cacheMs === null) return;

        await gmSetValue('lanlu.serverUrl', String(serverUrl).trim());
        await gmSetValue('lanlu.apiKey', String(apiKey).trim());
        await gmSetValue('lanlu.maxConcurrentRequests', parsePositiveInt(maxConcurrent, current.maxConcurrentRequests));
        await gmSetValue('lanlu.cacheDurationMs', parsePositiveInt(cacheMs, current.cacheDurationMs));

        // 直接刷新，让新配置立即生效。
        try { location.reload(); } catch { /* ignore */ }
    }

    try {
        GM_registerMenuCommand('Lanlu Checker: 设置', () => { void configureSettings(); });
        GM_registerMenuCommand('Lanlu Checker: 清空本页缓存', () => {
            try {
                for (let i = 0; i < localStorage.length; i++) {
                    const k = localStorage.key(i);
                    if (k && k.startsWith('lanlu-checker-')) {
                        localStorage.removeItem(k);
                        i--;
                    }
                }
                alert('Lanlu Checker: 已清空缓存（请刷新页面）');
            } catch {
                alert('Lanlu Checker: 清空缓存失败');
            }
        });
    } catch {
        // ignore (some managers may not support menu commands)
    }

    const SETTINGS = await loadSettings();
    const MAX_CONCURRENT_REQUESTS = SETTINGS.maxConcurrentRequests;

    GM_addStyle(`
        .lanlu-marker-span {
            font-weight: bold;
            border-radius: 3px;
            padding: 0px 3px;
            margin-right: 4px; /* 与 visied.js 的 ● 标记或标题文本的间距 */
            font-size: 0.9em;
            cursor: default;
            user-select: none;
        }

        .lanlu-marker-downloaded {
            color: #28a745; /* 绿色 */
            background-color: #49995d;
        }

        .lanlu-marker-notfound {
            color: #6b7280; /* 灰色 */
            background-color: #e5e7eb;
        }

        .lanlu-marker-error {
            color: #dc3545; /* 红色 */
            background-color: #fbe9ea;
        }
    `);

    function normalizeServerUrl(input) {
        const v = (input || '').trim();
        return v.endsWith('/') ? v.slice(0, -1) : v;
    }

    const SERVER_URL = normalizeServerUrl(SETTINGS.serverUrl);

    const CACHE_DURATION = SETTINGS.cacheDurationMs;
    const CLEANUP_INTERVAL = 7 * 24 * 60 * 60 * 1000; // 7 days cleanup interval

    function getCacheWithDuration(key, durationMs) {
        const cached = localStorage.getItem(key);
        if (!cached) return null;
        try {
            const parsed = JSON.parse(cached);
            const timestamp = parsed && typeof parsed.timestamp === 'number' ? parsed.timestamp : 0;
            const data = parsed ? parsed.data : null;
            if (timestamp > 0 && (Date.now() - timestamp) < durationMs) {
                return data;
            }
        } catch {
            return null;
        }
        return null;
    }

    function getCache(key) {
        return getCacheWithDuration(key, CACHE_DURATION);
    }

    function setCache(key, data) {
        const item = {
            timestamp: Date.now(),
            data: data
        };
        localStorage.setItem(key, JSON.stringify(item));
    }

    // 清理过期缓存
    function cleanupExpiredCache() {
        const lastCleanup = localStorage.getItem('lanlu-cache-last-cleanup');
        const currentTime = Date.now();

        // 如果距离上次清理超过7天，执行清理
        if (!lastCleanup || (currentTime - parseInt(lastCleanup)) > CLEANUP_INTERVAL) {
            console.log('[Lanlu Checker] Starting cache cleanup...');
            let removedCount = 0;

            for (let i = 0; i < localStorage.length; i++) {
                const key = localStorage.key(i);
                if (key && key.startsWith('lanlu-checker-')) {
                    try {
                        const item = localStorage.getItem(key);
                        if (item) {
                            const cacheData = JSON.parse(item);
                            if (currentTime - cacheData.timestamp > CACHE_DURATION) {
                                localStorage.removeItem(key);
                                removedCount++;
                                i--; // 因为删除后数组长度变化
                            }
                        }
                    } catch (e) {
                        console.error(`[Lanlu Checker] Error cleaning up cache key ${key}:`, e);
                    }
                }
            }

            localStorage.setItem('lanlu-cache-last-cleanup', currentTime.toString());
            console.log(`[Lanlu Checker] Cache cleanup completed. Removed ${removedCount} expired items.`);
        }
    }

    // 将GM_xmlhttpRequest包装为Promise
    function makeRequest(options) {
        return new Promise((resolve, reject) => {
            GM_xmlhttpRequest({
                method: options.method,
                url: options.url,
                headers: options.headers,
                data: options.data,
                onload: function(response) {
                    resolve(response);
                },
                onerror: function(error) {
                    reject(error);
                }
            });
        });
    }

    // 限制并发请求数量的函数
    async function processInBatches(items, processFn, batchSize) {
        const results = [];
        for (let i = 0; i < items.length; i += batchSize) {
            const batch = items.slice(i, i + batchSize);
            const batchPromises = batch.map(processFn);
            const batchResults = await Promise.all(batchPromises);
            results.push(...batchResults);
        }
        return results;
    }

    function getAuthHeaders() {
        const headers = {};
        if (SETTINGS.apiKey) {
            headers['Authorization'] = `Bearer ${SETTINGS.apiKey}`;
        }
        return headers;
    }

    function safeJsonParse(text) {
        if (typeof text !== 'string') return null;
        try {
            return text ? JSON.parse(text) : null;
        } catch {
            return null;
        }
    }

    function getSourceSearchCandidates(input) {
        // 与 extension/public/background.js 的逻辑保持一致：同一个 URL 生成多种候选，覆盖历史/非规范化的 source tag。
        try {
            const url = new URL(input);
            const base = `${url.protocol}//${url.host}${url.pathname}${url.search}`;
            const trimmed = base.endsWith('/') ? base.slice(0, -1) : base;

            const candidates = [base];
            if (trimmed !== base) candidates.push(trimmed);

            const withoutProtocol = `${url.host}${url.pathname}${url.search}`;
            const withoutProtocolTrimmed = withoutProtocol.endsWith('/') ? withoutProtocol.slice(0, -1) : withoutProtocol;
            if (!candidates.includes(withoutProtocol)) candidates.push(withoutProtocol);
            if (!candidates.includes(withoutProtocolTrimmed) && withoutProtocolTrimmed !== withoutProtocol) {
                candidates.push(withoutProtocolTrimmed);
            }
            return candidates;
        } catch {
            return [];
        }
    }

    async function searchArchives(filter, count = 1) {
        const params = new URLSearchParams();
        params.set('filter', filter);
        params.set('start', '0');
        params.set('count', String(count));
        const url = `${SERVER_URL}/api/search?${params.toString()}`;
        const response = await makeRequest({
            method: 'GET',
            url,
            headers: getAuthHeaders()
        });
        const data = safeJsonParse(response.responseText);
        return data && typeof data === 'object' ? data : {};
    }

    // 收集需要查询的画廊信息
    const galleryLinks = document.querySelectorAll('.itg .gl1t a[href*="/g/"]');
    const galleriesToCheck = [];

    galleryLinks.forEach(linkElement => {
        const galleryUrl = linkElement.href;
        const titleElement = linkElement.querySelector('.glink');

        if (!galleryUrl || !titleElement) {
            return;
        }

        if (titleElement.querySelector('.lanlu-marker-span')) {
            return;
        }

        const cacheKey = `lanlu-checker-${galleryUrl}`;
        const cachedData = getCache(cacheKey);

        if (cachedData) {
            console.log(`[Lanlu Checker] Using cached data for: ${galleryUrl}`);
            handleResponse(cachedData, titleElement, galleryUrl);
            return;
        }

        galleriesToCheck.push({
            galleryUrl,
            titleElement,
            cacheKey
        });
    });

    // 处理单个画廊的查询
    async function processGallery(gallery) {
        const { galleryUrl, titleElement, cacheKey } = gallery;

        try {
            // 参考 extension：优先用 source:URL tag 查找是否已存在
            const candidates = getSourceSearchCandidates(galleryUrl);
            let hit = null;

            // 1) exact token match: source:<candidate>$
            for (const candidate of candidates) {
                const resp = await searchArchives(`source:${candidate}$`, 1);
                const item = resp && Array.isArray(resp.data) ? resp.data[0] : null;
                if (item && typeof item.arcid === 'string') {
                    hit = { candidate, item, mode: 'exact' };
                    break;
                }
            }

            const result = hit
                ? { success: 1, data: { arcid: hit.item.arcid, title: hit.item.title, tags: hit.item.tags } }
                : { success: 0, error: 'not_saved' };

            setCache(cacheKey, result);
            handleResponse(result, titleElement, galleryUrl);
            return { success: true, galleryUrl, saved: !!hit };
        } catch (error) {
            console.error(`[Lanlu Checker] Network error checking ${galleryUrl}:`, error);
            let markerSpan = document.createElement('span');
            markerSpan.classList.add('lanlu-marker-span', 'lanlu-marker-error');
            markerSpan.textContent = '(Lanlu ❓)';
            if (titleElement) titleElement.prepend(markerSpan);
            return { success: false, galleryUrl, error };
        }
    }

    // 执行缓存清理
    cleanupExpiredCache();

    // 并行处理所有画廊查询，限制并发数
    if (galleriesToCheck.length > 0) {
        console.log(`[Lanlu Checker] Processing ${galleriesToCheck.length} galleries in parallel batches`);
        processInBatches(galleriesToCheck, processGallery, MAX_CONCURRENT_REQUESTS)
            .then(results => {
                console.log(`[Lanlu Checker] Completed all gallery checks. Success: ${results.filter(r => r.success).length}, Failed: ${results.filter(r => !r.success).length}`);
            })
            .catch(error => {
                console.error(`[Lanlu Checker] Error in batch processing:`, error);
            });
    }

    function handleResponse(result, titleElement, galleryUrl) {
        if (!titleElement) return;

        let markerSpan = document.createElement('span');
        markerSpan.classList.add('lanlu-marker-span');

        if (result.success === 1) {
            console.log(`[Lanlu Checker] Found: ${galleryUrl} (ARCID: ${result.data && result.data.arcid})`);
            markerSpan.textContent = '(Lanlu ✔)';
            markerSpan.classList.add('lanlu-marker-downloaded');
            titleElement.prepend(markerSpan);
        } else {
            console.log(`[Lanlu Checker] Not found or error: ${galleryUrl} - ${result.error}`);
            // 未找到：仅标记，不提供下载/入队功能
            markerSpan.textContent = '(Lanlu ?)';
            markerSpan.classList.add('lanlu-marker-notfound');
            titleElement.prepend(markerSpan);
        }
    }
})();
