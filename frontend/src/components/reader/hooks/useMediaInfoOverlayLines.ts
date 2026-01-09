/* eslint-disable react-hooks/refs */
import { useMemo, useRef } from 'react';
import type { PageInfo } from '@/lib/archive-service';
import {
  formatKiB,
  formatMiB,
  formatMs,
  formatPercent,
  formatSeconds,
  getApproxResourceBytes,
  getImageFormatLabel,
  getLastPathSegment,
  getLatestResourceTiming,
} from '@/components/reader/utils/media-info';

type ReadingMode = 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';

export function useMediaInfoOverlayLines({
  enabled,
  tick,
  pages,
  currentPage,
  readingMode,
  doublePageMode,
  splitCoverMode,
  cachedPages,
  htmlContents,
  scale,
  translateX,
  translateY,
  isFullscreen,
  showToolbar,
  sidebarOpen,
  autoHideEnabled,
  tapTurnPageEnabled,
  doubleTapZoom,
  autoPlayMode,
  autoPlayInterval,
  imagesLoading,
  loadedImages,
  visibleRange,
  imageRefs,
  videoRefs,
  htmlContainerRefs,
  imageRequestUrls,
}: {
  enabled: boolean;
  tick: number;
  pages: PageInfo[];
  currentPage: number;
  readingMode: ReadingMode;
  doublePageMode: boolean;
  splitCoverMode: boolean;
  cachedPages: string[];
  htmlContents: Record<number, string>;
  scale: number;
  translateX: number;
  translateY: number;
  isFullscreen: boolean;
  showToolbar: boolean;
  sidebarOpen: boolean;
  autoHideEnabled: boolean;
  tapTurnPageEnabled: boolean;
  doubleTapZoom: boolean;
  autoPlayMode: boolean;
  autoPlayInterval: number;
  imagesLoading: Set<number>;
  loadedImages: Set<number>;
  visibleRange: { start: number; end: number };
  imageRefs: React.MutableRefObject<(HTMLImageElement | null)[]>;
  videoRefs: React.MutableRefObject<(HTMLVideoElement | null)[]>;
  htmlContainerRefs: React.MutableRefObject<(HTMLDivElement | null)[]>;
  imageRequestUrls: React.MutableRefObject<(string | null)[]>;
}) {
  const htmlTitleCacheRef = useRef<Record<number, { len: number; title: string | null }>>({});

  return useMemo(() => {
    if (!enabled) return [];
    void tick;
    const page = pages[currentPage];
    if (!page) return [];

    const showSecondPage =
      readingMode !== 'webtoon' &&
      doublePageMode &&
      !(splitCoverMode && currentPage === 0) &&
      currentPage + 1 < pages.length;

    const indices = showSecondPage ? [currentPage, currentPage + 1] : [currentPage];

    const readImageInfo = (index: number) => {
      const element = imageRefs.current[index];
      if (!element) return null;
      const rect = element.getBoundingClientRect();
      const resourceUrl = imageRequestUrls.current[index] || element.currentSrc || element.src;
      const timing = getLatestResourceTiming(resourceUrl);
      return {
        naturalWidth: element.naturalWidth,
        naturalHeight: element.naturalHeight,
        displayedWidth: Math.round(rect.width),
        displayedHeight: Math.round(rect.height),
        bytes: getApproxResourceBytes(resourceUrl),
        transferSize: timing?.transferSize ?? null,
        duration: timing ? timing.responseEnd - timing.startTime : null,
        protocol: (timing as any)?.nextHopProtocol ? String((timing as any).nextHopProtocol) : null,
        format: getImageFormatLabel(resourceUrl),
        resourceUrl,
      };
    };

    const readVideoInfo = (index: number) => {
      const element = videoRefs.current[index];
      if (!element) return null;
      const timing = getLatestResourceTiming(element.currentSrc || element.src);
      const buffered = element.buffered;
      const bufferedEnd = buffered && buffered.length > 0 ? buffered.end(buffered.length - 1) : 0;
      return {
        videoWidth: element.videoWidth,
        videoHeight: element.videoHeight,
        duration: element.duration,
        currentTime: element.currentTime,
        playbackRate: element.playbackRate,
        muted: element.muted,
        volume: element.volume,
        paused: element.paused,
        readyState: element.readyState,
        bufferedEnd,
        transferSize: timing?.transferSize ?? null,
        durationMs: timing ? timing.responseEnd - timing.startTime : null,
        protocol: (timing as any)?.nextHopProtocol ? String((timing as any).nextHopProtocol) : null,
      };
    };

    const readHtmlInfo = (index: number) => {
      const html = htmlContents[index] || '';
      const cached = htmlTitleCacheRef.current[index];
      let title: string | null = cached?.len === html.length ? cached.title : null;
      if (!cached || cached.len !== html.length) {
        if (html) {
          try {
            const parsed = new DOMParser().parseFromString(html, 'text/html');
            title = parsed.querySelector('title')?.textContent?.trim() || null;
          } catch {
            title = null;
          }
        }
        htmlTitleCacheRef.current[index] = { len: html.length, title };
      }
      const container = htmlContainerRefs.current[index];
      const scrollable = readingMode !== 'webtoon' && container && container.scrollHeight > container.clientHeight;
      return {
        title,
        length: html.length,
        scrollTop: container ? Math.round(container.scrollTop) : null,
        scrollHeight: container ? Math.round(container.scrollHeight) : null,
        clientHeight: container ? Math.round(container.clientHeight) : null,
        scrollable,
      };
    };

    const joinPairs = (...pairs: Array<[string, string]>) => pairs.map(([k, v]) => `${k}  ${v}`).join('  ');

    const lines: string[] = [];
    const headerIndexLabel = indices.length === 2 ? `${indices[0] + 1}-${indices[1] + 1}` : `${indices[0] + 1}`;
    const viewport = typeof window !== 'undefined' ? `${window.innerWidth}x${window.innerHeight}` : '--';
    const dpr = typeof window !== 'undefined' ? window.devicePixelRatio : 1;

    lines.push(`P ${headerIndexLabel}/${pages.length}  ${readingMode}${doublePageMode ? '  double' : ''}`);
    lines.push(
      `ui ${joinPairs(
        ['toolbar', showToolbar ? 'on' : 'off'],
        ['sidebar', sidebarOpen ? 'on' : 'off'],
        ['fullscreen', isFullscreen ? 'on' : 'off']
      )}`
    );
    lines.push(
      `cfg ${joinPairs(
        ['autoHide', autoHideEnabled ? 'on' : 'off'],
        ['tapTurn', tapTurnPageEnabled ? 'on' : 'off'],
        ['dblTapZoom', doubleTapZoom ? 'on' : 'off']
      )}`
    );
    lines.push(
      `cfg ${joinPairs(
        ['splitCover', splitCoverMode ? 'on' : 'off'],
        ['autoPlay', autoPlayMode ? `${autoPlayInterval}s` : 'off']
      )}`
    );
    lines.push(
      `env ${joinPairs(
        ['vp', viewport],
        ['dpr', String(dpr)],
        ['zoom', `${scale.toFixed(2)}x`],
        ['pan', `${Math.round(translateX)}/${Math.round(translateY)}`]
      )}`
    );
    lines.push(
      `load ${joinPairs(
        ['loaded', `${loadedImages.size}/${pages.length}`],
        ['queue', String(imagesLoading.size)],
        ['webtoon', `${visibleRange.start + 1}-${visibleRange.end + 1}`]
      )}`
    );

    indices.forEach((index, idx) => {
      const p = pages[index];
      if (!p) return;
      const prefix = indices.length === 2 ? `#${idx + 1} ` : '';
      const src = p.type === 'image' ? cachedPages[index] || p.url : p.url;
      const cached = p.type === 'image' ? Boolean(cachedPages[index]) : false;
      const state = loadedImages.has(index) ? 'loaded' : imagesLoading.has(index) ? 'loading' : 'idle';
      lines.push(`${prefix}${p.type}  ${getLastPathSegment(src)}  ${state}${cached ? '  cached' : ''}`);

      if (p.type === 'video') {
        const info = readVideoInfo(index);
        if (info) {
          const time = `${formatSeconds(info.currentTime)}/${formatSeconds(info.duration)}`;
          const bufferedPct =
            info.duration > 0 ? formatPercent(Math.min(1, Math.max(0, info.bufferedEnd / info.duration))) : '--%';
          lines.push(`${prefix}${joinPairs(['dim', `${info.videoWidth}x${info.videoHeight}`], ['t', time], ['buf', bufferedPct])}`);
          lines.push(
            `${prefix}${joinPairs(
              ['state', info.paused ? 'paused' : 'playing'],
              ['rate', `${info.playbackRate.toFixed(2)}x`],
              ['vol', formatPercent(info.muted ? 0 : info.volume)],
              ['ready', String(info.readyState)]
            )}`
          );
          lines.push(
            `${prefix}${joinPairs(
              ['xfer', formatKiB(info.transferSize)],
              ['dl', formatMs(info.durationMs)],
              ['proto', info.protocol || '--']
            )}`
          );
        }
      } else if (p.type === 'html') {
        const info = readHtmlInfo(index);
        if (info.title) lines.push(`${prefix}${joinPairs(['title', info.title])}`);
        if (info.scrollable && info.scrollTop !== null && info.scrollHeight !== null && info.clientHeight !== null) {
          lines.push(`${prefix}${joinPairs(['scroll', `${info.scrollTop}/${info.scrollHeight - info.clientHeight}`])}`);
        } else if (info.length) {
          lines.push(`${prefix}${joinPairs(['len', String(info.length)])}`);
        }
      } else {
        const info = readImageInfo(index);
        if (info) {
          lines.push(
            `${prefix}${joinPairs(
              ['dim', `${info.naturalWidth}x${info.naturalHeight}`],
              ['disp', `${info.displayedWidth}x${info.displayedHeight}`]
            )}`
          );
          lines.push(`${prefix}${joinPairs(['fmt', info.format || '--'])}`);
          lines.push(
            `${prefix}${joinPairs(['size', formatMiB(info.bytes)], ['xfer', formatKiB(info.transferSize)], ['dl', formatMs(info.duration)])}`
          );
          lines.push(`${prefix}${joinPairs(['src', getLastPathSegment(info.resourceUrl)])}`);
          if (info.protocol) lines.push(`${prefix}${joinPairs(['proto', info.protocol])}`);
        }
      }
    });

    return lines;
  }, [
    enabled,
    tick,
    pages,
    currentPage,
    readingMode,
    doublePageMode,
    splitCoverMode,
    cachedPages,
    htmlContents,
    scale,
    translateX,
    translateY,
    isFullscreen,
    showToolbar,
    sidebarOpen,
    autoHideEnabled,
    tapTurnPageEnabled,
    doubleTapZoom,
    autoPlayMode,
    autoPlayInterval,
    imagesLoading,
    loadedImages,
    visibleRange.start,
    visibleRange.end,
    htmlContainerRefs,
    imageRefs,
    imageRequestUrls,
    videoRefs,
  ]);
}
