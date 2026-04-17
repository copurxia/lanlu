'use client';

import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { StepUpAuthService, type StepUpOptions } from '@/lib/services/step-up-auth-service';
import { WebauthnAuthService } from '@/lib/services/webauthn-auth-service';

type StepUpMethod = 'password' | 'totp' | 'passkey';

interface StepUpDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onVerified: () => void;
}

export function StepUpDialog({ open, onOpenChange, onVerified }: StepUpDialogProps) {
  const [loading, setLoading] = useState(false);
  const [options, setOptions] = useState<StepUpOptions | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [method, setMethod] = useState<StepUpMethod>('password');
  const [password, setPassword] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [recoveryCode, setRecoveryCode] = useState('');
  const [totpMode, setTotpMode] = useState<'totp' | 'recovery'>('totp');
  const passkeySupported = useMemo(() => WebauthnAuthService.isSupported(), []);

  useEffect(() => {
    if (!open) {
      setLoading(false);
      setError(null);
      setPassword('');
      setTotpCode('');
      setRecoveryCode('');
      setTotpMode('totp');
      return;
    }

    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const resp = await StepUpAuthService.getOptions();
        const nextOptions = resp.data;
        setOptions(nextOptions);
        if (nextOptions.methods.includes('passkey') && passkeySupported) {
          setMethod('passkey');
        } else if (nextOptions.methods.includes('totp')) {
          setMethod('totp');
        } else {
          setMethod('password');
        }
      } catch (e: any) {
        setError(e?.response?.data?.message || e?.message || 'Failed to load verification options');
      } finally {
        setLoading(false);
      }
    })();
  }, [open, passkeySupported]);

  const verify = async () => {
    setLoading(true);
    setError(null);
    try {
      if (method === 'password') {
        await StepUpAuthService.verifyPassword(password);
      } else if (method === 'totp') {
        await StepUpAuthService.verifyTotp({
          code: totpMode === 'totp' ? totpCode : '',
          recoveryCode: totpMode === 'recovery' ? recoveryCode : '',
        });
      } else {
        await StepUpAuthService.verifyPasskey();
      }
      onVerified();
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || 'Verification failed');
    } finally {
      setLoading(false);
    }
  };

  const methods = options?.methods || ['password'];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent size="sm">
        <DialogHeader>
          <DialogTitle>二次认证</DialogTitle>
        </DialogHeader>
        <DialogBody className="space-y-4">
          <p className="text-sm text-muted-foreground">
            这是高风险操作，请先完成一次身份确认。
          </p>

          <div className="flex flex-wrap gap-2">
            {methods.includes('password') && (
              <Button type="button" variant={method === 'password' ? 'default' : 'outline'} onClick={() => setMethod('password')}>
                密码
              </Button>
            )}
            {methods.includes('totp') && (
              <Button type="button" variant={method === 'totp' ? 'default' : 'outline'} onClick={() => setMethod('totp')}>
                TOTP
              </Button>
            )}
            {methods.includes('passkey') && passkeySupported && (
              <Button type="button" variant={method === 'passkey' ? 'default' : 'outline'} onClick={() => setMethod('passkey')}>
                Passkey
              </Button>
            )}
          </div>

          {method === 'password' && (
            <div className="space-y-2">
              <Label htmlFor="step-up-password">当前密码</Label>
              <Input
                id="step-up-password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="current-password"
                disabled={loading}
              />
            </div>
          )}

          {method === 'totp' && (
            <div className="space-y-3">
              <div className="flex gap-2">
                <Button type="button" variant={totpMode === 'totp' ? 'default' : 'outline'} onClick={() => setTotpMode('totp')}>
                  验证码
                </Button>
                <Button type="button" variant={totpMode === 'recovery' ? 'default' : 'outline'} onClick={() => setTotpMode('recovery')}>
                  恢复码
                </Button>
              </div>
              {totpMode === 'totp' ? (
                <div className="space-y-2">
                  <Label htmlFor="step-up-totp">TOTP 验证码</Label>
                  <Input
                    id="step-up-totp"
                    name="totp"
                    type="text"
                    value={totpCode}
                    onChange={(e) => setTotpCode(e.target.value)}
                    disabled={loading}
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    autoCapitalize="none"
                    autoCorrect="off"
                  />
                </div>
              ) : (
                <div className="space-y-2">
                  <Label htmlFor="step-up-recovery">恢复码</Label>
                  <Input
                    id="step-up-recovery"
                    name="recovery_code"
                    type="text"
                    value={recoveryCode}
                    onChange={(e) => setRecoveryCode(e.target.value)}
                    disabled={loading}
                    autoComplete="off"
                    autoCapitalize="none"
                    autoCorrect="off"
                  />
                </div>
              )}
            </div>
          )}

          {method === 'passkey' && (
            <p className="text-sm text-muted-foreground">
              点击确认后将调用浏览器的 Passkey 验证。
            </p>
          )}

          {error && <p className="text-sm text-destructive">{error}</p>}
        </DialogBody>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={loading}>
            取消
          </Button>
          <Button
            type="button"
            onClick={verify}
            disabled={
              loading ||
              (method === 'password' && !password.trim()) ||
              (method === 'totp' && totpMode === 'totp' && !totpCode.trim()) ||
              (method === 'totp' && totpMode === 'recovery' && !recoveryCode.trim())
            }
          >
            确认
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
