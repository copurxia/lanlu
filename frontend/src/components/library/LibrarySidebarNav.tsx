'use client';

import { BookOpen, Heart, History } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { Badge } from '@/components/ui/badge';
import { TabsList, TabsTrigger } from '@/components/ui/tabs';
import { cn } from '@/lib/utils/utils';

interface LibrarySidebarNavProps {
  favoriteCount: number;
  historyCountLabel: string;
}

const triggerClassName = cn(
  'h-auto w-full justify-start rounded-lg px-3 py-2 text-sm font-medium shadow-none',
  'text-muted-foreground hover:bg-muted hover:text-foreground',
  'data-[state=active]:bg-primary data-[state=active]:text-primary-foreground data-[state=active]:shadow-none'
);

export function LibrarySidebarNav({ favoriteCount, historyCountLabel }: LibrarySidebarNavProps) {
  const { t } = useLanguage();

  return (
    <div className="h-full overflow-y-auto bg-background">
      <div className="space-y-6 px-4 pb-4">
        <section className="space-y-2">
          <h2 className="px-3 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {t('library.title')}
          </h2>
          <TabsList className="flex h-auto w-full flex-col items-stretch gap-1 bg-transparent p-0">
            <TabsTrigger value="favorites" className={triggerClassName}>
              <div className="flex w-full items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <Heart className="h-4 w-4" />
                  <span>{t('library.tabs.favorites')}</span>
                </div>
                <Badge variant="secondary" className="shrink-0">
                  {favoriteCount}
                </Badge>
              </div>
            </TabsTrigger>

            <TabsTrigger value="history" className={triggerClassName}>
              <div className="flex w-full items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <History className="h-4 w-4" />
                  <span>{t('library.tabs.history')}</span>
                </div>
                <Badge variant="secondary" className="shrink-0">
                  {historyCountLabel}
                </Badge>
              </div>
            </TabsTrigger>
          </TabsList>
        </section>

        <section className="space-y-2">
          <h2 className="px-3 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {t('navigation.library')}
          </h2>
          <div className="rounded-lg border border-border/70 bg-muted/20 px-3 py-3 text-sm text-muted-foreground">
            <div className="flex items-center gap-2 text-foreground">
              <BookOpen className="h-4 w-4" />
              <span>{t('library.title')}</span>
            </div>
            <p className="mt-2 leading-6">{t('favorites.noFavoritesHint')}</p>
          </div>
        </section>
      </div>
    </div>
  );
}
