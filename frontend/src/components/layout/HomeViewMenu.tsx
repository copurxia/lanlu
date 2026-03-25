'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { LayoutGrid, List, MessageCircle, MessageSquareText, Rows3 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useLanguage } from '@/contexts/LanguageContext';
import { appEvents, AppEvents } from '@/lib/utils/events';
import {
  type HomeViewMode,
  DEFAULT_HOME_VIEW_MODE,
  HOME_VIEW_MODE_STORAGE_KEY,
  normalizeHomeViewMode,
} from '@/lib/utils/constants';

type ViewOption = {
  value: HomeViewMode;
  labelKey: string;
};

const VIEW_OPTIONS: ViewOption[] = [
  { value: 'category-rows', labelKey: 'home.categoryRowsView' },
  { value: 'masonry', labelKey: 'home.masonryView' },
  { value: 'list', labelKey: 'home.listView' },
  { value: 'tweet', labelKey: 'home.tweetView' },
  { value: 'channel', labelKey: 'home.channelView' },
];

function getViewIcon(mode: HomeViewMode) {
  if (mode === 'masonry') return LayoutGrid;
  if (mode === 'list') return List;
  if (mode === 'tweet') return MessageSquareText;
  if (mode === 'channel') return MessageCircle;
  return Rows3;
}

export function HomeViewMenu() {
  const { t } = useLanguage();
  const [viewMode, setViewMode] = useState<HomeViewMode>(() => {
    if (typeof window === 'undefined') return DEFAULT_HOME_VIEW_MODE;
    return normalizeHomeViewMode(window.localStorage.getItem(HOME_VIEW_MODE_STORAGE_KEY));
  });

  useEffect(() => {
    const handleViewModeChange = (nextMode?: HomeViewMode) => {
      setViewMode(normalizeHomeViewMode(nextMode));
    };

    appEvents.on(AppEvents.HOME_VIEW_MODE_CHANGE, handleViewModeChange);
    return () => appEvents.off(AppEvents.HOME_VIEW_MODE_CHANGE, handleViewModeChange);
  }, []);

  const applyModeChange = useCallback((nextMode: HomeViewMode) => {
    setViewMode(nextMode);

    if (typeof window !== 'undefined') {
      window.localStorage.setItem(HOME_VIEW_MODE_STORAGE_KEY, nextMode);
    }

    appEvents.emit(AppEvents.HOME_VIEW_MODE_CHANGE, nextMode);
  }, []);

  const currentIndex = useMemo(() => {
    const index = VIEW_OPTIONS.findIndex((item) => item.value === viewMode);
    return index >= 0 ? index : 0;
  }, [viewMode]);

  const currentLabel = useMemo(() => t(VIEW_OPTIONS[currentIndex].labelKey), [currentIndex, t]);
  const nextMode = useMemo<HomeViewMode>(() => {
    return VIEW_OPTIONS[(currentIndex + 1) % VIEW_OPTIONS.length].value;
  }, [currentIndex]);
  const nextLabel = useMemo(() => {
    const nextIndex = (currentIndex + 1) % VIEW_OPTIONS.length;
    return t(VIEW_OPTIONS[nextIndex].labelKey);
  }, [currentIndex, t]);

  const handleCycleView = useCallback(() => {
    applyModeChange(nextMode);
  }, [applyModeChange, nextMode]);

  const TriggerIcon = getViewIcon(viewMode);

  return (
    <Button
      variant="ghost"
      size="icon"
      className="h-9 w-9 rounded-md text-muted-foreground hover:bg-muted hover:text-foreground"
      title={`${t('home.switchView')} · ${currentLabel} -> ${nextLabel}`}
      aria-label={`${t('home.switchView')} · ${currentLabel} -> ${nextLabel}`}
      onClick={handleCycleView}
    >
      <TriggerIcon className="h-4 w-4" />
      <span className="sr-only">{`${t('home.switchView')} · ${currentLabel} -> ${nextLabel}`}</span>
    </Button>
  );
}
