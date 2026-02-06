import axios, { AxiosInstance, InternalAxiosRequestConfig, AxiosResponse, AxiosError } from 'axios';

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

function setAuthTokenCookie(token: string | null): void {
  if (typeof document === 'undefined') return;

  if (!token) {
    document.cookie = 'auth_token=; Path=/; Max-Age=0; SameSite=Lax';
    return;
  }

  document.cookie = `auth_token=${token}; Path=/; Max-Age=${60 * 60 * 24 * 30}; SameSite=Lax`;
}

/**
 * 获取认证 Token
 */
export function getAuthToken(): string | null {
  return (typeof window !== 'undefined' ? localStorage.getItem('auth_token') : null) || API_KEY || null;
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
  console.error(`${logPrefix} Error:`, (error.response?.data as any) || error.message);

  if (error?.response?.status === 401) {
    if (typeof window !== 'undefined') {
      localStorage.removeItem('auth_token');
      setAuthTokenCookie(null);
      window.dispatchEvent(new CustomEvent('auth:unauthorized'));
      const currentPath = window.location.pathname;
      const redirectParam = currentPath === '/' ? '' : `?redirect=${encodeURIComponent(currentPath)}`;
      window.location.href = `/login${redirectParam}`;
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
  timeout: 10000
});

export const uploadClient = axios.create({
  baseURL,
  headers: { 'Content-Type': 'application/json' },
  timeout: 300000
});

// 统一设置拦截器
setupInterceptors(apiClient, 'API');
setupInterceptors(uploadClient, 'Upload API');

export { skipRequest, setAuthTokenCookie };

export const getApiUrl = (path: string): string => `${baseURL}${path}`;

// API wrapper functions
export const api = {
  get: async (url: string) => {
    try {
      const response = await apiClient.get(url);
      return {
        success: true,
        data: response.data
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.message || error.message || 'Request failed'
      };
    }
  },

  post: async (url: string, data?: any) => {
    try {
      const response = await apiClient.post(url, data);
      return {
        success: true,
        data: response.data
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.message || error.message || 'Request failed'
      };
    }
  },

  put: async (url: string, data?: any) => {
    try {
      const response = await apiClient.put(url, data);
      return {
        success: true,
        data: response.data
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.message || error.message || 'Request failed'
      };
    }
  },

  delete: async (url: string) => {
    try {
      const response = await apiClient.delete(url);
      return {
        success: true,
        data: response.data
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.message || error.message || 'Request failed'
      };
    }
  }
};

export default apiClient;
