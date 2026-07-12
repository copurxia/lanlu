/**
 * JSON 辅助函数 & URL 编码 & 查询字符串构建
 */

/**
 * 从 JS 对象中安全获取字符串字段
 */
export function getString(obj, key) {
  const v = obj?.[key];
  return typeof v === 'string' ? v : undefined;
}

/**
 * 从 JS 对象中安全获取整数字段
 */
export function getInt(obj, key) {
  const v = obj?.[key];
  return typeof v === 'number' ? v : undefined;
}

/**
 * 从 JS 对象中安全获取布尔字段
 */
export function getBool(obj, key) {
  const v = obj?.[key];
  return typeof v === 'boolean' ? v : undefined;
}

/**
 * 从 JS 对象中安全获取子对象
 */
export function getObject(obj, key) {
  const v = obj?.[key];
  return v !== null && typeof v === 'object' && !Array.isArray(v) ? v : undefined;
}

/**
 * 从 JS 对象中安全获取数组
 */
export function getArray(obj, key) {
  const v = obj?.[key];
  return Array.isArray(v) ? v : undefined;
}

/**
 * 读取必需字符串字段，不存在则抛出异常
 */
export function requireString(obj, key) {
  const v = getString(obj, key);
  if (v === undefined) throw new Error(`missing field: ${key}`);
  return v;
}

/**
 * URL 百分号编码（UTF-8）
 */
export function urlEncode(value) {
  return encodeURIComponent(value);
}

/**
 * 将键值对构建为 URL 查询字符串
 */
export function buildQuery(params) {
  const entries = Object.entries(params).filter(([, v]) => v !== '' && v !== undefined);
  if (entries.length === 0) return '';
  return entries
    .map(([k, v]) => `${urlEncode(k)}=${urlEncode(String(v))}`)
    .join('&');
}

/**
 * 解析 JSON 字符串，失败时抛出异常并携带上下文
 */
export function parseJson(body, context) {
  try {
    return JSON.parse(body);
  } catch (e) {
    throw new Error(`failed to parse ${context}: ${e.message}`);
  }
}
