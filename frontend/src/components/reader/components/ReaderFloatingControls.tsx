import { Button } from '@/components/ui/button';
import { Slider } from '@/components/ui/slider';
import { Heart } from 'lucide-react';
import { ReaderSettingsSheet, type ReaderSettingButton } from '@/components/reader/components/ReaderSettingsSheet';
import type { ArchiveMetadata } from '@/types/archive';
import type React from 'react';

export function ReaderFloatingControls({
  showToolbar,
  currentPage,
  totalPages,
  onChangePage,
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
  return (
    <div
      className={`
        absolute bottom-8 left-1/2 transform -translate-x-1/2 flex items-center gap-3 
        transition-all duration-250 ease-out z-50
        will-change-transform will-change-opacity
        ${showToolbar ? 'opacity-100 translate-y-0 pointer-events-auto' : 'opacity-0 translate-y-4 pointer-events-none'}
      `}
    >
      <div className="bg-background/95 backdrop-blur-sm border border-border rounded-full px-4 py-3 shadow-lg">
        <div className="flex items-center space-x-2">
          <Slider
            value={[currentPage]}
            onValueChange={(value) => onChangePage(value[0])}
            max={Math.max(0, totalPages - 1)}
            min={0}
            step={1}
            className="w-40 sm:w-64 h-2"
          />
          <span className="text-sm whitespace-nowrap font-medium text-foreground">
            {currentPage + 1}/{totalPages}
          </span>
        </div>
      </div>

      <div className="bg-background/95 backdrop-blur-sm border border-border rounded-full p-0 shadow-lg">
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
        <div className="bg-background/95 backdrop-blur-sm border border-border rounded-full p-0 shadow-lg">
          <Button
            variant="ghost"
            size="sm"
            onClick={onToggleFavorite}
            className={`
              rounded-full h-11 w-11 p-1
              transition-all duration-150 ease-out
              hover:scale-110 active:scale-95
              text-muted-foreground hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-950/20
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
