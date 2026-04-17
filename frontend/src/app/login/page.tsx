'use client';

import { useState, useEffect, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Card, CardContent } from '@/components/ui/card';
import { LogIn, ShieldCheck, Key } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { useServerInfo } from '@/contexts/ServerInfoContext';
import { AuthService } from '@/lib/services/auth-service';
import { TotpAuthService } from '@/lib/services/totp-auth-service';
import { WebauthnAuthService } from '@/lib/services/webauthn-auth-service';
import { LanguageButton } from '@/components/language/LanguageButton';
import { ThemeButton } from '@/components/theme/theme-toggle';
import { Logo } from '@/components/brand/Logo';
import type { AuthLoginPendingTotp } from '@/types/auth';

function LoginForm() {
  const { t } = useLanguage();
  const { serverName } = useServerInfo();
  const { isAuthenticated, login } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const redirectTo = searchParams?.get('redirect') || '/';

  const LOGIN_USERNAME_STORAGE_KEY = 'lanlu.login.username';

  const [mode, setMode] = useState<'account' | 'passkey'>('account');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [totpChallengeId, setTotpChallengeId] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [recoveryCode, setRecoveryCode] = useState('');
  const [totpMethod, setTotpMethod] = useState<'totp' | 'recovery_code'>('totp');
  const [passkeySupported, setPasskeySupported] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  // 如果已登录，重定向到首页或指定页面
  useEffect(() => {
    if (isAuthenticated) {
      router.push(redirectTo);
    }
  }, [isAuthenticated, router, redirectTo]);

  // If login fails and the user refreshes, restore the last attempted username.
  useEffect(() => {
    setPasskeySupported(WebauthnAuthService.isSupported());
  }, []);

  useEffect(() => {
    try {
      const saved = window.localStorage.getItem(LOGIN_USERNAME_STORAGE_KEY);
      if (saved && !username) setUsername(saved);
    } catch {
      // Ignore storage access errors (private mode, disabled storage, etc).
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isPendingTotp = (data: unknown): data is AuthLoginPendingTotp => {
    if (!data || typeof data !== 'object') return false;
    return (data as AuthLoginPendingTotp).requiresTotp === true;
  };

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
      if (isPendingTotp(resp.data)) {
        setTotpChallengeId(resp.data.challengeId);
        setTotpCode('');
        setRecoveryCode('');
        setTotpMethod('totp');
        setPassword('');
        return;
      }
      try {
        window.localStorage.removeItem(LOGIN_USERNAME_STORAGE_KEY);
      } catch {
        // Ignore.
      }
      login(resp.data.token.token, resp.data.user);
    } catch (e: any) {
      try {
        window.localStorage.setItem(LOGIN_USERNAME_STORAGE_KEY, username.trim());
      } catch {
        // Ignore.
      }
      setError(e?.response?.data?.message || e?.message || 'Login failed');
    } finally {
      setIsLoading(false);
    }
  };

  const handleTotpVerify = async () => {
    if (!totpChallengeId.trim()) return;
    if (totpMethod === 'totp' && !totpCode.trim()) return;
    if (totpMethod === 'recovery_code' && !recoveryCode.trim()) return;

    setIsLoading(true);
    setError(null);
    try {
      const resp = await TotpAuthService.verifyLogin({
        challengeId: totpChallengeId.trim(),
        code: totpMethod === 'totp' ? totpCode.trim() : '',
        recoveryCode: totpMethod === 'recovery_code' ? recoveryCode.trim() : '',
      });
      try {
        window.localStorage.removeItem(LOGIN_USERNAME_STORAGE_KEY);
      } catch {
        // Ignore.
      }
      setTotpChallengeId('');
      setTotpCode('');
      setRecoveryCode('');
      login(resp.data.token.token, resp.data.user);
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || t('auth.totpVerifyFailed'));
    } finally {
      setIsLoading(false);
    }
  };

  const handlePasskeyLogin = async () => {
    setIsLoading(true);
    setError(null);
    try {
      const resp = await WebauthnAuthService.loginWithPasskey();
      try {
        window.localStorage.removeItem(LOGIN_USERNAME_STORAGE_KEY);
      } catch {
        // Ignore.
      }
      login(resp.data.token.token, resp.data.user);
    } catch (e: any) {
      try {
        if (username.trim()) {
          window.localStorage.setItem(LOGIN_USERNAME_STORAGE_KEY, username.trim());
        }
      } catch {
        // Ignore.
      }
      setError(e?.response?.data?.message || e?.message || t('auth.passkeyLoginFailed'));
    } finally {
      setIsLoading(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key !== 'Enter') return;
    if (mode === 'account') {
      if (totpChallengeId) void handleTotpVerify();
      else void handleAccountLogin();
    }
    else void handlePasskeyLogin();
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
        <div className="absolute inset-0 bg-linear-to-br from-primary/20 via-background to-background z-0" />
        <div className="absolute inset-0 bg-[url('https://images.unsplash.com/photo-1578632738908-4521c726eebf?q=80&w=2070&auto=format&fit=crop')] bg-cover bg-center opacity-10 grayscale z-[-1]" />
        
        <div className="relative z-10 flex items-center gap-2 text-2xl font-bold tracking-tight">
          <Logo width={40} height={40} />
          <span>{serverName}</span>
        </div>

        <div className="relative z-10 space-y-6">
          <blockquote className="space-y-2">
            <p className="text-3xl font-medium leading-tight">
              {t('home.description')}
            </p>
            <footer className="text-lg text-muted-foreground">
              {t('login.description')}
            </footer>
          </blockquote>
        </div>

        <div className="relative z-10 text-sm text-muted-foreground">
          © 2025 {serverName}. All rights reserved.
        </div>
      </div>

      {/* Right Side: Login Form */}
      <div className="flex items-center justify-center p-8 bg-background relative">
        {/* Align with left panel padding on desktop */}
        <div className="absolute top-4 right-4 lg:top-12 lg:right-12 flex items-center gap-2">
          <LanguageButton />
          <ThemeButton />
        </div>

        <div className="w-full max-w-[400px] space-y-6 animate-slide-in-from-bottom">
          <div className="lg:hidden flex flex-col items-center space-y-2 mb-8">
            <Logo width={64} height={64} className="rounded-lg shadow-lg" />
            <h1 className="text-2xl font-bold">{serverName}</h1>
          </div>

          {/* Match CardContent padding on desktop so the header aligns with form fields */}
          <div className="hidden lg:block space-y-2 text-center lg:text-left lg:px-6">
            <h2 className="text-3xl font-bold tracking-tight">{t('auth.login')}</h2>
            <p className="text-muted-foreground">
              {t('auth.loginDescription')}
            </p>
          </div>

          {/* Mobile: avoid the "card" backdrop (looks like an extra wrapper in dark mode). */}
          <Card className="border-none shadow-none bg-transparent lg:bg-card lg:border lg:shadow-xs">
            <CardContent className="pt-6 px-0 lg:px-6">
              <Tabs value={mode} onValueChange={(v) => setMode(v as any)} className="w-full">
                <TabsList className={`grid w-full mb-8 ${passkeySupported ? 'grid-cols-2' : 'grid-cols-1'}`}>
                  <TabsTrigger value="account" className="flex items-center gap-2">
                    <ShieldCheck className="h-4 w-4" />
                    {t('auth.accountLogin')}
                  </TabsTrigger>
                  {passkeySupported ? (
                    <TabsTrigger value="passkey" className="flex items-center gap-2">
                      <Key className="h-4 w-4" />
                      {t('auth.passkeyLogin')}
                    </TabsTrigger>
                  ) : null}
                </TabsList>

                <TabsContent value="account" className="space-y-4">
                  {totpChallengeId ? (
                    <>
                      <p className="text-sm text-muted-foreground">{t('auth.totpRequiredDescription')}</p>
                      <Tabs value={totpMethod} onValueChange={(value) => setTotpMethod(value as 'totp' | 'recovery_code')}>
                        <TabsList className="grid w-full grid-cols-2">
                          <TabsTrigger value="totp">{t('auth.totpCode')}</TabsTrigger>
                          <TabsTrigger value="recovery_code">{t('auth.recoveryCode')}</TabsTrigger>
                        </TabsList>
                        <TabsContent value="totp" className="space-y-2">
                          <Label htmlFor="totpCode">{t('auth.totpCode')}</Label>
                          <Input
                            id="totpCode"
                            value={totpCode}
                            onChange={(e) => setTotpCode(e.target.value)}
                            onKeyDown={handleKeyPress}
                            placeholder={t('auth.totpCodePlaceholder')}
                            disabled={isLoading}
                            inputMode="numeric"
                            className="h-11"
                          />
                        </TabsContent>
                        <TabsContent value="recovery_code" className="space-y-2">
                          <Label htmlFor="recoveryCode">{t('auth.recoveryCode')}</Label>
                          <Input
                            id="recoveryCode"
                            value={recoveryCode}
                            onChange={(e) => setRecoveryCode(e.target.value)}
                            onKeyDown={handleKeyPress}
                            placeholder={t('auth.recoveryCodePlaceholder')}
                            disabled={isLoading}
                            className="h-11"
                          />
                        </TabsContent>
                      </Tabs>
                      <Button type="button" variant="ghost" className="px-0" disabled={isLoading} onClick={() => setTotpChallengeId('')}>
                        {t('common.back')}
                      </Button>
                    </>
                  ) : (
                    <>
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
                    </>
                  )}
                </TabsContent>

                <TabsContent value="passkey" className="space-y-4">
                  <p className="text-sm text-muted-foreground">{t('auth.passkeyLoginDescription')}</p>
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
                onClick={mode === 'account' ? (totpChallengeId ? handleTotpVerify : handleAccountLogin) : handlePasskeyLogin}
                disabled={
                  isLoading ||
                  (mode === 'account'
                    ? (totpChallengeId
                      ? (totpMethod === 'totp' ? !totpCode.trim() : !recoveryCode.trim())
                      : (!username.trim() || !password))
                    : false)
                }
              >
                {isLoading ? (
                  <div className="flex items-center gap-2">
                    <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
                    {totpChallengeId ? t('auth.verifyingTotp') : t('auth.loggingIn')}
                  </div>
                ) : (
                  <div className="flex items-center gap-2">
                    <LogIn className="h-4 w-4" />
                    {totpChallengeId ? t('auth.verifyTotp') : t('auth.login')}
                  </div>
                )}
              </Button>
            </CardContent>
          </Card>

          <div className="text-center text-sm text-muted-foreground lg:hidden">
            © 2025 {serverName}. All rights reserved.
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
