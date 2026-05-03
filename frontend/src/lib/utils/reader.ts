export function buildReaderPath(id: string, page?: number, tankoubonId?: string): string {
  const archiveId = String(id || '').trim();
  if (!archiveId) return '/reader';

  const normalizedPage =
    typeof page === 'number' && Number.isFinite(page) && page > 0
      ? Math.trunc(page)
      : 0;

  const parts = [`/reader?id=${archiveId}`];
  if (normalizedPage > 0) parts.push(`page=${normalizedPage}`);
  if (tankoubonId) parts.push(`tankoubon=${encodeURIComponent(tankoubonId)}`);

  return parts.join('&');
}
