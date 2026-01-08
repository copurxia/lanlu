export function formatFileSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.min(sizes.length - 1, Math.floor(Math.log(bytes) / Math.log(k)));
  const value = bytes / Math.pow(k, i);
  return `${parseFloat(value.toFixed(2))} ${sizes[i]}`;
}

export function formatDate(dateString: string, unknownLabel: string): string {
  if (!dateString) return unknownLabel;
  try {
    return new Date(dateString).toLocaleString();
  } catch {
    return dateString;
  }
}

