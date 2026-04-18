import { apiClient } from '@/lib/api';
import type { ApiEnvelope } from '@/types/common';

export type StepUpOptions = {
  methods: string[];
};

export class StepUpAuthService {
  static async getOptions(): Promise<ApiEnvelope<StepUpOptions>> {
    const res = await apiClient.get<ApiEnvelope<StepUpOptions>>('/api/auth/step-up/options');
    return res.data as ApiEnvelope<StepUpOptions>;
  }

  static async verifyPassword(password: string): Promise<ApiEnvelope<null>> {
    const res = await apiClient.post<ApiEnvelope<null>>('/api/auth/step-up/password', { password });
    return res.data as ApiEnvelope<null>;
  }

  static async verifyTotp(params: { code?: string; recoveryCode?: string }): Promise<ApiEnvelope<null>> {
    const res = await apiClient.post<ApiEnvelope<null>>('/api/auth/step-up/totp', {
      code: params.code || '',
      recoveryCode: params.recoveryCode || '',
    });
    return res.data as ApiEnvelope<null>;
  }
}
