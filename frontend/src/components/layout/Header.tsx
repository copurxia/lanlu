'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { SearchBar } from '@/components/search/SearchBar';
import { ArchiveService } from '@/lib/archive-service';
import { ThemeToggle, ThemeButton } from '@/components/theme/theme-toggle';
import { LanguageButton } from '@/components/language/LanguageToggle';
import { UserMenu } from '@/components/user/UserMenu';
import { Menu, X, Home, Heart, Shuffle, Settings, ArrowLeft, LogIn } from 'lucide-react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useLanguage } from '@/contexts/LanguageContext';

export function Header() {
  const { t } = useLanguage();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [randomLoading, setRandomLoading] = useState(false);
  const pathname = usePathname();
  const router = useRouter();
  const showBackButton = pathname !== '/';

  const handleBack = () => {
    if (typeof window !== 'undefined' && window.history.length > 1) {
      router.back();
      return;
    }
    router.push('/');
  };

  const toggleMobileMenu = () => {
    setMobileMenuOpen(!mobileMenuOpen);
  };

  const handleRandomRead = async () => {
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
    { name: t('settings.favorites'), href: '/settings/favorites', icon: Heart },
    { name: t('navigation.random'), href: '#', icon: Shuffle, action: handleRandomRead },
  ];

  const mobileNavigation = [
    ...navigation,
    { name: t('navigation.settings'), href: '/settings', icon: Settings },
  ];

  return (
    <header className="bg-background border-b border-border sticky top-0 z-50">
      <div className="container mx-auto px-0.5 py-3">
        <div className="flex items-center justify-between">
          {/* Logo和标题 */}
          <div className="flex items-center space-x-4">
            <Button
              variant="ghost"
              size="sm"
              className="md:hidden"
              onClick={toggleMobileMenu}
            >
              {mobileMenuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </Button>

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
            
            <Link href="/" className="flex items-center space-x-2">
              <div className="w-8 h-8 bg-primary rounded-md flex items-center justify-center">
                <span className="text-primary-foreground font-bold text-sm">L4C</span>
              </div>
              <span className="font-semibold text-lg hidden sm:inline-block">
                Lanraragi4CJ
              </span>
            </Link>
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

        {/* 搜索栏 - 移动端显示 */}
        <div className="md:hidden mt-3">
          <SearchBar />
        </div>
      </div>

      {/* 移动端导航菜单 */}
      {mobileMenuOpen && (
        <div className="md:hidden border-t border-border bg-background">
          <nav className="container mx-auto px-0.5 py-2">
            {mobileNavigation.map((item) => {
              const Icon = item.icon;
              if (item.action) {
                return (
                  <Button
                    key={item.name}
                    variant="ghost"
                    size="sm"
                    onClick={() => {
                      item.action();
                      setMobileMenuOpen(false);
                    }}
                    disabled={randomLoading}
                    className={`flex items-center space-x-3 px-3 py-3 rounded-md text-base font-medium transition-colors w-full justify-start ${
                      randomLoading
                        ? 'text-muted-foreground'
                        : 'text-muted-foreground hover:text-foreground hover:bg-muted'
                    }`}
                  >
                    <Icon className={`h-5 w-5 ${randomLoading ? 'animate-spin' : ''}`} />
                    <span>{item.name}</span>
                  </Button>
                );
              }
              return (
                <Link
                  key={item.name}
                  href={item.href}
                  className={`flex items-center space-x-3 px-3 py-3 rounded-md text-base font-medium transition-colors ${
                    pathname === item.href
                      ? 'bg-primary text-primary-foreground'
                      : 'text-muted-foreground hover:text-foreground hover:bg-muted'
                  }`}
                  onClick={() => setMobileMenuOpen(false)}
                >
                  <Icon className="h-5 w-5" />
                  <span>{item.name}</span>
                </Link>
              );
            })}
            <div className="flex items-center justify-center space-x-2 px-3 py-3">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  router.push('/login');
                  setMobileMenuOpen(false);
                }}
                className="flex items-center space-x-2 px-3 py-2 rounded-md text-base font-medium transition-colors w-full justify-start text-muted-foreground hover:text-foreground hover:bg-muted"
              >
                <LogIn className="h-5 w-5" />
                <span>{t('auth.login')}</span>
              </Button>
              <ThemeButton />
              <LanguageButton />
            </div>
          </nav>
        </div>
      )}
    </header>
  );
}
