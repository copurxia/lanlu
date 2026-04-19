import axios, { AxiosInstance, InternalAxiosRequestConfig, AxiosResponse, AxiosError } from 'axios';
import { extractApiError } from '@/lib/utils/api-utils';

export interface AuthRequestConfig extends InternalAxiosRequestConfig {
  skipAuthRedirect?: boolean;
}

export type ApiResponseData = Record<string, unknown>;
export type ApiSuccessResult<T = ApiResponseData> = {
  success: true;
  data: T;
};
export type ApiFailureResult = {
  success: false;
  error: string;
};
export type ApiResult<T = ApiResponseData> = ApiSuccessResult<T> | ApiFailureResult;

// 区分服务端和客户端的API配置
const getApiConfig = () => {
  const configuredBaseUrl = (process.env.NEXT_PUBLIC_API_URL || '').trim();

  if (typeof window === 'undefined') {
    return {
      baseURL: configuredBaseUrl || 'http://localhost:8080',
      skipRequest: false
    };
  }

  return {
    baseURL: configuredBaseUrl || '',
    skipRequest: false
  };
};

const { baseURL, skipRequest } = getApiConfig();
const API_KEY = process.env.NEXT_PUBLIC_API_KEY || '';

/**
 * 获取认证 Token
 */
export function getAuthToken(): string | null {
  if (typeof window !== 'undefined') {
    return null;
  }
  return API_KEY || null;
}

/**
 * 通用请求拦截器
 */
function createRequestInterceptor(config: InternalAxiosRequestConfig): InternalAxiosRequestConfig {
  const token = getAuthToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
}

/**
 * 通用响应错误处理
 */
function handleResponseError(error: AxiosError, logPrefix: string = 'API'): Promise<never> {
  console.error(`${logPrefix} Error:`, error.response?.data ?? error.message);

  const requestConfig = error.config as AuthRequestConfig | undefined;
  const sessionInvalid = error?.response?.headers?.['x-auth-session-invalid'] === '1';
  if (error?.response?.status === 401 && sessionInvalid && !requestConfig?.skipAuthRedirect) {
    if (typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent('auth:unauthorized'));
    }
  }

  return Promise.reject(error);
}

/**
 * 为 Axios 实例添加拦截器
 */
function setupInterceptors(client: AxiosInstance, logPrefix: string = 'API'): void {
  client.interceptors.request.use(createRequestInterceptor, (error) => Promise.reject(error));
  client.interceptors.response.use(
    (response: AxiosResponse) => response,
    (error: AxiosError) => handleResponseError(error, logPrefix)
  );
}

export const apiClient = axios.create({
  baseURL,
  headers: { 'Content-Type': 'application/json' },
  timeout: 10000,
  withCredentials: true
});

export const uploadClient = axios.create({
  baseURL,
  headers: { 'Content-Type': 'application/json' },
  timeout: 0,
  withCredentials: true
});

// 统一设置拦截器
setupInterceptors(apiClient, 'API');
setupInterceptors(uploadClient, 'Upload API');

export { skipRequest };

export const getApiUrl = (path: string): string => `${baseURL}${path}`;

// API wrapper functions
export const api = {
  get: async <T = ApiResponseData>(url: string): Promise<ApiResult<T>> => {
    try {
      const response = await apiClient.get<T>(url);
      return {
        success: true,
        data: response.data
      };
    } catch (error) {
      return {
        success: false,
        error: extractApiError(error, 'Request failed')
      };
    }
  },

  post: async <T = ApiResponseData, TBody = unknown>(url: string, data?: TBody): Promise<ApiResult<T>> => {
    try {
      const response = await apiClient.post<T>(url, data);
      return {
        success: true,
        data: response.data
      };
    } catch (error) {
      return {
        success: false,
        error: extractApiError(error, 'Request failed')
      };
    }
  },

  put: async <T = ApiResponseData, TBody = unknown>(url: string, data?: TBody): Promise<ApiResult<T>> => {
    try {
      const response = await apiClient.put<T>(url, data);
      return {
        success: true,
        data: response.data
      };
    } catch (error) {
      return {
        success: false,
        error: extractApiError(error, 'Request failed')
      };
    }
  },

  delete: async <T = ApiResponseData>(url: string): Promise<ApiResult<T>> => {
    try {
      const response = await apiClient.delete<T>(url);
      return {
        success: true,
        data: response.data
      };
    } catch (error) {
      return {
        success: false,
        error: extractApiError(error, 'Request failed')
      };
    }
  }
};

export default apiClient;
