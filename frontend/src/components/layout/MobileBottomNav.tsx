'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { BookOpen, Home, Settings, Shuffle } from 'lucide-react';
import { useCallback, useState } from 'react';
import { ArchiveService } from '@/lib/services/archive-service';
import { useLanguage } from '@/contexts/LanguageContext';
import { cn } from '@/lib/utils/utils';

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
      const randomArchives = await ArchiveService.getRandom({ count: 1 });
      if (randomArchives.length > 0) {
        router.push(`/reader?id=${randomArchives[0].arcid}`);
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
        paddingTop: '0.25rem',
        paddingBottom: 'calc(env(safe-area-inset-bottom) + 0.5rem)',
      }}
      aria-label={t('common.menu')}
    >
      <div className="mx-auto grid h-16 max-w-md grid-cols-4">
        <Link
          href="/"
          className={cn(
            'flex flex-col items-center justify-center gap-1 text-xs transition-colors',
            isActiveHome ? 'text-primary' : 'text-muted-foreground hover:text-foreground'
          )}
          aria-current={isActiveHome ? 'page' : undefined}
        >
          <Home className="h-5 w-5" />
          <span>{t('navigation.home')}</span>
        </Link>

        <Link
          href="/library?tab=favorites"
          className={cn(
            'flex flex-col items-center justify-center gap-1 text-xs transition-colors',
            isActiveLibrary ? 'text-primary' : 'text-muted-foreground hover:text-foreground'
          )}
          aria-current={isActiveLibrary ? 'page' : undefined}
        >
          <BookOpen className="h-5 w-5" />
          <span>{t('navigation.library')}</span>
        </Link>

        <button
          type="button"
          onClick={handleRandomRead}
          disabled={randomLoading}
          className={cn(
            'flex flex-col items-center justify-center gap-1 text-xs transition-colors',
            randomLoading ? 'text-muted-foreground' : 'text-muted-foreground hover:text-foreground'
          )}
          aria-label={t('navigation.random')}
        >
          <Shuffle className={cn('h-5 w-5', randomLoading && 'animate-spin')} />
          <span>{t('navigation.random')}</span>
        </button>

        <Link
          href="/settings"
          className={cn(
            'flex flex-col items-center justify-center gap-1 text-xs transition-colors',
            isActiveSettings ? 'text-primary' : 'text-muted-foreground hover:text-foreground'
          )}
          aria-current={isActiveSettings ? 'page' : undefined}
        >
          <Settings className="h-5 w-5" />
          <span>{t('navigation.settings')}</span>
        </Link>
      </div>
    </nav>
  );
}
