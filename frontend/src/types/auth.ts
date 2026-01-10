export type { ApiEnvelope } from './common';

export type AuthUser = {
  id: number;
  username: string;
  isAdmin?: boolean;
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

