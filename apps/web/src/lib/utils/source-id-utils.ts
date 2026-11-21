/**
 * Source 复合 ID 工具函数
 *
 * 解析和构建 source:namespace:remote_id 格式的复合 ID，
 * 替换前端散落的 startsWith('source:') + split(':') 手动解析。
 */

export interface SourceIdParsed {
  namespace: string;
  remoteId: string;
}

/**
 * 解析 source:namespace:remote_id 格式的复合 ID
 */
export function parseSourceId(id: string): SourceIdParsed | null {
  if (!id || !id.startsWith('source:')) return null;
  const parts = id.split(':');
  if (parts.length < 3) return null;
  const namespace = parts[1];
  const remoteId = parts.slice(2).join(':');
  if (!namespace || !remoteId) return null;
  return { namespace, remoteId };
}


