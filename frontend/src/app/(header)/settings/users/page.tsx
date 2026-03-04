'use client';

import { useEffect, useMemo, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Switch } from '@/components/ui/switch';
import { Users } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { apiClient } from '@/lib/api';
import type { ApiEnvelope, AdminUser } from '@/types/auth';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';

interface CreateUserForm {
  username: string;
  isAdmin: boolean;
}

interface ResetPasswordForm {
  newPassword: string;
  confirmPassword: string;
}

export default function UsersSettingsPage() {
  const { t } = useLanguage();
  const { user, isAuthenticated } = useAuth();
  const { success, error: showError } = useToast();
  const { confirm } = useConfirmContext();

  const [loading, setLoading] = useState(false);

  // Users list
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [usersLoading, setUsersLoading] = useState(false);

  // Create user form
  const [createForm, setCreateForm] = useState<CreateUserForm>({
    username: '',
    isAdmin: false,
  });

  // Reset password form
  const [resetPasswordUser, setResetPasswordUser] = useState<AdminUser | null>(null);
  const [resetPasswordForm, setResetPasswordForm] = useState<ResetPasswordForm>({
    newPassword: '',
    confirmPassword: '',
  });

  // Check if current user is admin
  const isAdmin = useMemo(() => {
    return isAuthenticated && (user?.isAdmin === true);
  }, [isAuthenticated, user?.isAdmin]);

  const loadUsers = async () => {
    if (!isAuthenticated) return;
    setUsersLoading(true);
    try {
      const resp = await apiClient.get<ApiEnvelope<{ users: AdminUser[] }>>('/api/auth/admin/users');
      setUsers(resp.data.data.users || []);
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || 'Failed to load users');
    } finally {
      setUsersLoading(false);
    }
  };

  useEffect(() => {
    if (isAuthenticated) {
      void loadUsers();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAuthenticated]);

  const handleCreateUser = async () => {
    if (!createForm.username.trim()) {
      showError(t('auth.usernameRequired'));
      return;
    }

    setLoading(true);

    try {
      const resp = await apiClient.post<ApiEnvelope<{ user: AdminUser; generatedPassword: string }>>('/api/auth/admin/users', {
        username: createForm.username.trim(),
        isAdmin: createForm.isAdmin,
      });

      const createdUser = resp.data.data.user;
      const generatedPassword = resp.data.data.generatedPassword;
      success(`${t('auth.userCreatedSuccess')} "${createdUser.username}", ${t('auth.generatedPassword')}: ${generatedPassword}`);
      setCreateForm({
        username: '',
        isAdmin: false,
      });
      await loadUsers();
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || 'Failed to create user');
    } finally {
      setLoading(false);
    }
  };

  const handleToggleAdmin = async (userId: number, isAdmin: boolean) => {
    setLoading(true);
    try {
      await apiClient.put(`/api/auth/admin/users/${userId}/role`, {
        isAdmin,
      });
      success(t('auth.userRoleUpdated'));
      await loadUsers();
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || 'Failed to update user role');
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteUser = async (userId: number) => {
    const confirmed = await confirm({
      title: t('auth.confirmDeleteUser'),
      description: t('auth.confirmDeleteUserMessage'),
      confirmText: t('common.delete'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    });

    if (!confirmed) return;

    setLoading(true);
    try {
      await apiClient.delete(`/api/auth/admin/users/${userId}`);
      success(t('auth.userDeletedSuccess'));
      await loadUsers();
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || 'Failed to delete user');
    } finally {
      setLoading(false);
    }
  };

  const handleResetPassword = async () => {
    if (!resetPasswordUser) return;

    if (resetPasswordForm.newPassword !== resetPasswordForm.confirmPassword) {
      showError(t('auth.passwordMismatch'));
      return;
    }

    if (resetPasswordForm.newPassword.length < 6) {
      showError(t('auth.passwordTooShort'));
      return;
    }

    setLoading(true);
    try {
      await apiClient.post(`/api/auth/admin/users/${resetPasswordUser.id}/reset-password`, {
        newPassword: resetPasswordForm.newPassword,
      });
      success(t('auth.passwordResetSuccess'));
      setResetPasswordUser(null);
      setResetPasswordForm({ newPassword: '', confirmPassword: '' });
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || 'Failed to reset password');
    } finally {
      setLoading(false);
    }
  };

  if (!isAuthenticated) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <Users className="w-5 h-5" />
              {t('settings.users')}
            </h2>
            <p className="text-sm text-muted-foreground">{t('auth.loginToManageTokens')}</p>
          </div>
        </div>
        <Card>
          <CardContent className="pt-6 space-y-4">
            {/* Empty content */}
          </CardContent>
        </Card>
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <Users className="w-5 h-5" />
              {t('settings.users')}
            </h2>
            <p className="text-sm text-muted-foreground">{t('common.accessDenied')}</p>
          </div>
        </div>
        <Card>
          <CardContent className="pt-6 space-y-4">
            {/* Empty content */}
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            <Users className="w-5 h-5" />
            {t('settings.users')}
          </h2>
          <p className="text-sm text-muted-foreground">{t('settings.usersDescription')}</p>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>{t('auth.createUser')}</CardTitle>
          <CardDescription>{t('auth.createUserDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="username">{t('auth.username')}</Label>
              <Input
                id="username"
                value={createForm.username}
                onChange={(e) => setCreateForm({ ...createForm, username: e.target.value })}
                placeholder={t('auth.usernamePlaceholder')}
                disabled={loading}
                maxLength={64}
              />
            </div>
            <div className="flex items-center space-x-2 pt-8">
              <Switch
                id="isAdmin"
                checked={createForm.isAdmin}
                onCheckedChange={(checked) => setCreateForm({ ...createForm, isAdmin: checked })}
                disabled={loading}
              />
              <Label htmlFor="isAdmin">{t('auth.makeAdmin')}</Label>
            </div>
          </div>

          <Button onClick={handleCreateUser} disabled={loading || !createForm.username.trim()}>
            {loading ? t('common.creating') : t('auth.createUser')}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('auth.manageUsers')}</CardTitle>
          <CardDescription>{t('auth.manageUsersDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">{t('auth.users')}</p>
            <Button variant="ghost" size="sm" onClick={loadUsers} disabled={usersLoading}>
              {t('common.refresh')}
            </Button>
          </div>
          {usersLoading ? (
            <p className="text-sm text-muted-foreground">{t('common.loading')}</p>
          ) : users.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t('auth.noUsers')}</p>
          ) : (
            <div className="space-y-2">
              {users.map((u) => (
                <div
                  key={u.id}
                  className="flex flex-col gap-2 rounded-md border p-3 sm:flex-row sm:items-center sm:justify-between"
                >
                  <div className="min-w-0 space-y-1">
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{u.username}</span>
                      <Badge variant={u.isAdmin ? "default" : "secondary"}>
                        {u.isAdmin ? t('auth.admin') : t('auth.user')}
                      </Badge>
                    </div>
                    {u.createdAt && (
                      <p className="text-xs text-muted-foreground">
                        {t('auth.createdAt')}: {u.createdAt}
                      </p>
                    )}
                  </div>
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setResetPasswordUser(u)}
                      disabled={loading || u.id === user?.id}
                    >
                      {t('auth.resetPassword')}
                    </Button>
                    <div className="flex items-center gap-2">
                      <Label htmlFor={`admin-${u.id}`} className="text-xs">
                        {t('auth.admin')}
                      </Label>
                      <Switch
                        id={`admin-${u.id}`}
                        checked={u.isAdmin}
                        onCheckedChange={(checked) => handleToggleAdmin(u.id, checked)}
                        disabled={loading || u.id === user?.id}
                      />
                    </div>
                    <Button
                      variant="destructive"
                      size="sm"
                      onClick={() => handleDeleteUser(u.id)}
                      disabled={loading || u.id === user?.id}
                    >
                      {t('common.delete')}
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {resetPasswordUser && (
        <Card className="border-dashed">
          <CardHeader className="pb-2">
            <CardTitle className="text-base">{t('auth.resetPassword')}</CardTitle>
            <CardDescription>{t('auth.resetPasswordFor', { username: resetPasswordUser.username })}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="newPassword">{t('auth.newPassword')}</Label>
                <Input
                  id="newPassword"
                  type="password"
                  value={resetPasswordForm.newPassword}
                  onChange={(e) => setResetPasswordForm({ ...resetPasswordForm, newPassword: e.target.value })}
                  placeholder={t('auth.newPasswordPlaceholder')}
                  disabled={loading}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="confirmNewPassword">{t('auth.confirmPassword')}</Label>
                <Input
                  id="confirmNewPassword"
                  type="password"
                  value={resetPasswordForm.confirmPassword}
                  onChange={(e) => setResetPasswordForm({ ...resetPasswordForm, confirmPassword: e.target.value })}
                  placeholder={t('auth.confirmPasswordPlaceholder')}
                  disabled={loading}
                />
              </div>
            </div>
            {(resetPasswordForm.newPassword && resetPasswordForm.confirmPassword && resetPasswordForm.newPassword !== resetPasswordForm.confirmPassword) && (
              <p className="text-sm text-destructive">{t('auth.passwordMismatch')}</p>
            )}
            <div className="flex gap-2">
              <Button onClick={handleResetPassword} disabled={loading}>
                {loading ? t('common.saving') : t('auth.resetPassword')}
              </Button>
              <Button variant="outline" onClick={() => {
                setResetPasswordUser(null);
                setResetPasswordForm({ newPassword: '', confirmPassword: '' });
              }}>
                {t('common.cancel')}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
