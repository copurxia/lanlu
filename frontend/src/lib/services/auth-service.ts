import { apiClient, type AuthRequestConfig } from '@/lib/api';
import type { ApiEnvelope, AuthToken, AuthUser, AuthSession, AuthLoginPendingTotp } from '@/types/auth';
import { ChunkedUploadService } from './chunked-upload-service';

export class AuthService {
  static async login(
    params: { username: string; password: string; tokenName?: string }
  ): Promise<ApiEnvelope<{ user: AuthUser; token: AuthToken & { token: string } } | AuthLoginPendingTotp>> {
    const res = await apiClient.post<
      ApiEnvelope<{ user: AuthUser; token: AuthToken & { token: string } } | AuthLoginPendingTotp>
    >('/api/auth/login', {
      username: params.username,
      password: params.password,
      tokenName: params.tokenName || 'login',
    });
    return res.data as ApiEnvelope<{ user: AuthUser; token: AuthToken & { token: string } } | AuthLoginPendingTotp>;
  }

  static async me(): Promise<ApiEnvelope<{ user: AuthUser }>> {
    const res = await apiClient.get<ApiEnvelope<{ user: AuthUser }>>('/api/auth/me', {
      skipAuthRedirect: true,
    } as AuthRequestConfig);
    return res.data as ApiEnvelope<{ user: AuthUser }>;
  }

  static async listTokens(): Promise<ApiEnvelope<{ tokens: AuthToken[] }>> {
    const res = await apiClient.get<ApiEnvelope<{ tokens: AuthToken[] }>>('/api/auth/tokens');
    return res.data as ApiEnvelope<{ tokens: AuthToken[] }>;
  }

  static async listSessions(): Promise<ApiEnvelope<{ sessions: AuthSession[] }>> {
    const res = await apiClient.get<ApiEnvelope<{ sessions: AuthSession[] }>>('/api/auth/sessions');
    return res.data as ApiEnvelope<{ sessions: AuthSession[] }>;
  }

  static async revokeSession(id: number): Promise<ApiEnvelope<null>> {
    const res = await apiClient.delete<ApiEnvelope<null>>(`/api/auth/sessions/${id}`);
    return res.data as ApiEnvelope<null>;
  }

  static async revokeOtherSessions(): Promise<ApiEnvelope<null>> {
    const res = await apiClient.post<ApiEnvelope<null>>('/api/auth/sessions/revoke-others', {});
    return res.data as ApiEnvelope<null>;
  }

  static async createToken(name: string): Promise<ApiEnvelope<{ token: AuthToken & { token: string } }>> {
    const res = await apiClient.post<ApiEnvelope<{ token: AuthToken & { token: string } }>>(
      '/api/auth/tokens',
      { name }
    );
    return res.data as ApiEnvelope<{ token: AuthToken & { token: string } }>;
  }

  static async revokeToken(id: number): Promise<ApiEnvelope<null>> {
    const res = await apiClient.delete<ApiEnvelope<null>>(`/api/auth/tokens/${id}`);
    return res.data as ApiEnvelope<null>;
  }

  static async changePassword(params: { newPassword: string }): Promise<ApiEnvelope<null>> {
    const res = await apiClient.post<ApiEnvelope<null>>('/api/auth/password', {
      newPassword: params.newPassword,
    });
    return res.data as ApiEnvelope<null>;
  }

  static async logout(): Promise<ApiEnvelope<null>> {
    const res = await apiClient.post<ApiEnvelope<null>>('/api/auth/logout', {}, {
      skipAuthRedirect: true,
    } as AuthRequestConfig);
    return res.data as ApiEnvelope<null>;
  }

  static async changeUsername(newUsername: string): Promise<ApiEnvelope<{ user: AuthUser }>> {
    const res = await apiClient.post<ApiEnvelope<{ user: AuthUser }>>('/api/auth/username', {
      newUsername,
    });
    return res.data as ApiEnvelope<{ user: AuthUser }>;
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
