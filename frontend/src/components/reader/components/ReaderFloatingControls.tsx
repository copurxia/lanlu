import { Button } from '@/components/ui/button';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Slider } from '@/components/ui/slider';
import { cn } from '@/lib/utils/utils';
import { Heart, Pause, Play, Rewind, FastForward, Volume2, VolumeX, SlidersHorizontal, Book } from 'lucide-react';
import { ReaderSettingsSheet, type ReaderSettingButton } from '@/components/reader/components/ReaderSettingsSheet';
import type { ArchiveMetadata } from '@/types/archive';
import { useEffect, useMemo, useState } from 'react';
import type React from 'react';

export type ReaderProgressLane = {
  id: string;
  kind: 'book' | 'video' | 'audio';
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: number;
  min?: number;
  max: number;
  step?: number;
  valueText?: string;
  onChange: (value: number) => void;
  isPlaying?: boolean;
  isMuted?: boolean;
  volume?: number;
  onTogglePlay?: () => void;
  onSeekRelative?: (deltaSeconds: number) => void;
  onToggleMute?: () => void;
  onVolumeChange?: (value: number) => void;
};

const floatingSurfaceClass = 'bg-[hsl(var(--background)/0.55)] backdrop-blur-xl border border-[hsl(var(--border)/0.8)] shadow-lg';
const desktopIconButtonClass =
  'rounded-full h-11 w-11 p-1 transition-all duration-150 ease-out hover:scale-110 active:scale-95 text-foreground/70 hover:text-foreground hover:bg-white/30 hover:border hover:border-white/60 dark:hover:bg-[hsl(var(--background)/0.28)] dark:hover:border-[hsl(var(--border)/0.8)] will-change-transform';
const mobileActionButtonClass =
  'rounded-full h-11 w-11 p-0 text-foreground/80 hover:bg-white/20 hover:text-foreground active:scale-95';
const laneToggleButtonClass =
  'rounded-full h-9 w-9 p-0 border border-white/[0.28] bg-white/6 text-foreground/70 transition-all duration-150 ease-out hover:bg-white/20 hover:border-white/[0.55] hover:text-foreground dark:border-[hsl(var(--border)/0.7)] dark:bg-[hsl(var(--background)/0.24)] dark:hover:bg-[hsl(var(--background)/0.36)] dark:hover:border-[hsl(var(--border)/0.85)]';
const mobileLaneToggleButtonClass =
  'rounded-full h-9 w-9 p-0 border border-[hsl(var(--border)/0.7)] bg-[hsl(var(--background)/0.24)] text-foreground/70 transition-all duration-150 ease-out hover:bg-[hsl(var(--background)/0.36)] hover:border-[hsl(var(--border)/0.85)] hover:text-foreground';
const mobileMediaButtonClass =
  'rounded-full h-9 w-9 p-0 text-foreground/80 hover:bg-[hsl(var(--background)/0.28)] hover:text-foreground active:scale-95';
const mobileFloatingPanelClass =
  'relative overflow-hidden rounded-full px-2.5 py-2 bg-[hsl(var(--background)/0.55)] backdrop-blur-xl border border-[hsl(var(--border)/0.8)] shadow-lg';
const activeLaneToggleButtonClass =
  'bg-[hsl(var(--background)/0.55)] text-foreground border-[hsl(var(--border)/0.85)] shadow-xs';

function isMediaLane(
  lane: ReaderProgressLane | null | undefined
): lane is ReaderProgressLane & { kind: 'audio' | 'video' } {
  return lane?.kind === 'audio' || lane?.kind === 'video';
}

function MobileBookControls({
  currentPage,
  totalPages,
  onChangePage,
}: {
  currentPage: number;
  totalPages: number;
  onChangePage: (page: number) => void;
}) {
  return (
    <div className="flex min-w-0 flex-1 items-center gap-2.5">
      <Slider
        value={[currentPage]}
        onValueChange={(value) => onChangePage(value[0])}
        max={Math.max(0, totalPages - 1)}
        min={0}
        step={1}
        className="min-w-0 flex-1 h-2"
      />
      <span className="min-w-[44px] text-right text-sm font-medium tabular-nums text-foreground/95">
        {currentPage + 1}/{totalPages}
      </span>
    </div>
  );
}

function MobileMediaControls({
  lane,
  onOpenDetails,
}: {
  lane: ReaderProgressLane & { kind: 'audio' | 'video' };
  onOpenDetails: () => void;
}) {
  return (
    <div className="flex min-w-0 flex-1 items-center gap-1.5">
      <Button
        variant="ghost"
        size="sm"
        onClick={lane.onTogglePlay}
        className={mobileMediaButtonClass}
        title={lane.isPlaying ? 'Pause' : 'Play'}
      >
        {lane.isPlaying ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
      </Button>

      <div className="flex min-w-0 flex-1 items-center gap-2">
        <Slider
          value={[lane.value]}
          onValueChange={(value) => lane.onChange(value[0])}
          max={Math.max(lane.min ?? 0, lane.max)}
          min={lane.min ?? 0}
          step={lane.step ?? 1}
          className="min-w-0 flex-1 h-2"
        />
        <span className="min-w-[72px] text-right text-xs font-medium tabular-nums text-foreground/95">
          {lane.valueText ?? `${Math.round(lane.value)}/${Math.round(lane.max)}`}
        </span>
      </div>

      <Button
        variant="ghost"
        size="sm"
        onClick={lane.onToggleMute}
        className={mobileMediaButtonClass}
        title={lane.isMuted ? 'Unmute' : 'Mute'}
      >
        {lane.isMuted ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
      </Button>

      <Button
        variant="ghost"
        size="sm"
        onClick={onOpenDetails}
        className={mobileMediaButtonClass}
        title="More controls"
      >
        <SlidersHorizontal className="h-4 w-4" />
      </Button>
    </div>
  );
}

export function ReaderFloatingControls({
  showToolbar,
  currentPage,
  totalPages,
  onChangePage,
  progressLanes,
  expandedLaneId,
  onToggleLane,
  settingsOpen,
  onSettingsOpenChange,
  archiveTitle,
  archiveMetadata,
  metadataTags,
  id,
  onNavigateToArchive,
  settingButtons,
  autoPlayMode,
  autoPlayInterval,
  onAutoPlayIntervalChange,
  isFavorited,
  onToggleFavorite,
  t,
}: {
  showToolbar: boolean;
  currentPage: number;
  totalPages: number;
  onChangePage: (page: number) => void;
  progressLanes: ReaderProgressLane[];
  expandedLaneId: string | null;
  onToggleLane: (laneId: string) => void;
  settingsOpen: boolean;
  onSettingsOpenChange: (open: boolean) => void;
  archiveTitle: string;
  archiveMetadata: ArchiveMetadata | null;
  metadataTags: string[];
  id: string | null;
  onNavigateToArchive: () => void;
  settingButtons: ReaderSettingButton[];
  autoPlayMode: boolean;
  autoPlayInterval: number;
  onAutoPlayIntervalChange: (seconds: number) => void;
  isFavorited: boolean;
  onToggleFavorite: (e?: React.MouseEvent) => void;
  t: (key: string) => string;
}) {
  const [isMobile, setIsMobile] = useState(false);
  const [mediaSheetOpen, setMediaSheetOpen] = useState(false);

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const mql = window.matchMedia('(max-width: 639px)');
    const onChange = (event: MediaQueryListEvent) => setIsMobile(event.matches);
    setIsMobile(mql.matches);
    mql.addEventListener('change', onChange);
    return () => mql.removeEventListener('change', onChange);
  }, []);

  const fallbackBookLane = useMemo<ReaderProgressLane>(
    () => ({
      id: 'book',
      kind: 'book',
      icon: Book,
      label: t('reader.navigation'),
      value: currentPage,
      min: 0,
      max: Math.max(0, totalPages - 1),
      step: 1,
      valueText: `${currentPage + 1}/${totalPages}`,
      onChange: (value: number) => onChangePage(Math.round(value)),
    }),
    [currentPage, totalPages, onChangePage, t]
  );
  const resolvedLanes = useMemo(
    () => (progressLanes.length > 0 ? progressLanes : [fallbackBookLane]),
    [progressLanes, fallbackBookLane]
  );
  const resolvedActiveLane = useMemo(
    () => resolvedLanes.find((lane) => lane.id === expandedLaneId) ?? resolvedLanes[0] ?? null,
    [expandedLaneId, resolvedLanes]
  );

  useEffect(() => {
    if (!isMediaLane(resolvedActiveLane)) {
      setMediaSheetOpen(false);
    }
  }, [resolvedActiveLane]);

  useEffect(() => {
    if (!isMobile) {
      setMediaSheetOpen(false);
    }
  }, [isMobile]);

  if (isMobile) {
    return (
      <>
        <div
          data-reader-overlay="true"
          className={cn(
            'absolute inset-x-3 z-50 transition-all duration-250 ease-out',
            showToolbar ? 'translate-y-0 opacity-100 pointer-events-auto' : 'translate-y-4 opacity-0 pointer-events-none'
          )}
          style={{ bottom: 'calc(env(safe-area-inset-bottom, 0px) + 12px)' }}
        >
          <div className="relative mx-auto w-full max-w-[calc(100vw-24px)]">
            <div className="space-y-2">
              <div className="relative z-10 flex items-center justify-end gap-2 px-1">
                <div className={cn(floatingSurfaceClass, 'shrink-0 rounded-full')}>
                  <ReaderSettingsSheet
                    open={settingsOpen}
                    onOpenChange={onSettingsOpenChange}
                    archiveTitle={archiveTitle}
                    archiveMetadata={archiveMetadata}
                    metadataTags={metadataTags}
                    id={id}
                    onNavigateToArchive={onNavigateToArchive}
                    settingButtons={settingButtons}
                    autoPlayMode={autoPlayMode}
                    autoPlayInterval={autoPlayInterval}
                    onAutoPlayIntervalChange={onAutoPlayIntervalChange}
                    t={t}
                  />
                </div>

                {!isFavorited ? (
                  <div className={cn(floatingSurfaceClass, 'shrink-0 rounded-full')}>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={onToggleFavorite}
                      className={mobileActionButtonClass}
                      title={t('reader.favorite')}
                    >
                      <Heart className="h-4 w-4" />
                    </Button>
                  </div>
                ) : null}
              </div>

              {resolvedActiveLane ? (
                <div className={mobileFloatingPanelClass}>
                  <div aria-hidden className="pointer-events-none absolute inset-px rounded-full bg-[hsl(var(--background)/0.12)]" />
                  <div className="relative z-10 flex items-center gap-1">
                    {resolvedLanes.map((lane) => {
                      const Icon = lane.icon;
                      const isExpanded = resolvedActiveLane.id === lane.id;
                      return (
                        <div key={lane.id} className={cn("flex items-center gap-1 min-w-0", isExpanded && "flex-1")}>
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => onToggleLane(lane.id)}
                            className={cn(
                              mobileLaneToggleButtonClass,
                              isExpanded && activeLaneToggleButtonClass
                            )}
                            title={lane.label}
                          >
                            <Icon className="h-4 w-4" />
                          </Button>

                          <div
                            className={`
                              flex min-w-0 flex-1 items-center gap-2 overflow-hidden
                              transition-all duration-250 ease-out origin-left
                              ${isExpanded ? 'max-w-[84vw] opacity-100 scale-100' : 'max-w-0 opacity-0 scale-95'}
                            `}
                          >
                            {isExpanded &&
                              (isMediaLane(lane) ? (
                                <MobileMediaControls lane={lane} onOpenDetails={() => setMediaSheetOpen(true)} />
                              ) : (
                                <MobileBookControls
                                  currentPage={currentPage}
                                  totalPages={totalPages}
                                  onChangePage={onChangePage}
                                />
                              ))}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              ) : null}
            </div>
          </div>
        </div>

        <Sheet open={mediaSheetOpen} onOpenChange={setMediaSheetOpen}>
          <SheetContent
            side="bottom"
            className="flex flex-col rounded-t-2xl border-x-0 px-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] pt-3 sm:hidden"
            showCloseButton={false}
          >
            <div className="mx-auto mb-1 h-1.5 w-12 rounded-full bg-muted" />
            <SheetHeader className="space-y-1 text-left">
              <SheetTitle className="text-base">{resolvedActiveLane?.label ?? 'Media controls'}</SheetTitle>
            </SheetHeader>

            {isMediaLane(resolvedActiveLane) ? (
              <div className="mt-4 space-y-4">
                <div className="flex items-center gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={resolvedActiveLane.onTogglePlay}
                    className="h-10 rounded-full px-4"
                  >
                    {resolvedActiveLane.isPlaying ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
                    <span>{resolvedActiveLane.isPlaying ? 'Pause' : 'Play'}</span>
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => resolvedActiveLane.onSeekRelative?.(-5)}
                    className="h-10 rounded-full px-4"
                  >
                    <Rewind className="h-4 w-4" />
                    <span>-5s</span>
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => resolvedActiveLane.onSeekRelative?.(5)}
                    className="h-10 rounded-full px-4"
                  >
                    <FastForward className="h-4 w-4" />
                    <span>+5s</span>
                  </Button>
                </div>

                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-3 text-sm font-medium">
                    <span className="text-muted-foreground">Timeline</span>
                    <span className="tabular-nums text-foreground/90">{resolvedActiveLane.valueText}</span>
                  </div>
                  <Slider
                    value={[resolvedActiveLane.value]}
                    onValueChange={(value) => resolvedActiveLane.onChange(value[0])}
                    max={Math.max(resolvedActiveLane.min ?? 0, resolvedActiveLane.max)}
                    min={resolvedActiveLane.min ?? 0}
                    step={resolvedActiveLane.step ?? 1}
                    className="h-2"
                  />
                </div>

                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-3 text-sm font-medium">
                    <span className="text-muted-foreground">Volume</span>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={resolvedActiveLane.onToggleMute}
                      className="h-9 rounded-full px-3 text-foreground/80"
                    >
                      {resolvedActiveLane.isMuted ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
                    </Button>
                  </div>
                  <Slider
                    value={[Math.max(0, Math.min(1, resolvedActiveLane.volume ?? 1))]}
                    onValueChange={(value) => resolvedActiveLane.onVolumeChange?.(value[0])}
                    max={1}
                    min={0}
                    step={0.01}
                    className="h-2"
                  />
                </div>
              </div>
            ) : null}
          </SheetContent>
        </Sheet>
      </>
    );
  }

  return (
    <div
      data-reader-overlay="true"
      className={`
        absolute bottom-8 left-1/2 transform -translate-x-1/2 flex items-center gap-3 
        transition-all duration-250 ease-out z-50
        will-change-transform will-change-opacity
        ${showToolbar ? 'opacity-100 translate-y-0 pointer-events-auto' : 'opacity-0 translate-y-4 pointer-events-none'}
      `}
    >
      {resolvedActiveLane ? (
        <div className="bg-[hsl(var(--background)/0.55)] backdrop-blur-xl border border-[hsl(var(--border)/0.8)] rounded-full px-3 py-2 shadow-lg">
          <div className="flex items-center gap-2">
            {resolvedLanes.map((lane) => {
              const Icon = lane.icon;
              const isExpanded = resolvedActiveLane.id === lane.id;
              return (
                <div key={lane.id} className="flex items-center gap-1">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => onToggleLane(lane.id)}
                    className={cn(
                      laneToggleButtonClass,
                      isExpanded &&
                        'bg-white/45 text-foreground border border-white/70 shadow-[0_6px_18px_rgba(255,255,255,0.18)] dark:bg-[hsl(var(--background)/0.55)] dark:border-[hsl(var(--border)/0.85)] dark:shadow-xs'
                    )}
                    title={lane.label}
                  >
                    <Icon className="w-4 h-4" />
                  </Button>

                  <div
                    className={`
                      flex items-center gap-2 overflow-hidden
                      transition-all duration-250 ease-out origin-left
                      ${isExpanded ? 'max-w-[84vw] sm:max-w-[560px] opacity-100 scale-100' : 'max-w-0 opacity-0 scale-95'}
                    `}
                  >
                    {lane.kind === 'video' || lane.kind === 'audio' ? (
                      <>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={lane.onTogglePlay}
                          className="rounded-full h-8 w-8 p-0 text-foreground transition-all duration-150 ease-out hover:bg-transparent hover:border-transparent hover:shadow-none"
                          title={lane.isPlaying ? 'Pause' : 'Play'}
                        >
                          {lane.isPlaying ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => lane.onSeekRelative?.(-5)}
                          className="rounded-full h-8 w-8 p-0 text-foreground/80 transition-all duration-150 ease-out hover:bg-transparent hover:border-transparent hover:shadow-none hover:text-foreground"
                          title="Back 5s"
                        >
                          <Rewind className="w-4 h-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => lane.onSeekRelative?.(5)}
                          className="rounded-full h-8 w-8 p-0 text-foreground/80 transition-all duration-150 ease-out hover:bg-transparent hover:border-transparent hover:shadow-none hover:text-foreground"
                          title="Forward 5s"
                        >
                          <FastForward className="w-4 h-4" />
                        </Button>
                      </>
                    ) : null}

                    <Slider
                      value={[lane.value]}
                      onValueChange={(value) => lane.onChange(value[0])}
                      max={Math.max(lane.min ?? 0, lane.max)}
                      min={lane.min ?? 0}
                      step={lane.step ?? 1}
                      className="w-28 sm:w-52 h-2"
                    />
                    <span
                      className={cn(
                        'text-sm whitespace-nowrap font-medium text-foreground text-right tabular-nums',
                        lane.kind === 'book' ? 'min-w-[44px]' : 'min-w-[84px]'
                      )}
                    >
                      {lane.valueText ?? `${Math.round(lane.value)}/${Math.round(lane.max)}`}
                    </span>

                    {lane.kind === 'video' || lane.kind === 'audio' ? (
                      <>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={lane.onToggleMute}
                          className="rounded-full h-8 w-8 p-0 text-foreground/80 transition-all duration-150 ease-out hover:bg-transparent hover:border-transparent hover:shadow-none hover:text-foreground"
                          title={lane.isMuted ? 'Unmute' : 'Mute'}
                        >
                          {lane.isMuted ? <VolumeX className="w-4 h-4" /> : <Volume2 className="w-4 h-4" />}
                        </Button>
                        <Slider
                          value={[Math.max(0, Math.min(1, lane.volume ?? 1))]}
                          onValueChange={(value) => lane.onVolumeChange?.(value[0])}
                          max={1}
                          min={0}
                          step={0.01}
                          className="w-16 sm:w-24 h-2"
                        />
                      </>
                    ) : null}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ) : null}

      <div className="bg-[hsl(var(--background)/0.55)] backdrop-blur-xl border border-[hsl(var(--border)/0.8)] rounded-full p-0 shadow-lg">
        <ReaderSettingsSheet
          open={settingsOpen}
          onOpenChange={onSettingsOpenChange}
          archiveTitle={archiveTitle}
          archiveMetadata={archiveMetadata}
          metadataTags={metadataTags}
          id={id}
          onNavigateToArchive={onNavigateToArchive}
          settingButtons={settingButtons}
          autoPlayMode={autoPlayMode}
          autoPlayInterval={autoPlayInterval}
          onAutoPlayIntervalChange={onAutoPlayIntervalChange}
          t={t}
        />
      </div>

      {!isFavorited && (
        <div className="bg-[hsl(var(--background)/0.55)] backdrop-blur-xl border border-[hsl(var(--border)/0.8)] rounded-full p-0 shadow-lg">
          <Button
            variant="ghost"
            size="sm"
            onClick={onToggleFavorite}
            className={desktopIconButtonClass}
            title={t('reader.favorite')}
          >
            <Heart className="w-4 h-4" />
          </Button>
        </div>
      )}
    </div>
  );
}
