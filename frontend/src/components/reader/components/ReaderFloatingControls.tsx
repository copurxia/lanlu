import { Button } from '@/components/ui/button';
import { Slider } from '@/components/ui/slider';
import { Heart, Pause, Play, Rewind, FastForward, Volume2, VolumeX } from 'lucide-react';
import { ReaderSettingsSheet, type ReaderSettingButton } from '@/components/reader/components/ReaderSettingsSheet';
import type { ArchiveMetadata } from '@/types/archive';
import type React from 'react';

export type ReaderProgressLane = {
  id: string;
  kind: 'book' | 'video';
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
  const showFusionProgress = progressLanes.length > 0;

  return (
    <div
      className={`
        absolute bottom-8 left-1/2 transform -translate-x-1/2 flex items-center gap-3 
        transition-all duration-250 ease-out z-50
        will-change-transform will-change-opacity
        ${showToolbar ? 'opacity-100 translate-y-0 pointer-events-auto' : 'opacity-0 translate-y-4 pointer-events-none'}
      `}
    >
      {showFusionProgress ? (
        <div className="bg-background/55 backdrop-blur-xl border border-border/80 rounded-full px-3 py-2 shadow-lg">
          <div className="flex items-center gap-2">
            {progressLanes.map((lane) => {
              const Icon = lane.icon;
              const isExpanded = expandedLaneId === lane.id;
              return (
                <div key={lane.id} className="flex items-center gap-1">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => onToggleLane(lane.id)}
                    className={`
                      rounded-full h-9 w-9 p-0
                      transition-all duration-150 ease-out
                      hover:bg-white/30 hover:border hover:border-white/60 hover:text-foreground
                      ${
                        isExpanded
                          ? 'bg-white/45 text-foreground border border-white/70 shadow-[0_6px_18px_rgba(255,255,255,0.18)]'
                          : 'text-foreground/70'
                      }
                    `}
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
                    {lane.kind === 'video' ? (
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
                      trackClassName="bg-white/35 border border-white/55"
                      rangeClassName="bg-black/90"
                    />
                    <span className="text-sm whitespace-nowrap font-medium text-foreground min-w-[84px] text-right">
                      {lane.valueText ?? `${Math.round(lane.value)}/${Math.round(lane.max)}`}
                    </span>

                    {lane.kind === 'video' ? (
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
                          trackClassName="bg-white/35 border border-white/55"
                          rangeClassName="bg-black/90"
                        />
                      </>
                    ) : null}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ) : (
        <div className="bg-background/55 backdrop-blur-xl border border-border/80 rounded-full px-4 py-3 shadow-lg">
          <div className="flex items-center space-x-2">
            <Slider
              value={[currentPage]}
              onValueChange={(value) => onChangePage(value[0])}
              max={Math.max(0, totalPages - 1)}
              min={0}
              step={1}
              className="w-40 sm:w-64 h-2"
              trackClassName="bg-white/35 border border-white/55"
              rangeClassName="bg-black/90"
            />
            <span className="text-sm whitespace-nowrap font-medium text-foreground">
              {currentPage + 1}/{totalPages}
            </span>
          </div>
        </div>
      )}

      <div className="bg-background/55 backdrop-blur-xl border border-border/80 rounded-full p-0 shadow-lg">
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
        <div className="bg-background/55 backdrop-blur-xl border border-border/80 rounded-full p-0 shadow-lg">
          <Button
            variant="ghost"
            size="sm"
            onClick={onToggleFavorite}
            className={`
              rounded-full h-11 w-11 p-1
              transition-all duration-150 ease-out
              hover:scale-110 active:scale-95
              text-foreground/70 hover:text-foreground hover:bg-white/30 hover:border hover:border-white/60
              will-change-transform
            `}
            title={t('reader.favorite')}
          >
            <Heart className="w-4 h-4" />
          </Button>
        </div>
      )}
    </div>
  );
}
