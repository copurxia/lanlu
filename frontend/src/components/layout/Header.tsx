'use client';

import { Suspense, useState, useEffect, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { SearchBar, type SearchBarHandle } from '@/components/search/SearchBar';
import { ArchiveService } from '@/lib/services/archive-service';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { resolveArchiveAssetUrl } from '@/lib/utils/archive-assets';
import { ThemeToggle, ThemeButton } from '@/components/theme/theme-toggle';
import { LanguageButton } from '@/components/language/LanguageButton';
import { UserMenu } from '@/components/user/UserMenu';
import { AppSidebarNav } from '@/components/layout/AppSidebarNav';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Menu, Home, Shuffle, Settings, ArrowLeft, LogIn, Filter, Search } from 'lucide-react';
import Link from 'next/link';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { useAppBack } from '@/hooks/use-app-back';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { useServerInfo } from '@/contexts/ServerInfoContext';
import { Logo } from '@/components/brand/Logo';
import { appEvents, AppEvents } from '@/lib/utils/events';

function HeaderPageClearlogo({
  pathname,
  language,
}: {
  pathname: string | null | undefined;
  language: string;
}) {
  const searchParams = useSearchParams();
  const [pageClearlogoUrl, setPageClearlogoUrl] = useState('');
  const [pageClearlogoAlt, setPageClearlogoAlt] = useState('');
  const detailId = String(searchParams?.get('id') || '').trim();

  useEffect(() => {
    const onArchiveDetail = Boolean(pathname?.startsWith('/archive'));
    const onTankoubonDetail = Boolean(pathname?.startsWith('/tankoubon'));
    if (!detailId || (!onArchiveDetail && !onTankoubonDetail)) {
      setPageClearlogoUrl('');
      setPageClearlogoAlt('');
      return;
    }

    let cancelled = false;
    setPageClearlogoUrl('');
    setPageClearlogoAlt('');

    const loadClearlogo = async () => {
      try {
        if (onArchiveDetail) {
          const metadata = await ArchiveService.getMetadata(detailId, language);
          if (cancelled) return;
          setPageClearlogoUrl(resolveArchiveAssetUrl(metadata, 'clearlogo', metadata.clearlogo));
          setPageClearlogoAlt((metadata.title || '').trim());
          return;
        }

        const tank = await TankoubonService.getMetadata(detailId);
        if (cancelled) return;
        setPageClearlogoUrl(resolveArchiveAssetUrl(tank, 'clearlogo', tank.clearlogo));
        setPageClearlogoAlt(String(tank.title || '').trim());
      } catch {
        if (cancelled) return;
        setPageClearlogoUrl('');
        setPageClearlogoAlt('');
      }
    };

    void loadClearlogo();

    return () => {
      cancelled = true;
    };
  }, [detailId, language, pathname]);

  if (!pageClearlogoUrl) return null;

  return (
    <span className="flex h-5 max-w-[110px] shrink-0 items-center sm:h-6 sm:max-w-[150px] md:h-7 md:max-w-none">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={pageClearlogoUrl}
        alt={pageClearlogoAlt || 'clearlogo'}
        className="h-full w-auto max-w-full object-contain"
        loading="lazy"
        decoding="async"
      />
    </span>
  );
}

export function Header() {
  const { t, language } = useLanguage();
  const { serverName, serverInfo } = useServerInfo();
  const headerRef = useRef<HTMLElement | null>(null);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [mobileSearchOpen, setMobileSearchOpen] = useState(false);
  const mobileSearchRef = useRef<SearchBarHandle>(null);
  const [randomLoading, setRandomLoading] = useState(false);
  const [mounted, setMounted] = useState(false);
  const pathname = usePathname();
  const router = useRouter();
  const appBack = useAppBack();
  const { token } = useAuth();
  const isSettingsPage = pathname?.startsWith('/settings');
  const isLibraryPage = pathname?.startsWith('/library');
  const showBackButton = pathname !== '/' && !isSettingsPage && !isLibraryPage;

  useEffect(() => {
    setMounted(true);
  }, []);

  // Expose the header height as a CSS variable so pages can size their scroll containers
  // without hard-coding a pixel/rem value. This prevents the "white strip" body scroll.
  useEffect(() => {
    if (!mounted) return;
    if (typeof window === 'undefined') return;
    if (!headerRef.current) return;

    const el = headerRef.current;
    const root = document.documentElement;

    const update = () => {
      // offsetHeight is stable for sticky elements and includes padding/borders.
      root.style.setProperty('--app-header-height', `${el.offsetHeight}px`);
    };

    update();

    const ro = new ResizeObserver(() => update());
    ro.observe(el);
    window.addEventListener('resize', update);

    return () => {
      ro.disconnect();
      window.removeEventListener('resize', update);
    };
  }, [mounted]);

  // Close the mobile search mode on navigation.
  useEffect(() => {
    setMobileSearchOpen(false);
  }, [pathname]);

  const handleBack = () => {
    if (!mounted) return;
    appBack('/');
  };

  const handleRandomRead = async () => {
    if (!mounted) return;
    try {
      setRandomLoading(true);
      const randomArchives = await ArchiveService.getRandom({ count: 1, groupby_tanks: false });
      if (randomArchives.length > 0) {
        const randomItem = randomArchives[0];
        if ('arcid' in randomItem) {
          router.push(`/reader?id=${randomItem.arcid}`);
        }
      }
    } catch (error) {
      console.error('Failed to get random archive:', error);
    } finally {
      setRandomLoading(false);
    }
  };


  const navigation = [
    { name: t('navigation.home'), href: '/', icon: Home },
    { name: t('navigation.random'), href: '#', icon: Shuffle, action: handleRandomRead },
  ];

  return (
    <header
      ref={headerRef}
      className="sticky top-0 z-50 border-b border-border/70 bg-background/70 backdrop-blur-md dark:bg-background/70"
    >
      {/* Slightly shorter top bar on mobile to match typical 48-56px app headers. */}
      <div className="mx-auto px-4 py-2 sm:py-3">
        <div className="relative flex items-center justify-between">
          {/* Logo和标题 */}
          <div
            className={`
              flex items-center gap-3
              transition-opacity duration-200
              ${mobileSearchOpen ? 'opacity-0 pointer-events-none md:opacity-100 md:pointer-events-auto' : 'opacity-100'}
            `}
          >
            {(isSettingsPage || pathname === '/') && (
              <Button
                variant="ghost"
                size="sm"
                className="md:hidden"
                onClick={() => setMobileMenuOpen(true)}
              >
                <Menu className="h-5 w-5" />
              </Button>
            )}

            {showBackButton && (
              <Button
                variant="ghost"
                size="sm"
                onClick={handleBack}
                className="px-2"
                aria-label={t('common.back')}
                title={t('common.back')}
              >
                <ArrowLeft className="h-4 w-4" />
              </Button>
            )}

            <button
              onClick={() => {
                appEvents.emit(AppEvents.SEARCH_RESET);
                router.push('/');
              }}
              className="flex items-center gap-2 hover:opacity-80 transition-opacity"
            >
              <Logo width={32} height={32} />
              <span className="font-semibold text-lg hidden sm:inline-block">
                {serverName}
              </span>
            </button>
            {serverInfo?.motd && (
              <span className="text-sm text-muted-foreground hidden md:inline-block max-w-[250px] truncate" title={serverInfo.motd}>
                · {serverInfo.motd}
              </span>
            )}
            <Suspense fallback={null}>
              <HeaderPageClearlogo pathname={pathname} language={language} />
            </Suspense>
          </div>

          {/* 移动端：搜索模式（点击图标后独占顶栏） */}
          <div
            className={`
              md:hidden
              absolute inset-0
              flex items-center gap-2 min-w-0
              bg-background/70 backdrop-blur-md dark:bg-background/70
              transition-all duration-200 ease-out
              ${mobileSearchOpen ? 'opacity-100 translate-y-0 pointer-events-auto' : 'opacity-0 -translate-y-2 pointer-events-none'}
            `}
            onBlurCapture={(e) => {
              // Auto-hide when the search input loses focus (tap outside).
              if (!mobileSearchOpen) return;
              const next = e.relatedTarget as Node | null;
              if (next && e.currentTarget.contains(next)) return;
              setMobileSearchOpen(false);
            }}
          >
            <div className="flex-1 min-w-0">
              <SearchBar
                ref={mobileSearchRef}
                autoFocus={mobileSearchOpen}
                compact={false}
                onSubmitted={() => setMobileSearchOpen(false)}
              />
            </div>
            {pathname === '/' && (
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="h-10 w-10 flex-shrink-0"
                onClick={() => appEvents.emit(AppEvents.FILTER_OPEN)}
                aria-label={t('common.filter')}
                title={t('common.filter')}
              >
                <Filter className="h-5 w-5" />
              </Button>
            )}
          </div>

          {/* 搜索栏 - 桌面端显示 */}
          <div className="hidden md:flex flex-1 max-w-xl mx-8 items-center gap-2">
            <div className="min-w-0 flex-1">
              <SearchBar />
            </div>
            {pathname === '/' && (
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="h-10 w-10 flex-shrink-0"
                onClick={() => appEvents.emit(AppEvents.FILTER_OPEN)}
                aria-label={t('common.filter')}
                title={t('common.filter')}
              >
                <Filter className="h-5 w-5" />
              </Button>
            )}
          </div>

          {/* 导航菜单 - 桌面端显示 */}
          <nav className="hidden md:flex items-center space-x-2">
            {/* Hide duplicated "Home/Random" actions when the mobile bottom nav is visible (<lg). */}
            <div className="hidden lg:flex items-center space-x-2">
              {navigation.map((item) => {
                const Icon = item.icon;
                if (item.action) {
                  return (
                    <Button
                      key={item.name}
                      variant="ghost"
                      size="sm"
                      onClick={item.action}
                      disabled={randomLoading}
                      className={`flex items-center space-x-2 px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                        randomLoading
                          ? 'text-muted-foreground'
                          : 'text-muted-foreground hover:text-foreground hover:bg-muted'
                      }`}
                    >
                      <Icon className={`h-4 w-4 ${randomLoading ? 'animate-spin' : ''}`} />
                      <span>{item.name}</span>
                    </Button>
                  );
                }
                return (
                  <Link
                    key={item.name}
                    href={item.href}
                    className={`flex items-center space-x-2 px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                      pathname === item.href
                        ? 'bg-primary text-primary-foreground'
                        : 'text-muted-foreground hover:text-foreground hover:bg-muted'
                    }`}
                  >
                    <Icon className="h-4 w-4" />
                    <span>{item.name}</span>
                  </Link>
                );
              })}
            </div>
            <UserMenu />
            <LanguageButton />
            <ThemeToggle />
          </nav>

          {/* 移动端右侧按钮组 - 用户头像、主题、语言 */}
          <div
            className={`
              md:hidden flex items-center space-x-1
              transition-opacity duration-200
              ${mobileSearchOpen ? 'opacity-0 pointer-events-none' : 'opacity-100'}
            `}
          >
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => {
                // Focus must happen in the same user gesture on some mobile browsers.
                mobileSearchRef.current?.focus();
                setMobileSearchOpen(true);
              }}
              aria-label={t('common.search')}
              title={t('common.search')}
            >
              <Search className="h-5 w-5" />
            </Button>
            <UserMenu />
            <ThemeButton />
            <LanguageButton />
          </div>
        </div>
      </div>

      {/* 移动端：侧边栏菜单 */}
      {(isSettingsPage || pathname === '/') && (
        <Sheet open={mobileMenuOpen} onOpenChange={setMobileMenuOpen}>
          {mobileMenuOpen && (
            <SheetContent side="left" className="w-[280px] p-0 flex flex-col">
              <div className="px-4 pt-4">
                <SheetTitle className="flex items-center gap-2">
                  {isSettingsPage ? (
                    <>
                      <Settings className="w-5 h-5" />
                      {t('settings.title')}
                    </>
                  ) : (
                    <>
                      <Home className="w-5 h-5" />
                      {t('navigation.home')}
                    </>
                  )}
                </SheetTitle>
              </div>
              <AppSidebarNav
                mode={isSettingsPage ? 'settings' : 'home'}
                fetchCategories={!isSettingsPage}
                onNavigate={() => setMobileMenuOpen(false)}
                className="flex-1"
              />

              {!token && (
                <div className="px-4 pb-4">
                  <Button
                    variant="ghost"
                    onClick={() => {
                      router.push('/login');
                      setMobileMenuOpen(false);
                    }}
                    className="flex items-center gap-2 px-3 py-2 rounded-md text-sm font-medium transition-colors justify-start text-muted-foreground hover:text-foreground hover:bg-muted w-full"
                  >
                    <LogIn className="h-4 w-4" />
                    <span>{t('auth.login')}</span>
                  </Button>
                </div>
              )}

              <div className="flex items-center gap-2 pt-3 border-t border-border px-4 pb-4">
                <ThemeButton />
                <LanguageButton />
              </div>
            </SheetContent>
          )}
        </Sheet>
      )}
    </header>
  );
}
