'use client';

import { useState, useEffect, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Card, CardContent } from '@/components/ui/card';
import { LogIn, Library, ShieldCheck, Key } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { AuthService } from '@/lib/auth-service';
import { LanguageToggle } from '@/components/language/LanguageToggle';
import { ThemeButton } from '@/components/theme/theme-toggle';

function LoginForm() {
  const { t } = useLanguage();
  const { isAuthenticated, login } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const redirectTo = searchParams?.get('redirect') || '/';

  const [mode, setMode] = useState<'account' | 'token'>('account');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [tokenInput, setTokenInput] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  // 如果已登录，重定向到首页或指定页面
  useEffect(() => {
    if (isAuthenticated) {
      router.push(redirectTo);
    }
  }, [isAuthenticated, router, redirectTo]);

  const handleAccountLogin = async () => {
    if (!username.trim() || !password) return;
    setIsLoading(true);
    setError(null);
    try {
      const resp = await AuthService.login({
        username: username.trim(),
        password,
        tokenName: 'web',
      });
      login(resp.data.token.token, resp.data.user);
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Login failed');
    } finally {
      setIsLoading(false);
    }
  };

  const handleTokenLogin = async () => {
    if (!tokenInput.trim()) return;
    setIsLoading(true);
    setError(null);
    try {
      login(tokenInput.trim(), null);
    } catch (e: any) {
      setError(e?.message || 'Login failed');
    } finally {
      setIsLoading(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key !== 'Enter') return;
    if (mode === 'account') void handleAccountLogin();
    else void handleTokenLogin();
  };

  if (isAuthenticated) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-background">
        <div className="text-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary mx-auto"></div>
          <p className="mt-2 text-sm text-muted-foreground">{t('common.loading')}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen grid lg:grid-cols-2">
      {/* Left Side: Visual/Branding (Hidden on mobile) */}
      <div className="hidden lg:flex flex-col justify-between p-12 bg-muted relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-primary/20 via-background to-background z-0" />
        <div className="absolute inset-0 bg-[url('https://images.unsplash.com/photo-1578632738908-4521c726eebf?q=80&w=2070&auto=format&fit=crop')] bg-cover bg-center opacity-10 grayscale z-[-1]" />
        
        <div className="relative z-10 flex items-center gap-2 text-2xl font-bold tracking-tight">
          <img src="/logo.svg" alt="Logo" className="w-10 h-10" />
          <span>Lanraragi4CJ</span>
        </div>

        <div className="relative z-10 space-y-6">
          <blockquote className="space-y-2">
            <p className="text-3xl font-medium leading-tight">
              {t('home.description')}
            </p>
            <footer className="text-lg text-muted-foreground">
              Manage your comic archives with ease and style.
            </footer>
          </blockquote>
        </div>

        <div className="relative z-10 text-sm text-muted-foreground">
          &copy; 2025 Lanraragi4CJ. All rights reserved.
        </div>
      </div>

      {/* Right Side: Login Form */}
      <div className="flex items-center justify-center p-8 bg-background relative">
        <div className="absolute top-4 right-4 flex items-center gap-2">
          <LanguageToggle />
          <ThemeButton />
        </div>

        <div className="w-full max-w-[400px] space-y-6 animate-slide-in-from-bottom">
          <div className="lg:hidden flex flex-col items-center space-y-2 mb-8">
            <img src="/logo.svg" alt="Logo" className="w-16 h-16 shadow-lg" />
            <h1 className="text-2xl font-bold">Lanraragi4CJ</h1>
          </div>

          <div className="hidden lg:block space-y-2 text-center lg:text-left">
            <h2 className="text-3xl font-bold tracking-tight">{t('auth.login')}</h2>
            <p className="text-muted-foreground">
              {t('auth.loginDescription')}
            </p>
          </div>

          <Card className="border-none shadow-none lg:border lg:shadow-sm">
            <CardContent className="pt-6 px-0 lg:px-6">
              <Tabs value={mode} onValueChange={(v) => setMode(v as any)} className="w-full">
                <TabsList className="grid w-full grid-cols-2 mb-8">
                  <TabsTrigger value="account" className="flex items-center gap-2">
                    <ShieldCheck className="h-4 w-4" />
                    {t('auth.accountLogin')}
                  </TabsTrigger>
                  <TabsTrigger value="token" className="flex items-center gap-2">
                    <Key className="h-4 w-4" />
                    {t('auth.tokenLogin')}
                  </TabsTrigger>
                </TabsList>

                <TabsContent value="account" className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="username">{t('auth.username')}</Label>
                    <Input
                      id="username"
                      value={username}
                      onChange={(e) => setUsername(e.target.value)}
                      onKeyDown={handleKeyPress}
                      placeholder={t('auth.usernamePlaceholder')}
                      disabled={isLoading}
                      autoComplete="username"
                      className="h-11"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="password">{t('auth.password')}</Label>
                    <Input
                      id="password"
                      type="password"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      onKeyDown={handleKeyPress}
                      placeholder={t('auth.passwordPlaceholder')}
                      disabled={isLoading}
                      autoComplete="current-password"
                      className="h-11"
                    />
                  </div>
                </TabsContent>

                <TabsContent value="token" className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="token">{t('auth.token')}</Label>
                    <Input
                      id="token"
                      type="password"
                      placeholder={t('auth.tokenPlaceholder')}
                      value={tokenInput}
                      onChange={(e) => setTokenInput(e.target.value)}
                      onKeyDown={handleKeyPress}
                      disabled={isLoading}
                      autoComplete="off"
                      className="h-11"
                    />
                  </div>
                </TabsContent>
              </Tabs>

              {error && (
                <div className="mt-4 p-3 text-sm text-destructive bg-destructive/10 rounded-md border border-destructive/20 animate-shake">
                  {error}
                </div>
              )}

              <Button
                type="button"
                className="w-full mt-6 h-11 text-base font-medium transition-all active:scale-[0.98]"
                onClick={mode === 'account' ? handleAccountLogin : handleTokenLogin}
                disabled={
                  isLoading ||
                  (mode === 'account'
                    ? !username.trim() || !password
                    : !tokenInput.trim())
                }
              >
                {isLoading ? (
                  <div className="flex items-center gap-2">
                    <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
                    {t('auth.loggingIn')}
                  </div>
                ) : (
                  <div className="flex items-center gap-2">
                    <LogIn className="h-4 w-4" />
                    {t('auth.login')}
                  </div>
                )}
              </Button>
            </CardContent>
          </Card>

          <div className="text-center text-sm text-muted-foreground lg:hidden">
            &copy; 2025 Lanraragi4CJ. All rights reserved.
          </div>
        </div>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={
      <div className="flex items-center justify-center min-h-screen bg-background">
        <div className="text-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary mx-auto"></div>
          <p className="mt-2 text-sm text-muted-foreground">Loading...</p>
        </div>
      </div>
    }>
      <LoginForm />
    </Suspense>
  );
}