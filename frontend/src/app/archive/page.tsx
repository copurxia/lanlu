'use client';

import { Suspense } from 'react';
import { Header } from '@/components/layout/Header';
import { MobileBottomNav } from '@/components/layout/MobileBottomNav';
import { useLanguage } from '@/contexts/LanguageContext';
import { ArchiveDetailContent } from './ArchiveDetailContent';

export default function ArchiveDetailPage() {
  const { t } = useLanguage();

  return (
    <div className="min-h-screen pb-20 lg:pb-0">
      <Header />

      <Suspense
        fallback={
          <div className="container mx-auto px-4 py-8">
            <div className="text-center py-12">
              <p className="text-muted-foreground">{t('common.loading')}</p>
            </div>
          </div>
        }
      >
        <ArchiveDetailContent />
      </Suspense>

      <MobileBottomNav />
    </div>
  );
}
