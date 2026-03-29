'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { BookOpen, Home, Settings, Shuffle } from 'lucide-react';
import { useCallback, useState } from 'react';
import { RecommendationService } from '@/lib/services/recommendation-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { cn } from '@/lib/utils/utils';
import { buildReaderPath } from '@/lib/utils/reader';

export function MobileBottomNav() {
  const { t } = useLanguage();
  const pathname = usePathname() ?? '';
  const router = useRouter();
  const [randomLoading, setRandomLoading] = useState(false);

  const isActiveHome = pathname === '/';
  const isActiveLibrary = pathname === '/library';
  const isActiveSettings = pathname === '/settings' || pathname.startsWith('/settings/');

  const handleRandomRead = useCallback(async () => {
    try {
      setRandomLoading(true);
      const recommendations = await RecommendationService.getDiscover({ count: 8 });
      const archiveTarget = recommendations.find((item) => 'arcid' in item);
      if (archiveTarget && 'arcid' in archiveTarget) {
        await RecommendationService.recordInteraction({
          scene: 'discover',
          item_type: 'archive',
          item_id: archiveTarget.arcid,
          interaction_type: 'open_reader',
        });
        router.push(buildReaderPath(archiveTarget.arcid, archiveTarget.progress));
        return;
      }
      const tankTarget = recommendations.find((item) => 'tankoubon_id' in item && item.children?.[0]);
      if (tankTarget && 'tankoubon_id' in tankTarget) {
        const firstArchiveId = tankTarget.children?.[0];
        if (firstArchiveId) {
          await RecommendationService.recordInteraction({
            scene: 'discover',
            item_type: 'tankoubon',
            item_id: tankTarget.tankoubon_id,
            interaction_type: 'open_reader',
          });
          router.push(buildReaderPath(firstArchiveId));
        }
      }
    } catch (error) {
      console.error('Failed to get random archive:', error);
    } finally {
      setRandomLoading(false);
    }
  }, [router]);

  return (
    <nav
      className="lg:hidden fixed bottom-0 left-0 right-0 z-50 border-t border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80"
      style={{
        paddingTop: '0.125rem',
        // Keep iOS safe-area support while reducing overall bar height.
        paddingBottom: 'calc(env(safe-area-inset-bottom) + 0.25rem)',
      }}
      aria-label={t('common.menu')}
    >
      <div className="mx-auto grid h-14 max-w-md grid-cols-4">
        <Link
          href="/"
          className={cn(
            'flex flex-col items-center justify-center gap-0.5 text-xs transition-colors',
            isActiveHome ? 'text-primary' : 'text-muted-foreground hover:text-foreground'
          )}
          aria-current={isActiveHome ? 'page' : undefined}
        >
          <Home className="h-4 w-4" />
          <span>{t('navigation.home')}</span>
        </Link>

        <Link
          href="/library?tab=favorites"
          className={cn(
            'flex flex-col items-center justify-center gap-0.5 text-xs transition-colors',
            isActiveLibrary ? 'text-primary' : 'text-muted-foreground hover:text-foreground'
          )}
          aria-current={isActiveLibrary ? 'page' : undefined}
        >
          <BookOpen className="h-4 w-4" />
          <span>{t('navigation.library')}</span>
        </Link>

        <button
          type="button"
          onClick={handleRandomRead}
          disabled={randomLoading}
          className={cn(
            'flex flex-col items-center justify-center gap-0.5 text-xs transition-colors',
            randomLoading ? 'text-muted-foreground' : 'text-muted-foreground hover:text-foreground'
          )}
          aria-label={t('navigation.random')}
        >
          <Shuffle className={cn('h-4 w-4', randomLoading && 'animate-spin')} />
          <span>{t('navigation.random')}</span>
        </button>

        <Link
          href="/settings"
          className={cn(
            'flex flex-col items-center justify-center gap-0.5 text-xs transition-colors',
            isActiveSettings ? 'text-primary' : 'text-muted-foreground hover:text-foreground'
          )}
          aria-current={isActiveSettings ? 'page' : undefined}
        >
          <Settings className="h-4 w-4" />
          <span>{t('navigation.settings')}</span>
        </Link>
      </div>
    </nav>
  );
}
