'use client';

import React, { useEffect, useRef, useState } from 'react';

/**
 * 侧栏缩略图。
 *
 * 阅读器页面的 metadata 通常没有预生成缩略图（thumb_asset_id=0），旧实现直接
 * 用全尺寸页面原图当缩略图。一张 6336px 宽的漫画大图解码后约 240MB 内存，
 * 侧栏同时渲染十几张就会把浏览器渲染进程压垮（图片解码失败、显示错乱、
 * 甚至 "Aw, Snap" 崩溃）。原生客户端用 Glide 按控件尺寸降采样解码没有此问题。
 *
 * 这里用 createImageBitmap 的 resizeWidth 在解码阶段直接降采样，并把结果
 * 转成小尺寸 blob URL 渲染，内存占用与显示尺寸同量级。
 */

const CACHE_LIMIT = 300;
// src -> 已生成的小图 blob URL
const thumbCache = new Map<string, string>();
// src -> 进行中的生成任务，避免同一 URL 重复下载/解码
const inflight = new Map<string, Promise<string | null>>();

function cacheSet(key: string, url: string) {
  thumbCache.set(key, url);
  if (thumbCache.size > CACHE_LIMIT) {
    const oldestKey = thumbCache.keys().next().value;
    if (oldestKey !== undefined) {
      const oldUrl = thumbCache.get(oldestKey);
      thumbCache.delete(oldestKey);
      if (oldUrl) URL.revokeObjectURL(oldUrl);
    }
  }
}

async function buildDownscaledThumbnail(src: string, targetWidth: number): Promise<string | null> {
  const response = await fetch(src, { credentials: 'include' });
  if (!response.ok) {
    return null;
  }
  const blob = await response.blob();

  // 不支持 decode-time resize 的环境直接返回 null，由调用方回退到原图
  if (typeof createImageBitmap !== 'function' || typeof OffscreenCanvas === 'undefined') {
    return null;
  }

  const dpr = typeof window !== 'undefined' ? Math.min(window.devicePixelRatio || 1, 2) : 1;
  const resizeWidth = Math.max(32, Math.min(512, Math.round(targetWidth * dpr)));

  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(blob, {
      resizeWidth,
      resizeQuality: 'low',
      imageOrientation: 'from-image',
    } as ImageBitmapOptions);
  } catch {
    // 不支持 decode-time resize 时不要退化成全尺寸解码（那正是要避免的内存问题），
    // 交给调用方回退到原生 <img>。
    return null;
  }

  try {
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;
    ctx.drawImage(bitmap, 0, 0);
    const outBlob = await canvas.convertToBlob({ type: 'image/jpeg', quality: 0.78 });
    return URL.createObjectURL(outBlob);
  } finally {
    bitmap.close();
  }
}

function getOrCreateThumbnail(src: string, targetWidth: number): Promise<string | null> {
  const cacheKey = `${Math.round(targetWidth)}|${src}`;
  const cached = thumbCache.get(cacheKey);
  if (cached) return Promise.resolve(cached);
  const pending = inflight.get(cacheKey);
  if (pending) return pending;

  const task = buildDownscaledThumbnail(src, targetWidth)
    .then((url) => {
      if (url) cacheSet(cacheKey, url);
      return url;
    })
    .catch(() => null)
    .finally(() => {
      inflight.delete(cacheKey);
    });
  inflight.set(cacheKey, task);
  return task;
}

export function ReaderSidebarThumb({
  src,
  alt,
  widthPx,
  className,
  draggable,
  onThumbLoaded,
}: {
  src: string;
  alt: string;
  widthPx: number;
  className: string;
  draggable?: boolean;
  onThumbLoaded: (image: HTMLImageElement) => void;
}) {
  // 预生成缩略图（server-side thumbnail）无需降采样，直接走原生 img
  const needsDownscale = src.includes('/page?');
  const [objectUrl, setObjectUrl] = useState<string | null>(() => {
    if (!needsDownscale) return null;
    return thumbCache.get(`${Math.round(widthPx)}|${src}`) || null;
  });
  const [failed, setFailed] = useState(false);
  const imgRef = useRef<HTMLImageElement | null>(null);

  useEffect(() => {
    if (!needsDownscale || failed) return;
    const cached = thumbCache.get(`${Math.round(widthPx)}|${src}`);
    if (cached) {
      setObjectUrl(cached);
      return;
    }
    let cancelled = false;
    getOrCreateThumbnail(src, widthPx).then((url) => {
      if (cancelled) return;
      if (url) {
        setObjectUrl(url);
      } else {
        setFailed(true);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [needsDownscale, src, widthPx, failed]);

  // 降采样失败时回退到原图，保持旧行为可用
  const finalSrc = needsDownscale ? (objectUrl || (failed ? src : '')) : src;

  if (!finalSrc) {
    // 父容器已通过 thumbAspectRatios 固定了占位高度，这里留空即可，避免布局跳动
    return null;
  }

  return (
    <img
      ref={imgRef}
      src={finalSrc}
      alt={alt}
      className={className}
      decoding="async"
      loading="lazy"
      draggable={draggable}
      onLoad={(e) => onThumbLoaded(e.currentTarget)}
    />
  );
}
