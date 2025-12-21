import type { Metadata, Viewport } from 'next';
// import { Inter } from 'next/font/google';
import './globals.css';
import { ThemeProvider } from '@/components/theme/theme-provider';
import { LanguageProvider } from '@/contexts/LanguageContext';
import { AuthProvider } from '@/contexts/AuthContext';
import { ServerInfoProvider } from '@/contexts/ServerInfoContext';
import { StaticGenerationProvider } from '@/contexts/StaticGenerationContext';
import { ConfirmProvider } from '@/contexts/ConfirmProvider';
import { Toaster } from 'sonner';

// 使用系统字体而不是 Google Fonts 以避免构建时的网络依赖
// const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: '兰鹿',
  description: '漫画归档管理系统',
  icons: {
    icon: '/logo.svg',
  },
};

export const viewport: Viewport = {
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
        <StaticGenerationProvider>
          <LanguageProvider>
            <AuthProvider>
              <ServerInfoProvider>
                <ConfirmProvider>
                  <ThemeProvider
                    defaultTheme="system"
                  >
                    {children}
                    <Toaster position="top-center" richColors />
                  </ThemeProvider>
                </ConfirmProvider>
              </ServerInfoProvider>
            </AuthProvider>
          </LanguageProvider>
        </StaticGenerationProvider>
      </body>
    </html>
  );
}
