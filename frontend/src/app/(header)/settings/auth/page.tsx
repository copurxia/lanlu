'use client';

import { useEffect, useEffectEvent, useMemo, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Slider } from '@/components/ui/slider';
import { KeyRound } from 'lucide-react';
import { QrCode, ShieldCheck } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { AuthService } from '@/lib/services/auth-service';
import { TotpAuthService } from '@/lib/services/totp-auth-service';
import { WebauthnAuthService } from '@/lib/services/webauthn-auth-service';
import type { AuthToken, AuthSession, PasskeyCredential, TotpEnrollmentPayload, TotpStatus } from '@/types/auth';
import { AuthGuard } from '@/components/settings/AuthGuard';
import { useToast } from '@/hooks/use-toast';
import { useStepUpDialog } from '@/hooks/use-step-up-dialog';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { User } from 'lucide-react';

export default function AuthSettingsPage() {
  const { t } = useLanguage();
  const { user, isAuthenticated, logout, refreshMe } = useAuth();
  const { success: toastSuccess, error: toastError } = useToast();
  const { requestStepUp, stepUpDialog } = useStepUpDialog();
  const { confirm } = useConfirmContext();

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

  // Passkeys
  const [passkeys, setPasskeys] = useState<PasskeyCredential[]>([]);
  const [passkeysLoading, setPasskeysLoading] = useState(false);
  const [passkeySupported, setPasskeySupported] = useState(false);
  const [registeringPasskey, setRegisteringPasskey] = useState(false);
  const [newPasskeyName, setNewPasskeyName] = useState('');
  const [totpStatus, setTotpStatus] = useState<TotpStatus | null>(null);
  const [totpLoading, setTotpLoading] = useState(false);
  const [enrollingTotp, setEnrollingTotp] = useState(false);
  const [confirmingTotp, setConfirmingTotp] = useState(false);
  const [regeneratingRecoveryCodes, setRegeneratingRecoveryCodes] = useState(false);
  const [disablingTotp, setDisablingTotp] = useState(false);
  const [totpEnrollment, setTotpEnrollment] = useState<TotpEnrollmentPayload | null>(null);
  const [totpName, setTotpName] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);

  // 修改凭据表单
  const [newUsername, setNewUsername] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [avatarLoading, setAvatarLoading] = useState(false);
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [avatarUrl, setAvatarUrl] = useState<string | null>(null);
  const [avatarZoom, setAvatarZoom] = useState(1);
  const [avatarPan, setAvatarPan] = useState({ x: 0, y: 0 });
  const [avatarNaturalSize, setAvatarNaturalSize] = useState<{ w: number; h: number } | null>(null);
  const [dragState, setDragState] = useState<{ dragging: boolean; startX: number; startY: number; startPanX: number; startPanY: number } | null>(null);
  const [avatarDialogOpen, setAvatarDialogOpen] = useState(false);
  const [fileInputEl, setFileInputEl] = useState<HTMLInputElement | null>(null);

  const canChangeUsername = useMemo(
    () => newUsername && newUsername.length >= 3 && newUsername !== user?.username,
    [newUsername, user?.username]
  );

  const canChangePassword = useMemo(
    () => newPassword && newPassword.length >= 6 && newPassword === confirmPassword,
    [newPassword, confirmPassword]
  );

  const canSave = useMemo(
    () => canChangeUsername || canChangePassword,
    [canChangeUsername, canChangePassword]
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

  const loadPasskeys = async () => {
    if (!isAuthenticated || !passkeySupported) return;
    setPasskeysLoading(true);
    try {
      const resp = await WebauthnAuthService.listCredentials();
      setPasskeys(resp.data.credentials || []);
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || t('auth.passkeyLoadFailed'));
    } finally {
      setPasskeysLoading(false);
    }
  };

  const loadTotpStatus = async () => {
    if (!isAuthenticated) return;
    setTotpLoading(true);
    try {
      const resp = await TotpAuthService.getStatus();
      setTotpStatus(resp.data);
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || t('auth.totpStatusLoadFailed'));
    } finally {
      setTotpLoading(false);
    }
  };

  useEffect(() => {
    setPasskeySupported(WebauthnAuthService.isSupported());
  }, []);

  const syncAuthSecurityData = useEffectEvent(async () => {
    if (!isAuthenticated) return;

    try {
      await refreshMe();
    } catch {
      // ignore
    }

    await Promise.all([loadTokens(), loadSessions(), loadPasskeys(), loadTotpStatus()]);
  });

  useEffect(() => {
    void syncAuthSecurityData();
  }, [isAuthenticated, passkeySupported]);

  const handleSave = async () => {
    if (!canSave) return;
    setLoading(true);
    setError(null);
    setSuccessMsg(null);

    try {
      if (canChangeUsername) {
        await AuthService.changeUsername(newUsername);
        setNewUsername('');
      }

      if (canChangePassword) {
        if (!(await requestStepUp())) {
          return;
        }
        await AuthService.changePassword({ newPassword });
        setNewPassword('');
        setConfirmPassword('');
        await logout();
        return;
      }

      await refreshMe();
      setSuccessMsg(t('auth.credentialsUpdated'));
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Failed to update credentials');
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
    const confirmed = await confirm({
      title: t('auth.confirmRevokeTokenTitle'),
      description: t('auth.confirmRevokeTokenDescription'),
      confirmText: t('auth.revokeToken'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    });
    if (!confirmed) return;

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
    const targetSession = sessions.find((session) => session.id === id) || null;
    const confirmed = await confirm({
      title: targetSession?.current ? t('auth.confirmLogoutCurrentSessionTitle') : t('auth.confirmRevokeSessionTitle'),
      description: targetSession?.current ? t('auth.confirmLogoutCurrentSessionDescription') : t('auth.confirmRevokeSessionDescription'),
      confirmText: targetSession?.current ? t('auth.logout') : t('auth.revokeSession'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    });
    if (!confirmed) return;

    setLoading(true);
    setError(null);
    try {
      await AuthService.revokeSession(id);
      if (targetSession?.current) {
        await logout();
        return;
      }
      await loadSessions();
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Failed to revoke session');
    } finally {
      setLoading(false);
    }
  };

  const revokeOtherSessions = async () => {
    const confirmed = await confirm({
      title: t('auth.confirmRevokeOtherSessionsTitle'),
      description: t('auth.confirmRevokeOtherSessionsDescription'),
      confirmText: t('auth.revokeOtherSessions'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    });
    if (!confirmed) return;

    setLoading(true);
    setError(null);
    try {
      await AuthService.revokeOtherSessions();
      await loadSessions();
      setSuccessMsg(t('auth.otherSessionsRevoked'));
      toastSuccess(t('auth.otherSessionsRevoked'));
    } catch (e: any) {
      const msg = e?.response?.data?.message || e?.message || t('auth.revokeOtherSessionsFailed');
      setError(msg);
      toastError(msg);
    } finally {
      setLoading(false);
    }
  };

  const registerPasskey = async () => {
    if (!passkeySupported) return;
    setRegisteringPasskey(true);
    setError(null);
    setSuccessMsg(null);
    try {
      if (!(await requestStepUp())) {
        return;
      }
      await WebauthnAuthService.registerPasskey(newPasskeyName.trim());
      setNewPasskeyName('');
      await loadPasskeys();
      setSuccessMsg(t('auth.passkeyRegistered'));
      toastSuccess(t('auth.passkeyRegistered'));
    } catch (e: any) {
      const msg = e?.response?.data?.message || e?.message || t('auth.passkeyRegisterFailed');
      setError(msg);
      toastError(msg);
    } finally {
      setRegisteringPasskey(false);
    }
  };

  const revokePasskey = async (id: number) => {
    const confirmed = await confirm({
      title: t('auth.confirmDeletePasskeyTitle'),
      description: t('auth.confirmDeletePasskeyDescription'),
      confirmText: t('common.delete'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    });
    if (!confirmed) return;

    setLoading(true);
    setError(null);
    try {
      if (!(await requestStepUp())) {
        return;
      }
      await WebauthnAuthService.revokeCredential(id);
      await loadPasskeys();
      setSuccessMsg(t('auth.passkeyDeleted'));
      toastSuccess(t('auth.passkeyDeleted'));
    } catch (e: any) {
      const msg = e?.response?.data?.message || e?.message || t('auth.passkeyDeleteFailed');
      setError(msg);
      toastError(msg);
    } finally {
      setLoading(false);
    }
  };

  const startTotpEnrollment = async () => {
    setEnrollingTotp(true);
    setError(null);
    try {
      if (!(await requestStepUp())) {
        return;
      }
      const resp = await TotpAuthService.startEnrollment(totpName.trim());
      setTotpEnrollment(resp.data);
      setRecoveryCodes([]);
      setSuccessMsg(null);
    } catch (e: any) {
      const msg = e?.response?.data?.message || e?.message || t('auth.totpEnrollStartFailed');
      setError(msg);
      toastError(msg);
    } finally {
      setEnrollingTotp(false);
    }
  };

  const confirmTotpEnrollment = async () => {
    if (!totpEnrollment || !totpCode.trim()) return;
    setConfirmingTotp(true);
    setError(null);
    try {
      const resp = await TotpAuthService.confirmEnrollment({
        challengeId: totpEnrollment.challengeId,
        code: totpCode.trim(),
        name: totpName.trim(),
      });
      setRecoveryCodes(resp.data.recoveryCodes || []);
      setTotpEnrollment(null);
      setTotpCode('');
      await loadTotpStatus();
      setSuccessMsg(t('auth.totpEnabled'));
      toastSuccess(t('auth.totpEnabled'));
    } catch (e: any) {
      const msg = e?.response?.data?.message || e?.message || t('auth.totpConfirmFailed');
      setError(msg);
      toastError(msg);
    } finally {
      setConfirmingTotp(false);
    }
  };

  const regenerateTotpRecoveryCodes = async () => {
    if (!totpCode.trim()) return;
    const confirmed = await confirm({
      title: t('auth.confirmRegenerateRecoveryCodesTitle'),
      description: t('auth.confirmRegenerateRecoveryCodesDescription'),
      confirmText: t('auth.regenerateRecoveryCodes'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    });
    if (!confirmed) return;

    setRegeneratingRecoveryCodes(true);
    setError(null);
    try {
      if (!(await requestStepUp())) {
        return;
      }
      const resp = await TotpAuthService.regenerateRecoveryCodes(totpCode.trim());
      setRecoveryCodes(resp.data.recoveryCodes || []);
      setTotpCode('');
      await loadTotpStatus();
      setSuccessMsg(t('auth.totpRecoveryCodesRegenerated'));
      toastSuccess(t('auth.totpRecoveryCodesRegenerated'));
    } catch (e: any) {
      const msg = e?.response?.data?.message || e?.message || t('auth.totpRecoveryCodesRegenerateFailed');
      setError(msg);
      toastError(msg);
    } finally {
      setRegeneratingRecoveryCodes(false);
    }
  };

  const disableTotp = async () => {
    setDisablingTotp(true);
    setError(null);
    try {
      if (!(await requestStepUp())) {
        return;
      }
      await TotpAuthService.disable();
      setRecoveryCodes([]);
      setTotpEnrollment(null);
      setTotpCode('');
      await loadTotpStatus();
      setSuccessMsg(t('auth.totpDisabled'));
      toastSuccess(t('auth.totpDisabled'));
    } catch (e: any) {
      const msg = e?.response?.data?.message || e?.message || t('auth.totpDisableFailed');
      setError(msg);
      toastError(msg);
    } finally {
      setDisablingTotp(false);
    }
  };

  const copyRecoveryCodes = async () => {
    if (recoveryCodes.length === 0) return;
    try {
      await navigator.clipboard.writeText(recoveryCodes.join('\n'));
      toastSuccess(t('auth.recoveryCodesCopied'));
    } catch {
      toastError(t('auth.recoveryCodesCopyFailed'));
    }
  };

  const downloadRecoveryCodes = () => {
    if (recoveryCodes.length === 0) return;
    const blob = new Blob([recoveryCodes.join('\n')], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'lanlu-totp-recovery-codes.txt';
    link.click();
    URL.revokeObjectURL(url);
  };

  const handleAvatarSelected = async (file: File | null) => {
    if (!file) return;
    setError(null);
    setSuccessMsg(null);
    setAvatarFile(file);
    setAvatarZoom(1);
    setAvatarPan({ x: 0, y: 0 });
    const url = URL.createObjectURL(file);
    setAvatarUrl(url);
  };

  // Cleanup object URLs
  useEffect(() => {
    return () => {
      if (avatarUrl) URL.revokeObjectURL(avatarUrl);
    };
  }, [avatarUrl]);

  // Load image natural size
  useEffect(() => {
    if (!avatarUrl) {
      setAvatarNaturalSize(null);
      return;
    }
    const img = new Image();
    img.onload = () => {
      setAvatarNaturalSize({ w: img.naturalWidth, h: img.naturalHeight });
    };
    img.src = avatarUrl;
  }, [avatarUrl]);

  const renderAvatarPreview = (canvas: HTMLCanvasElement) => {
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const size = canvas.width; // square
    ctx.clearRect(0, 0, size, size);

    if (!avatarUrl || !avatarNaturalSize) {
      return;
    }

    const img = new Image();
    img.onload = () => {
      const w = avatarNaturalSize.w;
      const h = avatarNaturalSize.h;
      const baseScale = Math.max(size / w, size / h);
      const scale = baseScale * avatarZoom;
      const dw = w * scale;
      const dh = h * scale;

      // centered position + pan
      let dx = (size - dw) / 2 + avatarPan.x;
      let dy = (size - dh) / 2 + avatarPan.y;

      // clamp so image always covers the square
      const minDx = size - dw;
      const minDy = size - dh;
      dx = Math.min(0, Math.max(minDx, dx));
      dy = Math.min(0, Math.max(minDy, dy));

      // Draw the image clipped to a circle (common avatar UX).
      ctx.save();
      ctx.beginPath();
      ctx.arc(size / 2, size / 2, size / 2 - 6, 0, Math.PI * 2);
      ctx.closePath();
      ctx.clip();
      ctx.drawImage(img, dx, dy, dw, dh);
      ctx.restore();

      // No manual frame here; rely on CSS borders to avoid dark rings in light mode.

      // Don't mutate state here; this function can be used by multiple preview canvases.
    };
    img.src = avatarUrl;
  };

  const [avatarCanvasEl, setAvatarCanvasEl] = useState<HTMLCanvasElement | null>(null);
  const [avatarPreview100El, setAvatarPreview100El] = useState<HTMLCanvasElement | null>(null);
  const [avatarPreview50El, setAvatarPreview50El] = useState<HTMLCanvasElement | null>(null);

  const syncAvatarPreviews = useEffectEvent(() => {
    if (avatarCanvasEl) renderAvatarPreview(avatarCanvasEl);
    if (avatarPreview100El) renderAvatarPreview(avatarPreview100El);
    if (avatarPreview50El) renderAvatarPreview(avatarPreview50El);
  });

  useEffect(() => {
    syncAvatarPreviews();
  }, [avatarCanvasEl, avatarPreview100El, avatarPreview50El, avatarUrl, avatarZoom, avatarPan, avatarNaturalSize]);

  const exportAvatarAsFile = async (): Promise<File> => {
    const size = 256;
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;

    // Render using current settings into export canvas.
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('canvas not supported');
    if (!avatarUrl || !avatarNaturalSize) throw new Error('no avatar selected');

    const img = new Image();
    img.src = avatarUrl;
    await new Promise<void>((resolve, reject) => {
      img.onload = () => resolve();
      img.onerror = () => reject(new Error('failed to load image'));
    });

    const w = avatarNaturalSize.w;
    const h = avatarNaturalSize.h;
    const baseScale = Math.max(size / w, size / h);
    const scale = baseScale * avatarZoom;
    const dw = w * scale;
    const dh = h * scale;
    let dx = (size - dw) / 2 + avatarPan.x;
    let dy = (size - dh) / 2 + avatarPan.y;
    const minDx = size - dw;
    const minDy = size - dh;
    dx = Math.min(0, Math.max(minDx, dx));
    dy = Math.min(0, Math.max(minDy, dy));

    // Render cropped square (server will convert to AVIF; we keep alpha-free PNG).
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, size, size);
    ctx.drawImage(img, dx, dy, dw, dh);

    const blob: Blob = await new Promise((resolve, reject) => {
      canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('failed to encode image'))), 'image/png', 0.92);
    });

    return new File([blob], 'avatar.png', { type: 'image/png' });
  };

  const handleAvatarUpload = async () => {
    if (!avatarFile) return;
    setAvatarLoading(true);
    setError(null);
    setSuccessMsg(null);
    try {
      const cropped = await exportAvatarAsFile();
      await AuthService.uploadAvatar(cropped);
      await refreshMe();
      toastSuccess(t('auth.avatarUpdated'));
      // Keep the editor open, but you can clear selection if you prefer.
      setAvatarFile(null);
      if (avatarUrl) URL.revokeObjectURL(avatarUrl);
      setAvatarUrl(null);
      setAvatarNaturalSize(null);
    } catch (e: any) {
      const msg = e?.response?.data?.message || e?.message || 'Failed to upload avatar';
      setError(msg);
      toastError(msg);
    } finally {
      setAvatarLoading(false);
    }
  };

  const resetAvatarEditor = () => {
    setAvatarFile(null);
    if (avatarUrl) URL.revokeObjectURL(avatarUrl);
    setAvatarUrl(null);
    setAvatarNaturalSize(null);
    setAvatarZoom(1);
    setAvatarPan({ x: 0, y: 0 });
    setDragState(null);
    setError(null);
    setSuccessMsg(null);
  };

  const triggerAvatarFilePicker = () => fileInputEl?.click();

  return (
    <AuthGuard
      isAuthenticated={isAuthenticated}
      title={t('settings.auth')}
      description={t('settings.authDescription')}
      icon={KeyRound}
      t={t}
    >
      <div className="space-y-6">
        {stepUpDialog}
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <KeyRound className="w-5 h-5" />
              {t('settings.auth')}
            </h2>
            <p className="text-sm text-muted-foreground">{t('settings.authDescription')}</p>
          </div>
        </div>

      <Card>
        <CardContent className="py-4 space-y-3">
          {/* Hidden file input for avatar selection; triggered by "Change Avatar" buttons. */}
          <input
            ref={setFileInputEl}
            type="file"
            accept="image/*"
            className="hidden"
            disabled={avatarLoading}
            onChange={async (e) => {
              const f = e.target.files?.[0] || null;
              e.target.value = '';
              if (!f) return; // user canceled
              if (avatarUrl) URL.revokeObjectURL(avatarUrl);
              await handleAvatarSelected(f);
              setAvatarDialogOpen(true);
            }}
          />

          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-4 min-w-0">
              <Avatar className="h-14 w-14">
                <AvatarImage src={user?.avatarAssetId ? `/api/assets/${user.avatarAssetId}` : ''} alt={user?.username || ''} />
                <AvatarFallback>
                  <User className="h-6 w-6" />
                </AvatarFallback>
              </Avatar>
              <div className="min-w-0 space-y-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <Badge variant="secondary">{t('auth.loggedInAs')}</Badge>
                  <span className="font-medium truncate">{user?.username || user?.id || '-'}</span>
                  {user?.isAdmin ? <Badge variant="outline">{t('auth.admin')}</Badge> : null}
                </div>
                <p className="text-sm text-muted-foreground truncate">
                  ID: {user?.id ?? '-'}{user?.avatarAssetId ? ` • avatar #${user.avatarAssetId}` : ''}
                </p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Button type="button" variant="outline" onClick={triggerAvatarFilePicker} disabled={loading || avatarLoading}>
                {t('auth.changeAvatar')}
              </Button>
              <Button variant="outline" onClick={logout}>
                {t('auth.logout')}
              </Button>
            </div>
          </div>

          {error ? <p className="text-sm text-destructive">{error}</p> : null}
          {successMsg ? <p className="text-sm text-green-600">{successMsg}</p> : null}
        </CardContent>
      </Card>

      <Dialog open={avatarDialogOpen} onOpenChange={(open) => {
        setAvatarDialogOpen(open);
        if (!open) resetAvatarEditor();
      }}>
        <DialogContent size="xl">
          <DialogHeader>
            <DialogTitle>{t('auth.editAvatar')}</DialogTitle>
          </DialogHeader>
          <DialogBody>
            <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
              <div className="space-y-3">
                <div className="flex items-center justify-between gap-3">
                  <p className="text-sm text-muted-foreground">{t('auth.avatarDragHint')}</p>
                  <Button
                    type="button"
                    variant="outline"
                    disabled={avatarLoading}
                    onClick={triggerAvatarFilePicker}
                  >
                    {t('auth.avatarUpload')}
                  </Button>
                </div>

                <div className="w-full max-w-[640px]">
                  <canvas
                    width={420}
                    height={420}
                    ref={setAvatarCanvasEl}
                    className="w-full h-auto rounded-md border bg-muted cursor-move touch-none select-none"
                    onPointerDown={(e) => {
                      if (!avatarUrl) return;
                      (e.currentTarget as HTMLCanvasElement).setPointerCapture(e.pointerId);
                      setDragState({
                        dragging: true,
                        startX: e.clientX,
                        startY: e.clientY,
                        startPanX: avatarPan.x,
                        startPanY: avatarPan.y,
                      });
                    }}
                    onPointerMove={(e) => {
                      if (!dragState?.dragging) return;
                      const dx = e.clientX - dragState.startX;
                      const dy = e.clientY - dragState.startY;
                      setAvatarPan({ x: dragState.startPanX + dx, y: dragState.startPanY + dy });
                    }}
                    onPointerUp={(e) => {
                      (e.currentTarget as HTMLCanvasElement).releasePointerCapture(e.pointerId);
                      setDragState(null);
                    }}
                    onPointerCancel={() => setDragState(null)}
                  />
                </div>

                <div className="space-y-2">
                  <Label>{t('auth.avatarZoom')}</Label>
                  <Slider
                    min={1}
                    max={3}
                    step={0.01}
                    value={[avatarZoom]}
                    onValueChange={(v) => setAvatarZoom(v[0] ?? 1)}
                    disabled={!avatarUrl || avatarLoading}
                  />
                </div>
              </div>

              <div className="rounded-lg border bg-muted/30 p-4 space-y-5">
                <div className="space-y-3 text-center">
                  <p className="font-medium">{t('auth.avatarPreview')}</p>
                  <div className="flex flex-col items-center gap-4">
                    <div className="space-y-2">
                      <canvas
                        width={100}
                        height={100}
                        className="rounded-full border bg-muted"
                        ref={setAvatarPreview100El}
                      />
                      <p className="text-xs text-muted-foreground">100x100px</p>
                    </div>
                    <div className="space-y-2">
                      <canvas
                        width={50}
                        height={50}
                        className="rounded-full border bg-muted"
                        ref={setAvatarPreview50El}
                      />
                      <p className="text-xs text-muted-foreground">50x50px</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="outline" disabled={avatarLoading} onClick={() => setAvatarDialogOpen(false)}>
              {t('common.cancel')}
            </Button>
            <Button type="button" disabled={!avatarUrl || avatarLoading} onClick={handleAvatarUpload}>
              {avatarLoading ? t('common.saving') : t('common.save')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Card>
        <CardHeader>
          <CardTitle>{t('auth.changeCredentials')}</CardTitle>
          <CardDescription>{t('auth.changeCredentialsDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="space-y-2">
            <Label htmlFor="newUsername">{t('auth.username')}</Label>
            <Input
              id="newUsername"
              type="text"
              value={newUsername}
              onChange={(e) => setNewUsername(e.target.value)}
              placeholder={user?.username || ''}
              disabled={loading}
              maxLength={64}
            />
            {newUsername && newUsername.length < 3 && (
              <p className="text-sm text-destructive">{t('auth.usernameTooShort')}</p>
            )}
            {newUsername === user?.username && newUsername.length >= 3 && (
              <p className="text-sm text-muted-foreground">{t('auth.usernameUnchanged')}</p>
            )}
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
            <Input
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

          <Button onClick={handleSave} disabled={loading || !canSave} className="w-full">
            {loading ? t('common.saving') : t('common.save')}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('auth.totpManagement')}</CardTitle>
          <CardDescription>{t('auth.totpManagementDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="space-y-1">
              <div className="flex items-center gap-2">
                <ShieldCheck className="h-4 w-4 text-muted-foreground" />
                <span className="font-medium">
                  {totpStatus?.enabled ? t('auth.totpEnabledLabel') : t('auth.totpDisabledLabel')}
                </span>
              </div>
              {totpStatus?.enabled ? (
                <p className="text-sm text-muted-foreground">
                  {totpStatus.credentialName || t('auth.totpDefaultCredential')}
                  {totpStatus.createdAt ? ` · ${totpStatus.createdAt}` : ''}
                </p>
              ) : (
                <p className="text-sm text-muted-foreground">{t('auth.totpSetupHint')}</p>
              )}
            </div>
            <Button variant="ghost" size="sm" onClick={loadTotpStatus} disabled={totpLoading}>
              {t('common.refresh')}
            </Button>
          </div>

          {!totpStatus?.enabled ? (
            <div className="space-y-4 rounded-md border p-4">
              <div className="space-y-2">
                <Label htmlFor="totpName">{t('auth.totpAppName')}</Label>
                <Input
                  id="totpName"
                  value={totpName}
                  onChange={(e) => setTotpName(e.target.value)}
                  placeholder={t('auth.totpAppNamePlaceholder')}
                  disabled={enrollingTotp || confirmingTotp}
                />
              </div>
              {!totpEnrollment ? (
                <Button onClick={startTotpEnrollment} disabled={enrollingTotp}>
                  {enrollingTotp ? t('auth.totpGenerating') : t('auth.totpStartEnrollment')}
                </Button>
              ) : (
                <div className="space-y-4">
                  <div className="flex flex-col gap-4 md:flex-row">
                    <div className="rounded-lg border bg-white p-3">
                      <QRCodeSVG value={totpEnrollment.otpauthUri} size={160} />
                    </div>
                    <div className="min-w-0 flex-1 space-y-3">
                      <div className="space-y-1">
                        <p className="text-sm font-medium flex items-center gap-2">
                          <QrCode className="h-4 w-4" />
                          {t('auth.scanQrCode')}
                        </p>
                        <p className="text-sm text-muted-foreground">{t('auth.scanQrCodeDescription')}</p>
                      </div>
                      <div className="space-y-1">
                        <p className="text-sm font-medium">{t('auth.manualEntryKey')}</p>
                        <p className="break-all rounded-md border bg-muted/40 px-3 py-2 font-mono text-sm">
                          {totpEnrollment.manualEntryKey}
                        </p>
                      </div>
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="totpCode">{t('auth.totpCode')}</Label>
                    <Input
                      id="totpCode"
                      name="totp"
                      type="text"
                      value={totpCode}
                      onChange={(e) => setTotpCode(e.target.value)}
                      placeholder={t('auth.totpCodePlaceholder')}
                      disabled={confirmingTotp}
                      inputMode="numeric"
                      autoComplete="one-time-code"
                      autoCapitalize="none"
                      autoCorrect="off"
                    />
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button onClick={confirmTotpEnrollment} disabled={confirmingTotp || !totpCode.trim()}>
                      {confirmingTotp ? t('auth.totpConfirming') : t('auth.totpConfirmEnrollment')}
                    </Button>
                    <Button variant="ghost" onClick={() => setTotpEnrollment(null)} disabled={confirmingTotp}>
                      {t('common.cancel')}
                    </Button>
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div className="space-y-4 rounded-md border p-4">
              <p className="text-sm text-muted-foreground">
                {t('auth.recoveryCodesRemaining')}: {totpStatus?.recoveryCodesRemaining ?? 0}
              </p>

              <div className="space-y-2">
                <Label htmlFor="totpCurrentCode">{t('auth.totpCode')}</Label>
                <Input
                  id="totpCurrentCode"
                  name="totp"
                  type="text"
                  value={totpCode}
                  onChange={(e) => setTotpCode(e.target.value)}
                  placeholder={t('auth.totpCodePlaceholder')}
                  disabled={regeneratingRecoveryCodes}
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  autoCapitalize="none"
                  autoCorrect="off"
                />
                <Button onClick={regenerateTotpRecoveryCodes} disabled={regeneratingRecoveryCodes || !totpCode.trim()}>
                  {regeneratingRecoveryCodes ? t('auth.totpRegeneratingRecoveryCodes') : t('auth.regenerateRecoveryCodes')}
                </Button>
              </div>

              <div className="space-y-2">
                <Button
                  variant="destructive"
                  onClick={disableTotp}
                  disabled={disablingTotp}
                >
                  {disablingTotp ? t('auth.disablingTotp') : t('auth.disableTotp')}
                </Button>
              </div>
            </div>
          )}

          {recoveryCodes.length > 0 ? (
            <div className="space-y-3 rounded-md border border-dashed p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <p className="font-medium">{t('auth.recoveryCodes')}</p>
                  <p className="text-sm text-muted-foreground">{t('auth.recoveryCodesDescription')}</p>
                </div>
                <div className="flex gap-2">
                  <Button variant="secondary" size="sm" onClick={copyRecoveryCodes}>
                    {t('auth.copyRecoveryCodes')}
                  </Button>
                  <Button variant="secondary" size="sm" onClick={downloadRecoveryCodes}>
                    {t('auth.downloadRecoveryCodes')}
                  </Button>
                </div>
              </div>
              <div className="grid gap-2 sm:grid-cols-2">
                {recoveryCodes.map((code) => (
                  <div key={code} className="rounded-md border bg-muted/40 px-3 py-2 font-mono text-sm">
                    {code}
                  </div>
                ))}
              </div>
            </div>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('auth.passkeyManagement')}</CardTitle>
          <CardDescription>{t('auth.passkeyManagementDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {passkeySupported ? (
            <>
              <div className="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end">
                <div className="space-y-2">
                  <Label htmlFor="newPasskeyName">{t('auth.passkeyName')}</Label>
                  <Input
                    id="newPasskeyName"
                    value={newPasskeyName}
                    onChange={(e) => setNewPasskeyName(e.target.value)}
                    placeholder={t('auth.passkeyNamePlaceholder')}
                    disabled={registeringPasskey}
                  />
                </div>
                <Button onClick={registerPasskey} disabled={registeringPasskey}>
                  {registeringPasskey ? t('auth.passkeyRegistering') : t('auth.passkeyRegister')}
                </Button>
              </div>

              <div className="flex items-center justify-between">
                <p className="text-sm text-muted-foreground">{t('auth.passkeys')}</p>
                <Button variant="ghost" size="sm" onClick={loadPasskeys} disabled={passkeysLoading}>
                  {t('common.refresh')}
                </Button>
              </div>

              {passkeysLoading ? (
                <p className="text-sm text-muted-foreground">{t('common.loading')}</p>
              ) : passkeys.length === 0 ? (
                <p className="text-sm text-muted-foreground">{t('auth.noPasskeys')}</p>
              ) : (
                <div className="space-y-2">
                  {passkeys.map((passkey) => (
                    <div
                      key={passkey.id}
                      className="flex flex-col gap-2 rounded-md border p-3 sm:flex-row sm:items-center sm:justify-between"
                    >
                      <div className="min-w-0 space-y-1">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="font-medium">{passkey.name || t('auth.unnamedPasskey')}</span>
                          <Badge variant="outline">{passkey.algorithm}</Badge>
                          {passkey.userVerified ? <Badge variant="secondary">{t('auth.passkeyUserVerified')}</Badge> : null}
                        </div>
                        <p className="text-xs text-muted-foreground break-all">
                          {passkey.credentialId}
                        </p>
                        {passkey.lastUsedAt ? (
                          <p className="text-xs text-muted-foreground">
                            {t('auth.lastUsed')}: {passkey.lastUsedAt}
                          </p>
                        ) : null}
                      </div>
                      <Button variant="destructive" size="sm" onClick={() => revokePasskey(passkey.id)} disabled={loading}>
                        {t('common.delete')}
                      </Button>
                    </div>
                  ))}
                </div>
              )}
            </>
          ) : (
            <p className="text-sm text-muted-foreground">{t('auth.passkeyUnavailable')}</p>
          )}
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
            <div className="flex items-center gap-2">
              <Button variant="outline" size="sm" onClick={revokeOtherSessions} disabled={loading || sessionsLoading || sessions.length <= 1}>
                {t('auth.revokeOtherSessions')}
              </Button>
              <Button variant="ghost" size="sm" onClick={loadSessions} disabled={sessionsLoading}>
                {t('common.refresh')}
              </Button>
            </div>
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
                      {session.current ? <Badge>{t('auth.currentSession')}</Badge> : null}
                    </div>
                    {session.createdAt && (
                      <p className="text-xs text-muted-foreground">
                        {t('auth.createdAt')}: {session.createdAt}
                      </p>
                    )}
                    {session.lastUsedAt && (
                      <p className="text-xs text-muted-foreground">
                        {t('auth.lastUsed')}: {session.lastUsedAt}
                      </p>
                    )}
                    {session.lastUsedIp ? (
                      <p className="text-xs text-muted-foreground">
                        IP: {session.lastUsedIp}
                      </p>
                    ) : null}
                  </div>
                  <Button variant="destructive" size="sm" onClick={() => revokeSession(session.id)} disabled={loading}>
                    {session.current ? t('auth.logout') : t('auth.revokeSession')}
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
    </AuthGuard>
  );
}
