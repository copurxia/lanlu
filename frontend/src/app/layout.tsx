import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { ThemeProvider } from '@/components/theme/theme-provider';
import { LanguageProvider } from '@/contexts/LanguageContext';
import { AuthProvider } from '@/contexts/AuthContext';
import { StaticGenerationProvider } from '@/contexts/StaticGenerationContext';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'Lanraragi4CJ',
  description: '漫画归档管理系统',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // 检测是否在静态生成环境中
  const isStaticGeneration = process.env.NEXT_PUBLIC_STATIC_EXPORT === 'true' || typeof window === 'undefined';

  return (
    <html suppressHydrationWarning>
      <body className={inter.className}>
        <StaticGenerationProvider>
          <LanguageProvider>
            <AuthProvider>
              <ThemeProvider
                attribute="class"
                defaultTheme="system"
                enableSystem
                disableTransitionOnChange
              >
                {children}
              </ThemeProvider>
            </AuthProvider>
          </LanguageProvider>
        </StaticGenerationProvider>
      </body>
    </html>
  );
}
