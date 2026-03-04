import { ArchiveSearchTagBadge } from '@/components/archive/ArchiveSearchTagBadge';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Slider } from '@/components/ui/slider';
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetFooter,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet';
import { useLanguage } from '@/contexts/LanguageContext';
import { TagService } from '@/lib/services/tag-service';
import { stripNamespace } from '@/lib/utils/tag-utils';
import { Settings } from 'lucide-react';
import { useRouter } from 'next/navigation';
import type { ArchiveMetadata } from '@/types/archive';
import { useCallback, useEffect, useMemo, useState } from 'react';
import type React from 'react';

export type ReaderSettingButton = {
  key: string;
  label: string;
  icon: React.ElementType;
  active: boolean;
  disabled: boolean;
  onClick: () => void;
  tooltip: string;
};

export function ReaderSettingsSheet({
  open,
  onOpenChange,
  archiveTitle,
  archiveMetadata,
  metadataTags,
  id,
  onNavigateToArchive,
  settingButtons,
  autoPlayMode,
  autoPlayInterval,
  onAutoPlayIntervalChange,
  t,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  archiveTitle: string;
  archiveMetadata: ArchiveMetadata | null;
  metadataTags: string[];
  id: string | null;
  onNavigateToArchive: () => void;
  settingButtons: ReaderSettingButton[];
  autoPlayMode: boolean;
  autoPlayInterval: number;
  onAutoPlayIntervalChange: (seconds: number) => void;
  t: (key: string) => string;
}) {
  const router = useRouter();
  const { language } = useLanguage();
  const [isNarrowScreen, setIsNarrowScreen] = useState(false);
  const [tagTranslationMap, setTagTranslationMap] = useState<Record<string, string>>({});

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const mql = window.matchMedia('(max-width: 639px)');
    const onChange = (event: MediaQueryListEvent) => setIsNarrowScreen(event.matches);
    setIsNarrowScreen(mql.matches);
    mql.addEventListener('change', onChange);
    return () => mql.removeEventListener('change', onChange);
  }, []);

  useEffect(() => {
    if (!id) {
      setTagTranslationMap({});
      return;
    }
    let cancelled = false;
    void TagService.getTranslations(language, id)
      .then((map) => {
        if (!cancelled) setTagTranslationMap(map || {});
      })
      .catch(() => {
        if (!cancelled) setTagTranslationMap({});
      });
    return () => {
      cancelled = true;
    };
  }, [id, language]);

  const tagReverseMap = useMemo(() => {
    const reverse: Record<string, string> = {};
    for (const [canonical, translated] of Object.entries(tagTranslationMap || {})) {
      const translatedText = (translated || '').trim();
      if (!translatedText) continue;
      const idx = canonical.indexOf(':');
      if (idx > 0) {
        const namespace = canonical.slice(0, idx);
        reverse[`${namespace}:${translatedText}`] = canonical;
      } else {
        reverse[translatedText] = canonical;
      }
    }
    return reverse;
  }, [tagTranslationMap]);

  const toCanonicalTag = useCallback(
    (displayFullTag: string) => tagReverseMap[displayFullTag] || displayFullTag,
    [tagReverseMap]
  );

  const handleTagClick = useCallback(
    (displayFullTag: string) => {
      const canonical = toCanonicalTag(displayFullTag);
      const q = canonical.includes(':') ? canonical : stripNamespace(canonical);
      const trimmed = q.trim();
      if (!trimmed) return;
      const exactQuery = trimmed.endsWith('$') ? trimmed : `${trimmed}$`;
      onOpenChange(false);
      router.push(`/?q=${encodeURIComponent(exactQuery)}`);
    },
    [onOpenChange, router, toCanonicalTag]
  );

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className={`
            rounded-full h-11 w-11 p-1
            transition-all duration-150 ease-out
            hover:scale-110 active:scale-95
            text-muted-foreground hover:text-foreground hover:bg-accent
            will-change-transform
          `}
          title={t('reader.settings')}
        >
          <Settings className="h-4 w-4" />
        </Button>
      </SheetTrigger>
      <SheetContent
        side={isNarrowScreen ? 'bottom' : 'right'}
        className={
          isNarrowScreen
            ? 'flex flex-col max-h-[85vh] rounded-t-xl border-x-0 !px-4 !pt-3 !pb-[calc(env(safe-area-inset-bottom)+1rem)]'
            : 'flex flex-col max-w-sm !p-5 sm:!p-6'
        }
      >
        {isNarrowScreen && <div className="mx-auto mb-1 h-1.5 w-12 rounded-full bg-muted" />}
        <SheetHeader className="space-y-3 text-left">
          <div className="flex items-center gap-2.5">
            <Settings className="h-5 w-5 shrink-0 text-muted-foreground" />
            <div className="flex flex-col">
              <SheetTitle className="text-base">{t('reader.settings')}</SheetTitle>
              {archiveTitle ? (
                <div className="max-w-[240px] truncate text-xs text-muted-foreground">{archiveTitle}</div>
              ) : null}
            </div>
          </div>
        </SheetHeader>

        <div className="mt-4 flex-1 space-y-4 overflow-y-auto pr-1">
          {archiveMetadata ? (
            <div className="space-y-3 rounded-xl border border-border/60 bg-muted/20 p-4">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-medium">{t('archive.summary')}</span>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  className="h-8 rounded-lg px-3"
                  disabled={!id}
                  onClick={onNavigateToArchive}
                >
                  {t('archive.details')}
                </Button>
              </div>
              <div className="text-xs leading-relaxed text-muted-foreground whitespace-pre-wrap line-clamp-4">
                {archiveMetadata.summary ? archiveMetadata.summary : t('archive.noSummary')}
              </div>
              <div className="space-y-2">
                <span className="text-sm font-medium">{t('archive.tags')}</span>
                {metadataTags.length > 0 ? (
                  <div className="flex flex-wrap gap-1.5 max-h-28 overflow-y-auto overflow-x-hidden pb-1 pr-1">
                    {metadataTags.slice(0, 10).map((tag, index) => {
                      const canonical = toCanonicalTag(tag);
                      return (
                        <ArchiveSearchTagBadge
                          key={`${tag}-${index}`}
                          displayFullTag={tag}
                          canonicalFullTag={canonical}
                          className="max-w-[240px]"
                          onClick={() => handleTagClick(tag)}
                        />
                      );
                    })}
                    {metadataTags.length > 10 ? (
                      <Badge variant="secondary" className="text-xs whitespace-nowrap">
                        +{metadataTags.length - 10}
                      </Badge>
                    ) : null}
                  </div>
                ) : (
                  <div className="text-xs text-muted-foreground">{t('archive.noTags')}</div>
                )}
              </div>
            </div>
          ) : null}

          <div className="flex flex-col gap-2.5">
            {settingButtons.map((setting) => {
              const Icon = setting.icon as React.ElementType;
              const borderClass = setting.active
                ? 'border-primary/70 bg-primary/10 text-primary'
                : 'border-border/70 bg-background/90 text-foreground hover:border-foreground/50 hover:bg-accent/30';
              const disabledClass = setting.disabled
                ? 'opacity-55 cursor-not-allowed hover:border-border/70 hover:bg-background/90'
                : '';

              return (
                <Button
                  key={setting.key}
                  variant="ghost"
                  size="sm"
                  onClick={setting.onClick}
                  disabled={setting.disabled}
                  title={setting.tooltip}
                  className={`
                    flex items-center w-full gap-3 rounded-xl border px-3.5 py-3 text-left text-sm font-medium
                    transition-colors duration-150 hover:shadow-sm
                    ${borderClass}
                    ${disabledClass}
                  `}
                >
                  <Icon
                    className={`h-5 w-5 shrink-0 ${
                      setting.disabled
                        ? 'text-muted-foreground/50'
                        : setting.active
                          ? 'text-primary'
                          : 'text-muted-foreground'
                    }`}
                  />
                  <span className="flex-1">{setting.label}</span>
                  <span
                    className={`h-2.5 w-2.5 rounded-full ${
                      setting.disabled
                        ? 'bg-muted-foreground/25'
                        : setting.active
                          ? 'bg-primary'
                          : 'bg-muted-foreground/35'
                    }`}
                    aria-hidden
                  />
                </Button>
              );
            })}
          </div>

          {autoPlayMode && (
            <div className="space-y-3 rounded-xl border border-border/60 bg-muted/20 p-4">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">{t('reader.pageInterval')}</span>
                <span className="text-sm text-muted-foreground">{autoPlayInterval}秒</span>
              </div>
              <Slider
                value={[autoPlayInterval]}
                onValueChange={(value) => onAutoPlayIntervalChange(value[0])}
                max={10}
                min={1}
                step={1}
                className="w-full"
              />
            </div>
          )}
        </div>

        <SheetFooter className="mt-5 border-t border-border/60 pt-4">
          <SheetClose asChild>
            <Button variant="outline" className="w-full justify-center rounded-xl">
              {t('common.close')}
            </Button>
          </SheetClose>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}
