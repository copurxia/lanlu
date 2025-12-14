'use client';

import { useEffect, useMemo, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { AuthService } from '@/lib/auth-service';
import type { AuthToken, AuthSession } from '@/types/auth';

export default function AuthSettingsPage() {
  const { t } = useLanguage();
  const { user, isAuthenticated, logout, refreshMe } = useAuth();

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // API Tokens
  const [tokens, setTokens] = useState<AuthToken[]>([]);
  const [tokensLoading, setTokensLoading] = useState(false);
  const [newTokenName, setNewTokenName] = useState('');
  const [newTokenValue, setNewTokenValue] = useState<string | null>(null);

  // 登录设备
  const [sessions, setSessions] = useState<AuthSession[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);

  // 修改密码表单
  const [oldPassword, setOldPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  const canChangePassword = useMemo(
    () => oldPassword && newPassword && newPassword.length >= 6 && newPassword === confirmPassword,
    [oldPassword, newPassword, confirmPassword]
  );

  const loadTokens = async () => {
    if (!isAuthenticated) return;
    setTokensLoading(true);
    try {
      const resp = await AuthService.listTokens();
      setTokens(resp.data.tokens || []);
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Failed to load tokens');
    } finally {
      setTokensLoading(false);
    }
  };

  const loadSessions = async () => {
    if (!isAuthenticated) return;
    setSessionsLoading(true);
    try {
      const resp = await AuthService.listSessions();
      setSessions(resp.data.sessions || []);
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Failed to load sessions');
    } finally {
      setSessionsLoading(false);
    }
  };

  useEffect(() => {
    void (async () => {
      if (isAuthenticated) {
        try {
          await refreshMe();
        } catch {
          // ignore
        }
        await Promise.all([loadTokens(), loadSessions()]);
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAuthenticated]);

  const handleChangePassword = async () => {
    if (!canChangePassword) return;
    setLoading(true);
    setError(null);
    setSuccessMsg(null);
    try {
      await AuthService.changePassword({ oldPassword, newPassword });
      setSuccessMsg(t('auth.passwordChanged'));
      setOldPassword('');
      setNewPassword('');
      setConfirmPassword('');
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Failed to change password');
    } finally {
      setLoading(false);
    }
  };

  const createToken = async () => {
    if (!newTokenName.trim()) return;
    setLoading(true);
    setError(null);
    setNewTokenValue(null);
    try {
      const resp = await AuthService.createToken(newTokenName.trim());
      setNewTokenValue(resp.data.token.token || null);
      setNewTokenName('');
      await loadTokens();
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Failed to create token');
    } finally {
      setLoading(false);
    }
  };

  const revokeToken = async (id: number) => {
    setLoading(true);
    setError(null);
    try {
      await AuthService.revokeToken(id);
      await loadTokens();
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Failed to revoke token');
    } finally {
      setLoading(false);
    }
  };

  const revokeSession = async (id: number) => {
    setLoading(true);
    setError(null);
    try {
      await AuthService.revokeToken(id); // 同样使用 revokeToken API
      await loadSessions();
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Failed to revoke session');
    } finally {
      setLoading(false);
    }
  };

  if (!isAuthenticated) {
    return (
      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle>{t('settings.authTitle')}</CardTitle>
            <CardDescription>{t('auth.loginToManageTokens')}</CardDescription>
          </CardHeader>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>{t('settings.authTitle')}</CardTitle>
          <CardDescription>{t('settings.authDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="space-y-1">
              <div className="flex items-center gap-2">
                <Badge variant="secondary">{t('auth.loggedInAs')}</Badge>
                <span className="font-medium">{user?.username || user?.id || '-'}</span>
              </div>
            </div>
            <Button variant="outline" onClick={logout}>
              {t('auth.logout')}
            </Button>
          </div>

          {error ? <p className="text-sm text-destructive">{error}</p> : null}
          {successMsg ? <p className="text-sm text-green-600">{successMsg}</p> : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('auth.changePassword')}</CardTitle>
          <CardDescription>{t('auth.changePasswordDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="oldPassword">{t('auth.oldPassword')}</Label>
            <Input
              id="oldPassword"
              type="password"
              value={oldPassword}
              onChange={(e) => setOldPassword(e.target.value)}
              placeholder={t('auth.oldPasswordPlaceholder')}
              disabled={loading}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="newPassword">{t('auth.newPassword')}</Label>
            <Input
              id="newPassword"
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              placeholder={t('auth.newPasswordPlaceholder')}
              disabled={loading}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="confirmPassword">{t('auth.confirmPassword')}</Label>
            <Input
              id="confirmPassword"
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              placeholder={t('auth.confirmPasswordPlaceholder')}
              disabled={loading}
            />
            {newPassword && confirmPassword && newPassword !== confirmPassword && (
              <p className="text-sm text-destructive">{t('auth.passwordMismatch')}</p>
            )}
            {newPassword && newPassword.length < 6 && (
              <p className="text-sm text-destructive">{t('auth.passwordTooShort')}</p>
            )}
          </div>
          <Button onClick={handleChangePassword} disabled={loading || !canChangePassword}>
            {loading ? t('common.loading') : t('auth.changePassword')}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('auth.sessionManagement')}</CardTitle>
          <CardDescription>{t('auth.sessionManagementDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">{t('auth.sessions')}</p>
            <Button variant="ghost" size="sm" onClick={loadSessions} disabled={sessionsLoading}>
              {t('common.refresh')}
            </Button>
          </div>
          {sessionsLoading ? (
            <p className="text-sm text-muted-foreground">{t('common.loading')}</p>
          ) : sessions.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t('auth.noSessions')}</p>
          ) : (
            <div className="space-y-2">
              {sessions.map((session) => (
                <div
                  key={session.id}
                  className="flex flex-col gap-2 rounded-md border p-3 sm:flex-row sm:items-center sm:justify-between"
                >
                  <div className="min-w-0 space-y-1">
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{session.name || t('auth.unnamedSession')}</span>
                      <Badge variant="outline">{session.prefix}</Badge>
                    </div>
                    {session.lastUsedAt && (
                      <p className="text-xs text-muted-foreground">
                        {t('auth.lastUsed')}: {session.lastUsedAt}
                      </p>
                    )}
                  </div>
                  <Button variant="destructive" size="sm" onClick={() => revokeSession(session.id)} disabled={loading}>
                    {t('auth.revokeSession')}
                  </Button>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {newTokenValue ? (
        <Card className="border-dashed">
          <CardHeader className="pb-2">
            <CardTitle className="text-base">{t('auth.newToken')}</CardTitle>
            <CardDescription>{t('auth.newTokenHint')}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            <Input readOnly value={newTokenValue} />
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>{t('auth.tokenManagement')}</CardTitle>
          <CardDescription>{t('auth.tokenManagementDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end">
            <div className="space-y-2">
              <Label htmlFor="newTokenName">{t('auth.tokenName')}</Label>
              <Input
                id="newTokenName"
                value={newTokenName}
                onChange={(e) => setNewTokenName(e.target.value)}
                placeholder={t('auth.tokenNamePlaceholder')}
                disabled={loading}
              />
            </div>
            <Button onClick={createToken} disabled={loading || !newTokenName.trim()}>
              {t('auth.createToken')}
            </Button>
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <p className="text-sm text-muted-foreground">{t('auth.tokens')}</p>
              <Button variant="ghost" size="sm" onClick={loadTokens} disabled={tokensLoading}>
                {t('common.refresh')}
              </Button>
            </div>
            {tokensLoading ? (
              <p className="text-sm text-muted-foreground">{t('common.loading')}</p>
            ) : tokens.length === 0 ? (
              <p className="text-sm text-muted-foreground">{t('auth.noTokens')}</p>
            ) : (
              <div className="space-y-2">
                {tokens.map((tk) => (
                  <div
                    key={tk.id}
                    className="flex flex-col gap-2 rounded-md border p-3 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-medium">{tk.name || t('auth.unnamedToken')}</span>
                        <Badge variant="outline">{tk.prefix}</Badge>
                      </div>
                    </div>
                    <div className="flex gap-2">
                      <Button variant="destructive" size="sm" onClick={() => revokeToken(tk.id)} disabled={loading}>
                        {t('common.delete')}
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
