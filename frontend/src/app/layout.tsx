import type { Metadata, Viewport } from 'next';
import './globals.css';
import { ThemeProvider } from '@/components/theme/theme-provider';
import { LanguageProvider } from '@/contexts/LanguageContext';
import { AuthProvider } from '@/contexts/AuthContext';
import { ServerInfoProvider } from '@/contexts/ServerInfoContext';
import { ConfirmProvider } from '@/contexts/ConfirmProvider';
import { Toaster } from 'sonner';
import { RouteHistoryTracker } from '@/components/navigation/RouteHistoryTracker';

export const metadata: Metadata = {
  title: '兰鹿',
  description: '漫画归档管理系统',
  manifest: '/manifest.webmanifest',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'default',
    title: '兰鹿',
  },
  icons: {
    icon: [
      { url: '/icon.svg', type: 'image/svg+xml' },
      { url: '/icon.png', type: 'image/png', sizes: '128x128' },
    ],
    apple: '/icon.png',
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  colorScheme: 'light dark',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html suppressHydrationWarning>
      <body className="font-sans">
        <LanguageProvider>
          <AuthProvider>
            <ServerInfoProvider>
              <ConfirmProvider>
                <ThemeProvider defaultTheme="system">
                  <RouteHistoryTracker />
                  {children}
                  <Toaster position="top-center" richColors />
                </ThemeProvider>
              </ConfirmProvider>
            </ServerInfoProvider>
          </AuthProvider>
        </LanguageProvider>
      </body>
    </html>
  );
}
