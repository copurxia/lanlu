import { apiClient } from '@/lib/api';
import type { ApiEnvelope, AuthToken, AuthUser, AuthSession, AuthLoginPendingTotp } from '@/types/auth';
import { ChunkedUploadService } from './chunked-upload-service';

export class AuthService {
  static async login(params: { username: string; password: string; tokenName?: string }) {
    const res = await apiClient.post<
      ApiEnvelope<{ user: AuthUser; token: AuthToken & { token: string } } | AuthLoginPendingTotp>
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

  static async changePassword(params: { newPassword: string }) {
    const res = await apiClient.post<ApiEnvelope<null>>('/api/auth/password', {
      newPassword: params.newPassword,
    });
    return res.data;
  }

  static async changeUsername(newUsername: string) {
    const res = await apiClient.post<ApiEnvelope<{ user: AuthUser }>>('/api/auth/username', {
      newUsername,
    });
    return res.data;
  }

  static async uploadAvatar(file: File) {
    const result = await ChunkedUploadService.uploadWithChunks(
      file,
      {
        targetType: 'user_avatar',
        overwrite: true,
        contentType: file.type || 'application/octet-stream',
      },
      {
        onProgress: () => {},
        onChunkComplete: () => {},
        onError: () => {},
      }
    );
    if (!result.success) {
      throw new Error(result.error || 'Avatar upload failed');
    }

    let avatarAssetId = Number(result.data?.avatarAssetId ?? result.data?.assetId ?? 0);
    if (!avatarAssetId) {
      const me = await this.me();
      avatarAssetId = Number(me?.data?.user?.avatarAssetId ?? 0);
    }

    return {
      code: 200,
      message: 'ok',
      data: { avatarAssetId },
    } as ApiEnvelope<{ avatarAssetId: number }>;
  }
}
