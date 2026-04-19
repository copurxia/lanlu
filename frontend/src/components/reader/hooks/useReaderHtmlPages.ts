'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import type { PageInfo } from '@/lib/services/archive-service';
import { ArchiveService } from '@/lib/services/archive-service';
import { logger } from '@/lib/utils/logger';

const MAX_RETRIES = 5;
const BASE_RETRY_DELAY_MS = 500;
const MAX_RETRY_DELAY_MS = 15000;

function getRetryDelayMs(attempt: number) {
  const exp = Math.min(attempt - 1, 10);
  const base = Math.min(MAX_RETRY_DELAY_MS, BASE_RETRY_DELAY_MS * Math.pow(2, exp));
  const jitter = Math.random() * 0.2 + 0.9; // 0.9x ~ 1.1x
  return Math.round(base * jitter);
}

export function useReaderHtmlPages({
  id,
  pages,
  onError,
}: {
  id: string | null;
  pages: PageInfo[];
  onError: (message: string) => void;
}) {
  const [htmlContents, setHtmlContents] = useState<Record<number, string>>({});
  const htmlContentsRef = useRef<Record<number, string>>({});
  const htmlLoadingRef = useRef<Set<number>>(new Set());
  const retryStateRef = useRef<Map<number, { attempts: number; nextRetryAt: number }>>(new Map());
  const retryTimersRef = useRef<Map<number, ReturnType<typeof setTimeout>>>(new Map());
  const mountedRef = useRef(true);

  const loadHtmlPage = useCallback(
    async function loadHtmlPageInternal(pageIndex: number) {
      const page = pages[pageIndex];
      if (!page || page.type !== 'html') return;
      const pageArchiveId = ((page as { archiveId?: string }).archiveId || id || '').trim();
      const pagePath = ArchiveService.getPagePath(page);
      if (!pageArchiveId) return;
      if (!pagePath) return;
      if (htmlContentsRef.current[pageIndex]) return;
      if (htmlLoadingRef.current.has(pageIndex)) return;

      const now = Date.now();
      const retryState = retryStateRef.current.get(pageIndex);
      if (retryState) {
        if (retryState.attempts >= MAX_RETRIES) return;
        if (now < retryState.nextRetryAt) return;
      }

      htmlLoadingRef.current.add(pageIndex);
      try {
        const pageUrl = ArchiveService.addTokenToUrl(ArchiveService.getPageUrl(pageArchiveId, pagePath));
        const response = await fetch(pageUrl);
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        const html = await response.text();

        const slashIndex = pagePath.lastIndexOf('/');
        const currentDir = slashIndex >= 0 ? pagePath.substring(0, slashIndex) : '';

        let processedHtml = html;

        processedHtml = processedHtml.replace(
          /(src|href)=["'](?!http|https|data:|mailto:|tel:)([^"']+)["']/gi,
          (match, attr, relativePath) => {
            if (!relativePath.startsWith('/') && !relativePath.startsWith('data:')) {
              const fullPath = currentDir ? `${currentDir}/${relativePath}` : relativePath;
              const apiPath = ArchiveService.addTokenToUrl(ArchiveService.getPageUrl(pageArchiveId, fullPath));
              return `${attr}="${apiPath}"`;
            }
            return match;
          }
        );

        processedHtml = processedHtml.replace(
          /url\((?!['"]?(?:http|https|data:))([^'")]+)\)/gi,
          (match, relativePath) => {
            relativePath = relativePath.replace(/['"]/g, '');
            if (!relativePath.startsWith('/') && !relativePath.startsWith('data:')) {
              const fullPath = currentDir ? `${currentDir}/${relativePath}` : relativePath;
              const apiPath = ArchiveService.addTokenToUrl(ArchiveService.getPageUrl(pageArchiveId, fullPath));
              return `url(${apiPath})`;
            }
            return match;
          }
        );

        setHtmlContents((prev) => ({ ...prev, [pageIndex]: processedHtml }));
        retryStateRef.current.delete(pageIndex);
        const timerId = retryTimersRef.current.get(pageIndex);
        if (timerId) {
          clearTimeout(timerId);
          retryTimersRef.current.delete(pageIndex);
        }
      } catch (error) {
        logger.error('Failed to load HTML page', error);
        const prevState = retryStateRef.current.get(pageIndex);
        const attempts = (prevState?.attempts ?? 0) + 1;
        const delayMs = getRetryDelayMs(attempts);
        const nextRetryAt = Date.now() + delayMs;
        retryStateRef.current.set(pageIndex, { attempts, nextRetryAt });

        if (attempts === 1 || attempts >= MAX_RETRIES) {
          onError('Failed to load HTML content');
        }

        if (attempts < MAX_RETRIES) {
          const existingTimerId = retryTimersRef.current.get(pageIndex);
          if (existingTimerId) clearTimeout(existingTimerId);
          const timerId = setTimeout(() => {
            retryTimersRef.current.delete(pageIndex);
            if (!mountedRef.current) return;
            if (htmlContentsRef.current[pageIndex]) return;
            void loadHtmlPageInternal(pageIndex);
          }, delayMs);
          retryTimersRef.current.set(pageIndex, timerId);
        }
      } finally {
        htmlLoadingRef.current.delete(pageIndex);
      }
    },
    [id, pages, onError]
  );

  useEffect(() => {
    htmlContentsRef.current = htmlContents;
  }, [htmlContents]);

  useEffect(() => {
    mountedRef.current = true;
    const retryTimers = retryTimersRef.current;
    return () => {
      mountedRef.current = false;
      retryTimers.forEach((timerId) => clearTimeout(timerId));
      retryTimers.clear();
    };
  }, []);

  useEffect(() => {
    setHtmlContents({});
    htmlContentsRef.current = {};
    htmlLoadingRef.current.clear();
    retryStateRef.current.clear();
    retryTimersRef.current.forEach((timerId) => clearTimeout(timerId));
    retryTimersRef.current.clear();
  }, [id]);

  useEffect(() => {
    if (pages.length === 0) {
      retryStateRef.current.clear();
      retryTimersRef.current.forEach((timerId) => clearTimeout(timerId));
      retryTimersRef.current.clear();
      return;
    }

    retryStateRef.current.forEach((_, index) => {
      if (index >= pages.length) retryStateRef.current.delete(index);
    });
    retryTimersRef.current.forEach((timerId, index) => {
      if (index >= pages.length) {
        clearTimeout(timerId);
        retryTimersRef.current.delete(index);
      }
    });
  }, [pages.length]);

  return { htmlContents, loadHtmlPage } as const;
}
