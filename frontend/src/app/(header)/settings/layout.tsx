'use client';

import { AppSidebarNav } from '@/components/layout/AppSidebarNav';
import { PageSidebarLayout } from '@/components/layout/PageSidebarLayout';

export default function SettingsLayout({ children }: { children: React.ReactNode }) {
  return (
    <PageSidebarLayout sidebar={<AppSidebarNav mode="settings" />} contentClassName="pb-6">
      <div className="settings-page-content mx-auto w-full max-w-6xl space-y-6">
        {children}
      </div>
    </PageSidebarLayout>
  );
}
