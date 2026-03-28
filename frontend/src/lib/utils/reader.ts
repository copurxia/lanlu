export function buildReaderPath(id: string, page?: number): string {
  const archiveId = String(id || '').trim();
  if (!archiveId) return '/reader';

  const normalizedPage =
    typeof page === 'number' && Number.isFinite(page) && page > 0
      ? Math.trunc(page)
      : 0;

  if (normalizedPage > 0) {
    return `/reader?id=${archiveId}&page=${normalizedPage}`;
  }

  return `/reader?id=${archiveId}`;
}
