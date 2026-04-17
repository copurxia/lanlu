export type { ApiEnvelope } from './common';

export type AuthUser = {
  id: number;
  username: string;
  isAdmin?: boolean;
  avatarAssetId?: number;
};

export type AdminUser = {
  id: number;
  username: string;
  isAdmin: boolean;
  createdAt?: string;
};

export type AuthToken = {
  id: number;
  name: string;
  prefix: string;
  createdAt?: string;
  lastUsedAt?: string;
  token?: string; // only returned once on create/login/register
};

export type AuthSession = {
  id: number;
  name: string;
  prefix: string;
  createdAt?: string;
  lastUsedAt?: string;
};

export type PasskeyCredential = {
  id: number;
  name: string;
  credentialId: string;
  algorithm: string;
  transports: string[];
  userVerified: boolean;
  backupEligible: boolean;
  backupState: boolean;
  createdAt: string;
  lastUsedAt: string;
};
