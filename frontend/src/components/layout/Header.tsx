'use client';

import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { SearchBar } from '@/components/search/SearchBar';
import { ArchiveService } from '@/lib/services/archive-service';
import { ThemeToggle, ThemeButton } from '@/components/theme/theme-toggle';
import { LanguageButton } from '@/components/language/LanguageButton';
import { UserMenu } from '@/components/user/UserMenu';
import { SettingsNav } from '@/components/settings/SettingsNav';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Menu, Home, Shuffle, Settings, ArrowLeft, LogIn } from 'lucide-react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { useServerInfo } from '@/contexts/ServerInfoContext';
import { Logo } from '@/components/brand/Logo';
import { appEvents, AppEvents } from '@/lib/utils/events';

export function Header() {
  const { t } = useLanguage();
  const { serverName, serverInfo } = useServerInfo();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [randomLoading, setRandomLoading] = useState(false);
  const [mounted, setMounted] = useState(false);
  const pathname = usePathname();
  const router = useRouter();
  const { token } = useAuth();
  const showBackButton = pathname !== '/';
  const isSettingsPage = pathname?.startsWith('/settings');

  useEffect(() => {
    setMounted(true);
  }, []);

  const handleBack = () => {
    if (!mounted) return;
    if (typeof window !== 'undefined' && window.history.length > 1) {
      router.back();
      return;
    }
    router.push('/');
  };

  const handleRandomRead = async () => {
    if (!mounted) return;
    try {
      setRandomLoading(true);
      const randomArchives = await ArchiveService.getRandom({ count: 1 });
      if (randomArchives.length > 0) {
        const randomArchive = randomArchives[0];
        router.push(`/reader?id=${randomArchive.arcid}`);
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
    <header className="bg-background border-b border-border sticky top-0 z-50">
      <div className="mx-auto px-4 py-3">
        <div className="flex items-center justify-between">
          {/* Logo和标题 */}
          <div className="flex items-center gap-3">
            {isSettingsPage && (
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
          </div>

          {/* 搜索栏 - 桌面端显示 */}
          <div className="hidden md:flex flex-1 max-w-md mx-8">
            <SearchBar />
          </div>

          {/* 导航菜单 - 桌面端显示 */}
          <nav className="hidden md:flex items-center space-x-2">
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
            <UserMenu />
            <LanguageButton />
            <ThemeToggle />
          </nav>

          {/* 移动端右侧按钮组 - 用户头像、主题、语言 */}
          <div className="md:hidden flex items-center space-x-1">
            <UserMenu />
            <ThemeButton />
            <LanguageButton />
          </div>
        </div>

      </div>

      {/* 移动端：侧边栏菜单仅出现在 settings */}
      {isSettingsPage && (
        <Sheet open={mobileMenuOpen} onOpenChange={setMobileMenuOpen}>
          {mobileMenuOpen && (
            <SheetContent side="left" className="w-[280px]">
              <SheetHeader>
                <SheetTitle className="flex items-center gap-2">
                  <Settings className="w-5 h-5" />
                  {t('settings.title')}
                </SheetTitle>
              </SheetHeader>
              <div className="mt-4 flex flex-col gap-4">
                <SettingsNav onNavigate={() => setMobileMenuOpen(false)} />

                {!token && (
                  <Button
                    variant="ghost"
                    onClick={() => {
                      router.push('/login');
                      setMobileMenuOpen(false);
                    }}
                    className="flex items-center gap-2 px-3 py-2 rounded-md text-sm font-medium transition-colors justify-start text-muted-foreground hover:text-foreground hover:bg-muted"
                  >
                    <LogIn className="h-4 w-4" />
                    <span>{t('auth.login')}</span>
                  </Button>
                )}

                {/* 底部工具栏 */}
                <div className="flex items-center gap-2 pt-3 border-t border-border">
                  <ThemeButton />
                  <LanguageButton />
                </div>
              </div>
            </SheetContent>
          )}
        </Sheet>
      )}
    </header>
  );
}
