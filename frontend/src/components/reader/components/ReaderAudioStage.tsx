/* eslint-disable @next/next/no-img-element */
import { useEffect, useMemo, useRef, useState } from 'react';
import { MemoizedAudio, MemoizedImage } from '@/components/reader/components/MemoizedMedia';
import { ArchiveService } from '@/lib/services/archive-service';
import { apiClient } from '@/lib/api';

const lyricsCache = new Map<number, string>();
const lyricsInflight = new Map<number, Promise<string>>();
let sharedAudioContext: AudioContext | null = null;
const mediaElementSourceCache = new WeakMap<HTMLMediaElement, MediaElementAudioSourceNode>();

async function loadLyricsText(assetId: number): Promise<string> {
  if (!assetId || assetId <= 0) return '';
  const cached = lyricsCache.get(assetId);
  if (cached != null) return cached;
  const inflight = lyricsInflight.get(assetId);
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
    lyricsCache.set(assetId, normalized);
    return normalized;
  })().finally(() => {
    lyricsInflight.delete(assetId);
  });

  lyricsInflight.set(assetId, request);
  return request;
}

type TimedLyricLine = {
  time: number;
  text: string;
  key: string;
};

const LRC_TIME_TAG = /\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]/g;

function parseTimedLyrics(rawLyrics: string): TimedLyricLine[] {
  const lines = rawLyrics.split(/\r?\n/);
  const parsed: TimedLyricLine[] = [];
  let lineIndex = 0;

  for (const rawLine of lines) {
    const tags = [...rawLine.matchAll(LRC_TIME_TAG)];
    if (tags.length <= 0) {
      lineIndex += 1;
      continue;
    }

    const text = rawLine.replace(LRC_TIME_TAG, '').trim();
    for (let i = 0; i < tags.length; i += 1) {
      const tag = tags[i];
      const minutes = Number(tag[1] || 0);
      const seconds = Number(tag[2] || 0);
      const fractionRaw = tag[3] || '0';
      const ms = Number((fractionRaw + '00').slice(0, 3));
      if (!Number.isFinite(minutes) || !Number.isFinite(seconds) || !Number.isFinite(ms)) continue;
      const time = minutes * 60 + seconds + ms / 1000;
      parsed.push({
        time,
        text,
        key: `${lineIndex}-${i}-${time.toFixed(3)}`,
      });
    }
    lineIndex += 1;
  }

  parsed.sort((a, b) => a.time - b.time);
  return parsed;
}

function getActiveTimedLyricIndex(lines: TimedLyricLine[], currentTime: number): number {
  if (lines.length <= 0) return -1;
  if (currentTime < lines[0].time) return -1;

  let low = 0;
  let high = lines.length - 1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (lines[mid].time <= currentTime) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return high;
}

export function ReaderAudioStage({
  title,
  description,
  thumb,
  audioUrl,
  lyricsAssetId,
  audioRef,
  onLoadedData,
  onError,
  t,
}: {
  title: string;
  description?: string;
  thumb?: string;
  audioUrl: string;
  lyricsAssetId?: number;
  audioRef: (el: HTMLAudioElement | null) => void;
  onLoadedData: () => void;
  onError: () => void;
  t: (key: string) => string;
}) {
  const [lyrics, setLyrics] = useState('');
  const [lyricsLoading, setLyricsLoading] = useState(false);
  const [lyricsError, setLyricsError] = useState(false);
  const [audioEl, setAudioEl] = useState<HTMLAudioElement | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [waveBeat, setWaveBeat] = useState(0);
  const [reducedMotion, setReducedMotion] = useState(false);
  const lyricViewportRef = useRef<HTMLDivElement | null>(null);
  const timedLineRefs = useRef<Array<HTMLDivElement | null>>([]);

  useEffect(() => {
    let cancelled = false;
    const assetId = Number(lyricsAssetId || 0);
    if (!assetId || assetId <= 0) {
      setLyrics('');
      setLyricsLoading(false);
      setLyricsError(false);
      return;
    }

    setLyricsLoading(true);
    setLyricsError(false);
    loadLyricsText(assetId)
      .then((text) => {
        if (cancelled) return;
        setLyrics(text);
        setLyricsLoading(false);
      })
      .catch(() => {
        if (cancelled) return;
        setLyrics('');
        setLyricsLoading(false);
        setLyricsError(true);
      });

    return () => {
      cancelled = true;
    };
  }, [lyricsAssetId]);

  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
    const mediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    const apply = () => setReducedMotion(mediaQuery.matches);
    apply();

    if (typeof mediaQuery.addEventListener === 'function') {
      mediaQuery.addEventListener('change', apply);
      return () => mediaQuery.removeEventListener('change', apply);
    }
    mediaQuery.addListener(apply);
    return () => mediaQuery.removeListener(apply);
  }, []);

  useEffect(() => {
    if (!audioEl) {
      setIsPlaying(false);
      setCurrentTime(0);
      return;
    }

    const syncState = () => {
      setCurrentTime(Number.isFinite(audioEl.currentTime) ? audioEl.currentTime : 0);
      setIsPlaying(!audioEl.paused && !audioEl.ended);
    };

    syncState();
    audioEl.addEventListener('play', syncState);
    audioEl.addEventListener('pause', syncState);
    audioEl.addEventListener('ended', syncState);
    audioEl.addEventListener('timeupdate', syncState);
    audioEl.addEventListener('seeked', syncState);
    audioEl.addEventListener('loadedmetadata', syncState);

    return () => {
      audioEl.removeEventListener('play', syncState);
      audioEl.removeEventListener('pause', syncState);
      audioEl.removeEventListener('ended', syncState);
      audioEl.removeEventListener('timeupdate', syncState);
      audioEl.removeEventListener('seeked', syncState);
      audioEl.removeEventListener('loadedmetadata', syncState);
    };
  }, [audioEl]);

  useEffect(() => {
    if (!audioEl || typeof window === 'undefined') {
      setWaveBeat(0);
      return;
    }

    let rafId = 0;
    let disposed = false;
    let smoothedEnergy = 0;
    let analyserNode: AnalyserNode | null = null;
    let sourceNode: MediaElementAudioSourceNode | null = null;
    let frequencyBuffer: Uint8Array | null = null;
    let audioContext: AudioContext | null = null;

    const tick = () => {
      if (disposed) return;

      if (analyserNode && frequencyBuffer) {
        analyserNode.getByteFrequencyData(frequencyBuffer as any);
        let sum = 0;
        for (let i = 0; i < frequencyBuffer.length; i += 1) {
          sum += frequencyBuffer[i];
        }
        const average = sum / Math.max(1, frequencyBuffer.length) / 255;
        const boosted = Math.min(1, average * 5);
        smoothedEnergy = smoothedEnergy * 0.58 + boosted * 0.42;
      } else {
        smoothedEnergy *= 0.86;
      }

      const nextValue = smoothedEnergy < 0.01 ? 0 : smoothedEnergy;
      setWaveBeat((prev) => (Math.abs(prev - nextValue) > 0.008 ? nextValue : prev));
      rafId = window.requestAnimationFrame(tick);
    };

    const setupAudioAnalysis = () => {
      try {
        const AudioContextCtor = window.AudioContext || (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
        if (!AudioContextCtor) return;
        sharedAudioContext = sharedAudioContext || new AudioContextCtor();
        audioContext = sharedAudioContext;

        sourceNode = mediaElementSourceCache.get(audioEl) || null;
        if (!sourceNode) {
          sourceNode = audioContext.createMediaElementSource(audioEl);
          mediaElementSourceCache.set(audioEl, sourceNode);
        }

        analyserNode = audioContext.createAnalyser();
        analyserNode.fftSize = 256;
        analyserNode.smoothingTimeConstant = 0.86;
        frequencyBuffer = new Uint8Array(analyserNode.frequencyBinCount);

        sourceNode.connect(analyserNode);
        analyserNode.connect(audioContext.destination);
      } catch {
        analyserNode = null;
        frequencyBuffer = null;
      }
    };

    const resumeAudioContext = () => {
      if (!audioContext) return;
      if (audioContext.state === 'suspended') {
        void audioContext.resume().catch(() => {});
      }
    };

    setupAudioAnalysis();
    resumeAudioContext();
    audioEl.addEventListener('play', resumeAudioContext);
    rafId = window.requestAnimationFrame(tick);

    return () => {
      disposed = true;
      audioEl.removeEventListener('play', resumeAudioContext);
      if (rafId) window.cancelAnimationFrame(rafId);
      if (sourceNode && analyserNode) {
        try {
          sourceNode.disconnect(analyserNode);
        } catch {
          // ignore
        }
      }
      if (analyserNode) {
        try {
          analyserNode.disconnect();
        } catch {
          // ignore
        }
      }
    };
  }, [audioEl]);

  const safeTitle = useMemo(() => title.trim() || 'Untitled', [title]);
  const safeDescription = description?.trim() || '';
  const hasLyrics = lyrics.length > 0;
  const timedLyrics = useMemo(() => parseTimedLyrics(lyrics), [lyrics]);
  const hasTimedLyrics = timedLyrics.length > 0;
  const plainLyrics = useMemo(
    () =>
      lyrics
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean),
    [lyrics]
  );
  const activeTimedIndex = hasTimedLyrics ? getActiveTimedLyricIndex(timedLyrics, currentTime) : -1;
  const waveStageStyle = useMemo(
    () => ({ ['--wave-beat' as const]: (isPlaying ? waveBeat : 0).toFixed(3) }) as Record<string, string>,
    [isPlaying, waveBeat]
  );

  useEffect(() => {
    if (!hasTimedLyrics || activeTimedIndex < 0) return;
    const viewport = lyricViewportRef.current;
    const activeLine = timedLineRefs.current[activeTimedIndex];
    if (!viewport || !activeLine) return;

    const targetTop = activeLine.offsetTop - viewport.clientHeight / 2 + activeLine.clientHeight / 2;
    viewport.scrollTo({
      top: Math.max(0, targetTop),
      behavior: reducedMotion ? 'auto' : 'smooth',
    });
  }, [activeTimedIndex, hasTimedLyrics, reducedMotion]);

  return (
    <div className="relative h-full w-full overflow-hidden text-white">
      {thumb ? (
        <MemoizedImage
          src={thumb}
          alt={safeTitle}
          className="absolute inset-0 h-full w-full scale-[1.2] object-cover blur-[56px] opacity-60"
          decoding="async"
          loading="eager"
          draggable={false}
        />
      ) : null}
      <div className="absolute inset-0 bg-gradient-to-b from-black/20 via-black/28 to-black/36" />
      <div
        className={`pointer-events-none absolute inset-x-0 bottom-0 z-[1] h-28 overflow-hidden sm:h-32 ${
          isPlaying ? 'reader-audio-wave-stage-active' : 'reader-audio-wave-stage-idle'
        }`}
        style={waveStageStyle}
      >
        <div className="reader-audio-line-wave reader-audio-line-wave-a">
          <svg viewBox="0 0 1440 120" preserveAspectRatio="none" className="reader-audio-line-shape" aria-hidden="true">
            <path className="reader-audio-line-path reader-audio-line-path-a" d="M0,78 C100,62 220,94 340,78 C460,62 580,94 700,78 C820,62 940,94 1060,78 C1180,62 1300,94 1440,78" />
            <path className="reader-audio-line-path reader-audio-line-path-a" d="M1440,78 C1540,62 1660,94 1780,78 C1900,62 2020,94 2140,78 C2260,62 2380,94 2500,78 C2620,62 2740,94 2880,78" />
          </svg>
        </div>
        <div className="reader-audio-line-wave reader-audio-line-wave-b">
          <svg viewBox="0 0 1440 120" preserveAspectRatio="none" className="reader-audio-line-shape" aria-hidden="true">
            <path className="reader-audio-line-path reader-audio-line-path-b" d="M0,80 C120,70 250,88 380,80 C510,72 640,90 770,80 C900,70 1030,88 1160,80 C1290,72 1360,88 1440,80" />
            <path className="reader-audio-line-path reader-audio-line-path-b" d="M1440,80 C1560,70 1690,88 1820,80 C1950,72 2080,90 2210,80 C2340,70 2470,88 2600,80 C2730,72 2800,88 2880,80" />
          </svg>
        </div>
        <div className="reader-audio-line-wave reader-audio-line-wave-c">
          <svg viewBox="0 0 1440 120" preserveAspectRatio="none" className="reader-audio-line-shape" aria-hidden="true">
            <path className="reader-audio-line-path reader-audio-line-path-c" d="M0,82 C110,74 240,90 370,82 C500,74 630,90 760,82 C890,74 1020,90 1150,82 C1280,74 1360,90 1440,82" />
            <path className="reader-audio-line-path reader-audio-line-path-c" d="M1440,82 C1550,74 1680,90 1810,82 C1940,74 2070,90 2200,82 C2330,74 2460,90 2590,82 C2720,74 2800,90 2880,82" />
          </svg>
        </div>
      </div>

      <div className="relative z-10 flex h-full w-full items-center justify-center px-4 py-6 sm:px-6 sm:py-8 lg:px-10 lg:py-10">
        <div className="grid h-full w-full max-w-6xl grid-cols-1 items-center gap-6 lg:gap-8 xl:grid-cols-[minmax(260px,360px)_minmax(0,1fr)]">
          <div className="flex w-full flex-col items-center justify-center gap-5 sm:gap-7 xl:items-start xl:gap-6">
            <div className="relative w-[62vw] max-w-[340px] min-w-[148px] sm:w-[44vw] xl:w-[min(24vw,340px)]">
              <div className="absolute inset-[-8%] rounded-full bg-white/12 blur-2xl" />
              <div className="relative aspect-square rounded-full border border-white/28 p-1.5 shadow-[0_28px_80px_-32px_rgba(0,0,0,0.85)]">
                <div className="h-full w-full overflow-hidden rounded-full border border-white/25">
                  {thumb ? (
                    <MemoizedImage
                      src={thumb}
                      alt={safeTitle}
                      className="h-full w-full animate-[spin_18s_linear_infinite] object-cover motion-reduce:animate-none"
                      style={{ animationPlayState: isPlaying ? 'running' : 'paused' }}
                      decoding="async"
                      loading="eager"
                      draggable={false}
                    />
                  ) : (
                    <div className="flex h-full w-full items-center justify-center rounded-full bg-white/10 text-sm text-white/65">
                      Audio
                    </div>
                  )}
                </div>
                <div className="absolute left-1/2 top-1/2 h-5 w-5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-black/45 ring-2 ring-white/38" />
              </div>
            </div>

            <div className="w-full text-center xl:text-left">
              <div className="line-clamp-2 break-words text-xl font-semibold tracking-tight text-white sm:text-3xl">{safeTitle}</div>
              {safeDescription ? <div className="mt-2 line-clamp-3 whitespace-pre-line text-sm text-white/80 sm:text-base">{safeDescription}</div> : null}
            </div>
          </div>

          <div className="min-h-0 w-full xl:h-full xl:py-3">
            <div ref={lyricViewportRef} className="h-full max-h-[38vh] overflow-x-hidden overflow-y-auto px-1 py-2 sm:max-h-[40vh] xl:max-h-[74vh]">
              {lyricsLoading ? <div className="py-3 text-center text-sm text-white/75">{t('reader.audioLyricsLoading')}</div> : null}
              {!lyricsLoading && lyricsError ? <div className="py-3 text-center text-sm text-white/75">{t('reader.audioLyricsLoadFailed')}</div> : null}
              {!lyricsLoading && !lyricsError && !hasLyrics ? (
                <div className="py-3 text-center text-sm text-white/75">{t('reader.audioLyricsEmpty')}</div>
              ) : null}
              {!lyricsLoading && !lyricsError && hasLyrics && hasTimedLyrics ? (
                <div className="space-y-2 pb-16 pt-12">
                  {timedLyrics.map((line, index) => {
                    const isActive = index === activeTimedIndex;
                    return (
                      <div
                        key={line.key}
                        ref={(el) => {
                          timedLineRefs.current[index] = el;
                        }}
                        className={`select-none break-words text-center transition-all duration-300 ${
                          isActive ? 'scale-[1.03] text-white text-[1.05rem] sm:text-xl font-semibold' : 'text-white/58 text-sm sm:text-base'
                        }`}
                      >
                        {line.text || '...'}
                      </div>
                    );
                  })}
                </div>
              ) : null}
              {!lyricsLoading && !lyricsError && hasLyrics && !hasTimedLyrics ? (
                <div className="space-y-2 pb-8 pt-2">
                  {plainLyrics.map((line, index) => (
                    <div key={`${index}-${line}`} className="break-words text-center text-sm text-white/78 sm:text-base">
                      {line}
                    </div>
                  ))}
                </div>
              ) : null}
            </div>
          </div>

          <MemoizedAudio
            src={audioUrl}
            ref={(el) => {
              setAudioEl(el);
              audioRef(el);
            }}
            className="absolute h-px w-px pointer-events-none opacity-0"
            onLoadedData={onLoadedData}
            onError={onError}
          />
        </div>
      </div>
    </div>
  );
}
