'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { LogIn } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { AuthService } from '@/lib/auth-service';

interface LoginDialogProps {
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}

export function LoginDialog({ open: externalOpen, onOpenChange: externalOnOpenChange }: LoginDialogProps = {}) {
  const { t } = useLanguage();
  const { isAuthenticated, login } = useAuth();
  const [internalOpen, setInternalOpen] = useState(false);

  const open = externalOpen !== undefined ? externalOpen : internalOpen;
  const setOpen = externalOnOpenChange || setInternalOpen;

  const [mode, setMode] = useState<'account' | 'token'>('account');

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [tokenInput, setTokenInput] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

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
      setOpen(false);
      setPassword('');
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
      // 直接保存 token，并由 AuthContext 去 /api/auth/me 校验
      login(tokenInput.trim(), null);
      setOpen(false);
      setTokenInput('');
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

  const showButton = externalOpen === undefined;
  if (isAuthenticated) {
    return showButton ? null : <></>;
  }

  return (
    <>
      {showButton && (
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setOpen(true)}
          className="flex items-center space-x-2 px-3 py-2 rounded-md text-sm font-medium transition-colors text-muted-foreground hover:text-foreground hover:bg-muted"
        >
          <LogIn className="h-4 w-4" />
          <span className="hidden sm:inline">{t('auth.login')}</span>
        </Button>
      )}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{t('auth.loginTitle')}</DialogTitle>
            <DialogDescription>{t('auth.loginDescription')}</DialogDescription>
          </DialogHeader>

          <Tabs value={mode} onValueChange={(v) => setMode(v as any)}>
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="account">{t('auth.accountLogin')}</TabsTrigger>
              <TabsTrigger value="token">{t('auth.tokenLogin')}</TabsTrigger>
            </TabsList>

            <TabsContent value="account" className="mt-4 space-y-3">
              <div className="space-y-2">
                <Label htmlFor="username">{t('auth.username')}</Label>
                <Input
                  id="username"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  onKeyDown={handleKeyPress}
                  placeholder={t('auth.usernamePlaceholder')}
                  disabled={isLoading}
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
                />
              </div>
            </TabsContent>

            <TabsContent value="token" className="mt-4 space-y-3">
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
                />
              </div>
            </TabsContent>
          </Tabs>

          {error ? <p className="text-sm text-destructive">{error}</p> : null}

          <DialogFooter className="sm:justify-start">
            <Button
              type="button"
              onClick={mode === 'account' ? handleAccountLogin : handleTokenLogin}
              disabled={
                isLoading ||
                (mode === 'account'
                  ? !username.trim() || !password
                  : !tokenInput.trim())
              }
            >
              {isLoading ? t('auth.loggingIn') : t('auth.login')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

