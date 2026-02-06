/**
 * API 响应处理工具函数
 */

/**
 * 检查 API 响应是否成功
 * 兼容多种成功值格式: true, 1, "1", "true"
 */
export function isSuccessResponse(value: unknown): boolean {
  return value === true || value === 1 || value === '1' || value === 'true';
}

/**
 * 从错误对象中提取错误信息
 */
export function extractApiError(
  error: unknown,
  defaultMessage: string = 'Operation failed'
): string {
  if (!error) return defaultMessage;

  if (typeof error === 'string') {
    return error;
  }

  const e = error as {
    response?: { data?: { error?: string; message?: string } };
    message?: string;
  };

  if (e.response?.data?.error || e.response?.data?.message) {
    return e.response?.data?.error || e.response?.data?.message || defaultMessage;
  }

  if (error instanceof Error) {
    return error.message;
  }

  return e.message || defaultMessage;
}

/**
 * 规范化数组响应
 * 确保返回值始终是数组
 */
export function normalizeArrayResponse<T>(data: T | T[] | null | undefined): T[] {
  if (!data) return [];
  return Array.isArray(data) ? data : [data];
}

/**
 * 构建 URL 查询参数
 * 自动过滤 undefined 和 null 值
 */
export function buildQueryParams(
  params: Record<string, string | number | boolean | undefined | null>
): URLSearchParams {
  const searchParams = new URLSearchParams();

  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') {
      searchParams.append(key, String(value));
    }
  }

  return searchParams;
}

/**
 * 创建带错误处理的 API 调用包装器
 */
export async function safeApiCall<T>(
  apiCall: () => Promise<T>,
  defaultValue: T,
  errorMessage?: string
): Promise<T> {
  try {
    return await apiCall();
  } catch (error) {
    console.error(errorMessage || 'API call failed:', error);
    return defaultValue;
  }
}
