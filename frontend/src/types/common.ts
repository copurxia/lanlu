/**
 * 通用 API 类型定义
 */

/**
 * API 响应包装器
 */
export type ApiEnvelope<T> = {
  code: number;
  message: string;
  data: T;
};

/**
 * 分页响应
 */
export interface PaginatedResponse<T> {
  data: T[];
  draw?: number;
  recordsFiltered: number;
  recordsTotal: number;
}

/**
 * 操作结果
 */
export interface OperationResult {
  success: boolean;
  error?: string;
  message?: string;
}
