import type React from 'react';
import { Header } from '@/components/layout/Header';
import { ServerInfoProvider } from '@/contexts/ServerInfoContext';

export default function HeaderLayout({ children }: { children: React.ReactNode }) {
  return (
    <ServerInfoProvider>
      <Header />
      {children}
    </ServerInfoProvider>
  );
}
