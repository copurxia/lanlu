import { apiClient } from '@/lib/api';
import type { ApiEnvelope, AuthToken, AuthUser, AuthSession } from '@/types/auth';

export class AuthService {
  static async register(params: { username: string; password: string; tokenName?: string }) {
    const res = await apiClient.post<
      ApiEnvelope<{ user: AuthUser; token: AuthToken & { token: string } }>
    >('/api/auth/register', {
      username: params.username,
      password: params.password,
      tokenName: params.tokenName || 'default',
    });
    return res.data;
  }

  static async login(params: { username: string; password: string; tokenName?: string }) {
    const res = await apiClient.post<
      ApiEnvelope<{ user: AuthUser; token: AuthToken & { token: string } }>
    >('/api/auth/login', {
      username: params.username,
      password: params.password,
      tokenName: params.tokenName || 'login',
    });
    return res.data;
  }

  static async me() {
    const res = await apiClient.get<ApiEnvelope<{ user: AuthUser }>>('/api/auth/me');
    return res.data;
  }

  static async listTokens() {
    const res = await apiClient.get<ApiEnvelope<{ tokens: AuthToken[] }>>('/api/auth/tokens');
    return res.data;
  }

  static async listSessions() {
    const res = await apiClient.get<ApiEnvelope<{ sessions: AuthSession[] }>>('/api/auth/sessions');
    return res.data;
  }

  static async createToken(name: string) {
    const res = await apiClient.post<ApiEnvelope<{ token: AuthToken & { token: string } }>>(
      '/api/auth/tokens',
      { name }
    );
    return res.data;
  }

  static async revokeToken(id: number) {
    const res = await apiClient.delete<ApiEnvelope<null>>(`/api/auth/tokens/${id}`);
    return res.data;
  }

  static async changePassword(params: { oldPassword: string; newPassword: string }) {
    const res = await apiClient.post<ApiEnvelope<null>>('/api/auth/password', {
      oldPassword: params.oldPassword,
      newPassword: params.newPassword,
    });
    return res.data;
  }
}

