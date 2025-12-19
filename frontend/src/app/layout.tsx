import type { Metadata } from 'next';
// import { Inter } from 'next/font/google';
import './globals.css';
import { ThemeProvider } from '@/components/theme/theme-provider';
import { LanguageProvider } from '@/contexts/LanguageContext';
import { AuthProvider } from '@/contexts/AuthContext';
import { StaticGenerationProvider } from '@/contexts/StaticGenerationContext';
import { ConfirmProvider } from '@/contexts/ConfirmProvider';
import { Toaster } from 'sonner';

// 使用系统字体而不是 Google Fonts 以避免构建时的网络依赖
// const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'Lanraragi4CJ',
  description: '漫画归档管理系统',
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
              <ConfirmProvider>
                <ThemeProvider
                  defaultTheme="system"
                >
                  {children}
                  <Toaster position="top-center" richColors />
                </ThemeProvider>
              </ConfirmProvider>
            </AuthProvider>
          </LanguageProvider>
        </StaticGenerationProvider>
      </body>
    </html>
  );
}
