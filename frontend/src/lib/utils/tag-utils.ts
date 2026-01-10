/**
 * 标签相关工具函数
 */

/**
 * 去掉 namespace 前缀的简单显示函数
 * 例如: "artist:name" -> "name"
 */
export function stripNamespace(tag: string): string {
  const idx = tag.indexOf(':');
  return idx > 0 ? tag.slice(idx + 1) : tag;
}

/**
 * 解析标签字符串为数组
 */
export function parseTags(tags: string | undefined | null): string[] {
  if (!tags) return [];
  return tags.split(',').map(tag => tag.trim()).filter(tag => tag);
}
