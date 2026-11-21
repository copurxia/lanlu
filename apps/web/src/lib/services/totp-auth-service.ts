import { apiClient } from '@/lib/api';
import type {
  ApiEnvelope,
  AuthToken,
  AuthUser,
  TotpEnrollmentPayload,
  TotpStatus,
} from '@/types/auth';

export class TotpAuthService {
  static async verifyLogin(params: { challengeId: string; code?: string; recoveryCode?: string }) {
    const res = await apiClient.post<
      ApiEnvelope<{ user: AuthUser; token: AuthToken & { token: string } }>
    >('/api/auth/login/totp/verify', {
      challengeId: params.challengeId,
      code: params.code || '',
      recoveryCode: params.recoveryCode || '',
    });
    return res.data;
  }

  static async getStatus() {
    const res = await apiClient.get<ApiEnvelope<TotpStatus>>('/api/auth/totp/status');
    return res.data;
  }

  static async startEnrollment(name?: string) {
    const res = await apiClient.post<ApiEnvelope<TotpEnrollmentPayload>>('/api/auth/totp/enroll/start', {
      name: name?.trim() || '',
    });
    return res.data;
  }

  static async confirmEnrollment(params: { challengeId: string; code: string; name?: string }) {
    const res = await apiClient.post<ApiEnvelope<{ recoveryCodes: string[] }>>('/api/auth/totp/enroll/confirm', {
      challengeId: params.challengeId,
      code: params.code,
      name: params.name?.trim() || '',
    });
    return res.data;
  }

  static async regenerateRecoveryCodes(code: string) {
    const res = await apiClient.post<ApiEnvelope<{ recoveryCodes: string[] }>>(
      '/api/auth/totp/recovery-codes/regenerate',
      { code }
    );
    return res.data;
  }

  static async disable() {
    const res = await apiClient.delete<ApiEnvelope<null>>('/api/auth/totp');
    return res.data;
  }
}
