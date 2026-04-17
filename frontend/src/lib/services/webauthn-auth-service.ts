import { apiClient } from '@/lib/api';
import type { ApiEnvelope, AuthToken, AuthUser, PasskeyCredential } from '@/types/auth';

type WebauthnCredentialDescriptor = {
  id: string;
  type: string;
};

type WebauthnPubKeyCredParam = {
  type: string;
  alg: number;
};

type WebauthnRegistrationOptionsPayload = {
  challengeId: string;
  publicKey: {
    challenge: string;
    rp: { id: string; name: string };
    user: { id: string; name: string; displayName: string };
    timeout: number;
    pubKeyCredParams: WebauthnPubKeyCredParam[];
    excludeCredentials: WebauthnCredentialDescriptor[];
    attestation: AttestationConveyancePreference;
    authenticatorSelection?: {
      residentKey?: ResidentKeyRequirement;
      userVerification?: UserVerificationRequirement;
      authenticatorAttachment?: AuthenticatorAttachment;
    };
  };
};

type WebauthnAuthenticationOptionsPayload = {
  challengeId: string;
  publicKey: {
    challenge: string;
    timeout: number;
    rpId: string;
    allowCredentials: WebauthnCredentialDescriptor[];
    userVerification?: UserVerificationRequirement;
  };
};

function base64UrlToArrayBuffer(input: string): ArrayBuffer {
  const padding = (4 - (input.length % 4)) % 4;
  const base64 = `${input}${'='.repeat(padding)}`.replace(/-/g, '+').replace(/_/g, '/');
  const binary = window.atob(base64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    out[i] = binary.charCodeAt(i);
  }
  return out.buffer.slice(0);
}

function arrayBufferToBase64Url(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return window.btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function toCreationOptions(
  payload: WebauthnRegistrationOptionsPayload['publicKey']
): PublicKeyCredentialCreationOptions {
  return {
    challenge: base64UrlToArrayBuffer(payload.challenge),
    rp: payload.rp,
    user: {
      ...payload.user,
      id: base64UrlToArrayBuffer(payload.user.id),
    },
    timeout: payload.timeout,
    pubKeyCredParams: payload.pubKeyCredParams.map((item) => ({
      type: item.type as 'public-key',
      alg: item.alg,
    })),
    attestation: payload.attestation,
    authenticatorSelection: payload.authenticatorSelection,
    excludeCredentials: payload.excludeCredentials.map((item) => ({
      id: base64UrlToArrayBuffer(item.id),
      type: item.type as PublicKeyCredentialType,
    })),
  };
}

function toRequestOptions(
  payload: WebauthnAuthenticationOptionsPayload['publicKey']
): PublicKeyCredentialRequestOptions {
  return {
    challenge: base64UrlToArrayBuffer(payload.challenge),
    timeout: payload.timeout,
    rpId: payload.rpId,
    userVerification: payload.userVerification,
    allowCredentials: payload.allowCredentials.map((item) => ({
      id: base64UrlToArrayBuffer(item.id),
      type: item.type as PublicKeyCredentialType,
    })),
  };
}

function serializeRegistrationCredential(credential: PublicKeyCredential) {
  const response = credential.response as AuthenticatorAttestationResponse;
  const transports = typeof response.getTransports === 'function' ? response.getTransports() : [];
  return {
    id: credential.id,
    rawId: arrayBufferToBase64Url(credential.rawId),
    clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
    attestationObject: arrayBufferToBase64Url(response.attestationObject),
    transports,
  };
}

function serializeAuthenticationCredential(credential: PublicKeyCredential) {
  const response = credential.response as AuthenticatorAssertionResponse;
  return {
    id: credential.id,
    rawId: arrayBufferToBase64Url(credential.rawId),
    clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
    authenticatorData: arrayBufferToBase64Url(response.authenticatorData),
    signature: arrayBufferToBase64Url(response.signature),
    userHandle: response.userHandle ? arrayBufferToBase64Url(response.userHandle) : '',
  };
}

export class WebauthnAuthService {
  static isSupported(): boolean {
    return typeof window !== 'undefined' &&
      typeof window.PublicKeyCredential !== 'undefined' &&
      typeof navigator !== 'undefined' &&
      typeof navigator.credentials !== 'undefined';
  }

  private static async authenticateWithPasskey<ResultData>(
    optionsUrl: string,
    verifyUrl: string
  ): Promise<ApiEnvelope<ResultData>> {
    const optionsRes = await apiClient.post<ApiEnvelope<WebauthnAuthenticationOptionsPayload>>(
      optionsUrl,
      {}
    );
    const { challengeId, publicKey } = optionsRes.data.data;
    const credential = await navigator.credentials.get({
      publicKey: toRequestOptions(publicKey),
    });
    if (!(credential instanceof PublicKeyCredential)) {
      throw new Error('Passkey authentication was cancelled');
    }
    const verifyRes = await apiClient.post<ApiEnvelope<ResultData>>(verifyUrl, {
      challengeId,
      credential: serializeAuthenticationCredential(credential),
    });
    return verifyRes.data;
  }

  static async registerPasskey(name?: string) {
    const optionsRes = await apiClient.post<ApiEnvelope<WebauthnRegistrationOptionsPayload>>(
      '/api/auth/webauthn/register/options',
      { name: name?.trim() || '' }
    );
    const { challengeId, publicKey } = optionsRes.data.data;
    const credential = await navigator.credentials.create({
      publicKey: toCreationOptions(publicKey),
    });
    if (!(credential instanceof PublicKeyCredential)) {
      throw new Error('Passkey creation was cancelled');
    }
    const verifyRes = await apiClient.post<ApiEnvelope<null>>('/api/auth/webauthn/register/verify', {
      challengeId,
      name: name?.trim() || '',
      credential: serializeRegistrationCredential(credential),
    });
    return verifyRes.data;
  }

  static async loginWithPasskey() {
    return this.authenticateWithPasskey<{ user: AuthUser; token: AuthToken & { token: string } }>(
      '/api/auth/webauthn/authenticate/options',
      '/api/auth/webauthn/authenticate/verify'
    );
  }

  static async verifyStepUpWithPasskey() {
    return this.authenticateWithPasskey<null>(
      '/api/auth/step-up/webauthn/options',
      '/api/auth/step-up/webauthn/verify'
    );
  }

  static async listCredentials() {
    const res = await apiClient.get<ApiEnvelope<{ credentials: PasskeyCredential[] }>>(
      '/api/auth/webauthn/credentials'
    );
    return res.data;
  }

  static async revokeCredential(id: number) {
    const res = await apiClient.delete<ApiEnvelope<null>>(`/api/auth/webauthn/credentials/${id}`, {
      data: {},
    });
    return res.data;
  }
}
