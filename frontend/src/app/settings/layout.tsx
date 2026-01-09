'use client';

import { Header } from '@/components/layout/Header';
import { MobileBottomNav } from '@/components/layout/MobileBottomNav';
import { SettingsNav } from '@/components/settings/SettingsNav';
import { Settings } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';

export default function SettingsLayout({ children }: { children: React.ReactNode }) {
  const { t } = useLanguage();

  return (
    <div className="min-h-screen bg-background pb-20 lg:pb-0">
      <Header />

      <div className="container mx-auto px-4 py-8">
        {/* 标题区域 - 移动端隐藏 */}
        <div className="hidden md:flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between mb-4">
          <div className="flex items-center gap-2">
            <Settings className="w-6 h-6 text-primary" />
            <h1 className="text-2xl font-bold leading-tight">{t('settings.title')}</h1>
          </div>
          <p className="text-sm text-muted-foreground sm:text-right sm:max-w-[52ch]">
            {t('settings.description')}
          </p>
        </div>

        <div className="grid gap-6 md:grid-cols-[220px_1fr]">
          {/* 桌面端侧边栏 */}
          <aside className="hidden md:block md:sticky md:top-20 h-fit">
            <SettingsNav />
          </aside>
          <main className="min-w-0">{children}</main>
        </div>
      </div>

      <MobileBottomNav />
    </div>
  );
}
