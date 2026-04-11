import { useEffect, useMemo, useState } from 'react';
import type React from 'react';
import { MemoizedVideo } from '@/components/reader/components/MemoizedMedia';
import { ArchiveService } from '@/lib/services/archive-service';
import { apiClient } from '@/lib/api';

type SubtitleCue = {
  start: number;
  end: number;
  text: string;
};

const subtitleCache = new Map<number, string>();
const subtitleInflight = new Map<number, Promise<string>>();

async function loadSubtitleText(assetId: number): Promise<string> {
  if (!assetId || assetId <= 0) return '';
  const cached = subtitleCache.get(assetId);
  if (cached != null) return cached;
  const inflight = subtitleInflight.get(assetId);
  if (inflight) return inflight;

  const request = (async () => {
    const url = ArchiveService.getAssetUrl(assetId);
    if (!url) return '';
    const response = await apiClient.get<string>(url, {
      responseType: 'text',
      transformResponse: [(v) => v],
    });
    const text = typeof response.data === 'string' ? response.data : String(response.data || '');
    const normalized = text.replace(/^\uFEFF/, '').trim();
    subtitleCache.set(assetId, normalized);
    return normalized;
  })().finally(() => {
    subtitleInflight.delete(assetId);
  });

  subtitleInflight.set(assetId, request);
  return request;
}

function parseTimestamp(raw: string): number {
  const normalized = raw.trim().replace(',', '.');
  const parts = normalized.split(':').map((part) => Number(part));
  if (parts.some((part) => !Number.isFinite(part))) return 0;
  if (parts.length === 3) {
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
  }
  if (parts.length === 2) {
    return parts[0] * 60 + parts[1];
  }
  return parts[0] || 0;
}

function stripAssFormatting(text: string): string {
  return text
    .replace(/\{[^}]*\}/g, '')
    .replace(/\\N/gi, '\n')
    .replace(/\\n/g, '\n')
    .replace(/\\h/g, ' ')
    .trim();
}

function parseSrt(text: string): SubtitleCue[] {
  return text
    .split(/\r?\n\r?\n/)
    .map((block) => block.trim())
    .filter(Boolean)
    .map((block) => {
      const lines = block.split(/\r?\n/).map((line) => line.trim());
      const timeLine = lines.find((line) => line.includes('-->')) || '';
      const [startRaw, endRaw] = timeLine.split('-->').map((value) => value.trim());
      if (!startRaw || !endRaw) return null;
      const start = parseTimestamp(startRaw);
      const end = parseTimestamp(endRaw);
      const textLines = lines.filter((line) => line && line !== timeLine && !/^\d+$/.test(line));
      const body = textLines.join('\n').trim();
      if (!body) return null;
      return { start, end, text: body } satisfies SubtitleCue;
    })
    .filter((cue): cue is SubtitleCue => Boolean(cue));
}

function parseVtt(text: string): SubtitleCue[] {
  return text
    .replace(/^WEBVTT[\s\r\n]*/i, '')
    .split(/\r?\n\r?\n/)
    .map((block) => block.trim())
    .filter(Boolean)
    .map((block) => {
      const lines = block.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
      const timeLine = lines.find((line) => line.includes('-->')) || '';
      const [startRaw, endRaw] = timeLine.split('-->').map((value) => value.trim().split(/\s+/)[0]);
      if (!startRaw || !endRaw) return null;
      const body = lines.filter((line) => line && line !== timeLine).join('\n').trim();
      if (!body) return null;
      return { start: parseTimestamp(startRaw), end: parseTimestamp(endRaw), text: body } satisfies SubtitleCue;
    })
    .filter((cue): cue is SubtitleCue => Boolean(cue));
}

function parseAss(text: string): SubtitleCue[] {
  const lines = text.split(/\r?\n/);
  const cues: SubtitleCue[] = [];
  for (const line of lines) {
    if (!line.startsWith('Dialogue:')) continue;
    const payload = line.slice('Dialogue:'.length).trim();
    const parts = payload.split(',');
    if (parts.length < 10) continue;
    const start = parseTimestamp(parts[1] || '');
    const end = parseTimestamp(parts[2] || '');
    const body = stripAssFormatting(parts.slice(9).join(','));
    if (!body) continue;
    cues.push({ start, end, text: body });
  }
  return cues;
}

function parseSubtitleText(text: string, kind?: string): SubtitleCue[] {
  const normalizedKind = String(kind || '').trim().toLowerCase();
  if (normalizedKind === 'ass' || normalizedKind === 'ssa') return parseAss(text);
  if (normalizedKind === 'vtt') return parseVtt(text);
  return parseSrt(text);
}

function getActiveSubtitle(cues: SubtitleCue[], currentTime: number): SubtitleCue | null {
  for (const cue of cues) {
    if (currentTime >= cue.start && currentTime <= cue.end) {
      return cue;
    }
  }
  return null;
}

export function ReaderVideoStage({
  src,
  subtitleAssetId,
  subtitleKind,
  className,
  style,
  videoRef,
  onLoadedData,
  onError,
  onVideoClick,
}: {
  src: string;
  subtitleAssetId?: number;
  subtitleKind?: string;
  className?: string;
  style?: React.CSSProperties;
  videoRef: (el: HTMLVideoElement | null) => void;
  onLoadedData?: () => void;
  onError?: () => void;
  onVideoClick?: () => void;
}) {
  const [videoEl, setVideoEl] = useState<HTMLVideoElement | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [subtitleText, setSubtitleText] = useState('');

  useEffect(() => {
    let cancelled = false;
    const assetId = Number(subtitleAssetId || 0);
    if (!assetId || assetId <= 0) {
      setSubtitleText('');
      return;
    }

    loadSubtitleText(assetId)
      .then((text) => {
        if (!cancelled) setSubtitleText(text);
      })
      .catch(() => {
        if (!cancelled) setSubtitleText('');
      });

    return () => {
      cancelled = true;
    };
  }, [subtitleAssetId]);

  useEffect(() => {
    if (!videoEl) {
      setCurrentTime(0);
      return;
    }
    const sync = () => {
      setCurrentTime(Number.isFinite(videoEl.currentTime) ? videoEl.currentTime : 0);
    };
    sync();
    videoEl.addEventListener('timeupdate', sync);
    videoEl.addEventListener('seeked', sync);
    videoEl.addEventListener('loadedmetadata', sync);
    return () => {
      videoEl.removeEventListener('timeupdate', sync);
      videoEl.removeEventListener('seeked', sync);
      videoEl.removeEventListener('loadedmetadata', sync);
    };
  }, [videoEl]);

  const cues = useMemo(() => {
    if (!subtitleText.trim()) return [];
    return parseSubtitleText(subtitleText, subtitleKind);
  }, [subtitleKind, subtitleText]);

  const activeCue = useMemo(() => getActiveSubtitle(cues, currentTime), [cues, currentTime]);

  return (
    <div className="relative flex h-full w-full max-h-full max-w-full items-center justify-center">
      <MemoizedVideo
        src={src}
        ref={(el) => {
          setVideoEl(el);
          videoRef(el);
        }}
        className={className}
        style={style}
        onLoadedData={onLoadedData}
        onError={onError}
        onVideoClick={onVideoClick}
      />
      {activeCue ? (
        <div className="pointer-events-none absolute inset-x-4 bottom-4 flex justify-center">
          <div className="max-w-[92%] rounded-xl bg-black/68 px-3 py-2 text-center text-sm font-medium leading-6 text-white shadow-lg backdrop-blur-sm whitespace-pre-line">
            {activeCue.text}
          </div>
        </div>
      ) : null}
    </div>
  );
}
