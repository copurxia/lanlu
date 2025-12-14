import axios from 'axios';

// 区分服务端和客户端的API配置
const getApiConfig = () => {
  const configuredBaseUrl = (process.env.NEXT_PUBLIC_API_URL || '').trim();

  // 静态生成时也要调用API，使用环境变量配置的API地址
  if (typeof window === 'undefined') {
    return {
      baseURL: configuredBaseUrl || 'http://localhost:8080',
      skipRequest: false // 静态生成时也要调用API
    };
  }

  // 客户端默认使用相对路径；若显式配置了 NEXT_PUBLIC_API_URL，则使用它（便于 next dev 单独运行）
  return {
    baseURL: configuredBaseUrl || '', // 空字符串表示相对路径，会自动使用当前域名和端口
    skipRequest: false
  };
};

const { baseURL, skipRequest } = getApiConfig();
const API_KEY = process.env.NEXT_PUBLIC_API_KEY || '';

export const apiClient = axios.create({
  baseURL,
  headers: {
    'Content-Type': 'application/json'
  },
  timeout: 10000 // 默认10秒，用于普通API请求
});

// 创建专门用于上传的客户端，具有更长的超时时间
export const uploadClient = axios.create({
  baseURL,
  headers: {
    'Content-Type': 'application/json'
  },
  timeout: 300000 // 5分钟超时，用于上传请求
});

// 为上传客户端添加请求拦截器
uploadClient.interceptors.request.use(
  (config) => {
    const token =
      (typeof window !== 'undefined' ? localStorage.getItem('auth_token') : null) || API_KEY;
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// 为上传客户端添加响应拦截器
uploadClient.interceptors.response.use(
  (response) => response,
  (error) => {
    console.error('Upload API Error:', error.response?.data || error.message);
    return Promise.reject(error);
  }
);

// 请求拦截器 - 动态设置 Authorization 头
apiClient.interceptors.request.use(
  (config) => {
    const token =
      (typeof window !== 'undefined' ? localStorage.getItem('auth_token') : null) || API_KEY;
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// 导出skipRequest标志，用于在静态生成期间跳过API调用
export { skipRequest };


// 响应拦截器
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    console.error('API Error:', error.response?.data || error.message);

    // 如果是 401 未授权，清空 token
    if (error?.response?.status === 401 || error?.status === 401) {
      if (typeof window !== 'undefined') {
        localStorage.removeItem('auth_token');
        // 发送自定义事件，通知 AuthContext 更新状态
        window.dispatchEvent(new CustomEvent('auth:unauthorized'));
      }
    }

    return Promise.reject(error);
  }
);

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
