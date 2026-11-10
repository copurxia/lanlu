const RECOMMENDATION_SESSION_STORAGE_KEY = 'recommendation_session_key';

function createSessionKey(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `reco_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

export function getRecommendationSessionKey(): string {
  if (typeof window === 'undefined') {
    return 'server-session';
  }

  const existing = window.localStorage.getItem(RECOMMENDATION_SESSION_STORAGE_KEY);
  if (existing) {
    return existing;
  }

  const created = createSessionKey();
  window.localStorage.setItem(RECOMMENDATION_SESSION_STORAGE_KEY, created);
  return created;
}
